locals {
  create = var.create

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  module_tags = { ManagedBy = "Terraform", Module = "keel-limits" }
  tags        = merge(var.tags, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)

  default_denied_actions = [
    "ec2:RunInstances", "ec2:StartInstances", "ec2:CreateNatGateway", "ec2:AllocateAddress",
    "rds:CreateDBInstance", "rds:CreateDBCluster", "rds:StartDBInstance", "rds:StartDBCluster",
    "ecs:RunTask", "ecs:CreateService", "eks:CreateNodegroup", "lambda:CreateFunction",
    "sagemaker:Create*", "bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream",
    "glue:StartJobRun", "emr-serverless:StartJobRun", "elasticmapreduce:RunJobFlow",
  ]

  limits = local.create ? var.limits : {}

  spend_limits      = { for k, l in local.limits : k => l if contains(["COST", "USAGE"], l.type) }
  commitment_limits = { for k, l in local.limits : k => l if !contains(["COST", "USAGE"], l.type) }

  # The scope as filter elements, ANDed. One element is the filter itself; two
  # or more are joined with and.
  elements = { for k, l in local.limits : k => concat(
    [for tk in sort(keys(l.scope.tags)) : { kind = "tags", key = tk, values = l.scope.tags[tk] }],
    [for ck in sort(keys(l.scope.cost_categories)) : { kind = "cost_categories", key = ck, values = l.scope.cost_categories[ck] }],
    length(l.scope.accounts) > 0 ? [{ kind = "dimensions", key = "LINKED_ACCOUNT", values = l.scope.accounts }] : [],
    length(l.scope.services) > 0 ? [{ kind = "dimensions", key = "SERVICE", values = l.scope.services }] : [],
    length(l.scope.regions) > 0 ? [{ kind = "dimensions", key = "REGION", values = l.scope.regions }] : [],
    length(l.scope.usage_types) > 0 ? [{ kind = "dimensions", key = "USAGE_TYPE", values = l.scope.usage_types }] : [],
    length(l.scope.usage_type_groups) > 0 ? [{ kind = "dimensions", key = "USAGE_TYPE_GROUP", values = l.scope.usage_type_groups }] : [],
  ) }

  # Every threshold with its severity: a forecast is a WARNING; actual spend is
  # a WARNING below the limit, HIGH from it and CRITICAL from the tier's mark.
  notifications = { for k, l in local.spend_limits : k => concat(
    [for t in coalesce(l.forecast_thresholds, var.tiers[l.tier].forecast_thresholds) : { type = "FORECASTED", threshold = t, severity = "warning" }],
    [for t in coalesce(l.actual_thresholds, var.tiers[l.tier].actual_thresholds) : {
      type      = "ACTUAL"
      threshold = t
      severity  = t >= var.tiers[l.tier].critical_at_percent ? "critical" : (t >= 100 ? "high" : "warning")
    }],
  ) }
  needed_severities = toset(concat(
    flatten([for k, n in local.notifications : [for x in n : x.severity]]),
    length(local.commitment_limits) > 0 ? ["warning"] : [],
    [for k, l in local.anomaly_limits : var.tiers[l.tier].anomaly_severity],
  ))

  # An anomaly monitor watches exactly one tag key, one cost category or up to
  # ten accounts, with up to ten values.
  # https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_AnomalyMonitor.html
  anomaly_limits = { for k, l in local.limits : k => l if l.anomaly != null }
  monitor_specification = { for k, l in local.anomaly_limits : k => (
    length(local.elements[k]) != 1 ? "" : (
      local.elements[k][0].kind == "tags" ? jsonencode({ Tags = { Key = local.elements[k][0].key, Values = local.elements[k][0].values } }) : (
        local.elements[k][0].kind == "cost_categories" ? jsonencode({ CostCategories = { Key = local.elements[k][0].key, Values = local.elements[k][0].values } }) : (
          local.elements[k][0].key == "LINKED_ACCOUNT" ? jsonencode({ Dimensions = { Key = "LINKED_ACCOUNT", Values = local.elements[k][0].values } }) : ""
        )
      )
    )
  ) }

  lock_limits = { for k, l in local.spend_limits : k => l if l.action != null ? length(l.action.lock_roles) > 0 : false }
  scp_limits  = { for k, l in local.spend_limits : k => l if l.action != null ? l.action.scp != null : false }
}

# ---------------------------------------------------------------------------
# Spend and usage limits
# ---------------------------------------------------------------------------

resource "aws_budgets_budget" "spend" {
  for_each = local.spend_limits

  name         = "${var.name}-${each.key}"
  budget_type  = each.value.type
  limit_amount = each.value.auto_adjust_months > 0 ? null : each.value.amount
  limit_unit   = each.value.auto_adjust_months > 0 ? null : each.value.unit
  time_unit    = each.value.period
  tags         = local.tags

  dynamic "auto_adjust_data" {
    for_each = each.value.auto_adjust_months > 0 ? [1] : []
    content {
      auto_adjust_type = "HISTORICAL"
      historical_options {
        budget_adjustment_period = each.value.auto_adjust_months
      }
    }
  }

  # The provider takes metrics only with a filter; an unfiltered limit sets its
  # cost basis through cost_types.
  metrics = length(local.elements[each.key]) == 0 ? null : [each.value.type == "USAGE" ? "UsageQuantity" : each.value.metric]

  dynamic "cost_types" {
    for_each = length(local.elements[each.key]) == 0 ? [1] : []
    content {
      use_amortized = each.value.metric == "AmortizedCost"
      use_blended   = each.value.metric == "BlendedCost"
    }
  }

  dynamic "filter_expression" {
    for_each = length(local.elements[each.key]) == 0 ? [] : [local.elements[each.key]]
    content {
      # A single element is the expression.
      dynamic "tags" {
        for_each = length(filter_expression.value) == 1 && filter_expression.value[0].kind == "tags" ? filter_expression.value : []
        content {
          key    = tags.value.key
          values = tags.value.values
        }
      }
      dynamic "cost_categories" {
        for_each = length(filter_expression.value) == 1 && filter_expression.value[0].kind == "cost_categories" ? filter_expression.value : []
        content {
          key    = cost_categories.value.key
          values = cost_categories.value.values
        }
      }
      dynamic "dimensions" {
        for_each = length(filter_expression.value) == 1 && filter_expression.value[0].kind == "dimensions" ? filter_expression.value : []
        content {
          key    = dimensions.value.key
          values = dimensions.value.values
        }
      }
      # Two or more are joined with and.
      dynamic "and" {
        for_each = length(filter_expression.value) > 1 ? filter_expression.value : []
        content {
          dynamic "tags" {
            for_each = and.value.kind == "tags" ? [and.value] : []
            content {
              key    = tags.value.key
              values = tags.value.values
            }
          }
          dynamic "cost_categories" {
            for_each = and.value.kind == "cost_categories" ? [and.value] : []
            content {
              key    = cost_categories.value.key
              values = cost_categories.value.values
            }
          }
          dynamic "dimensions" {
            for_each = and.value.kind == "dimensions" ? [and.value] : []
            content {
              key    = dimensions.value.key
              values = dimensions.value.values
            }
          }
        }
      }
    }
  }

  dynamic "notification" {
    for_each = local.notifications[each.key]
    content {
      comparison_operator        = "GREATER_THAN"
      notification_type          = notification.value.type
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      subscriber_sns_topic_arns  = contains(keys(var.topic_arns), notification.value.severity) ? [var.topic_arns[notification.value.severity]] : []
      subscriber_email_addresses = each.value.owners
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.notifications[each.key]) <= 10
      error_message = "Limit ${each.key} has ${length(local.notifications[each.key])} thresholds; AWS Budgets allows ten notifications per budget."
    }
    # A notification needs at least one subscriber.
    # https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_budgets_NotificationWithSubscribers.html
    precondition {
      condition     = length(each.value.owners) > 0 ? true : alltrue([for n in local.notifications[each.key] : contains(keys(var.topic_arns), n.severity)])
      error_message = "Limit ${each.key} has no owners, and no topic for ${join(", ", distinct([for n in local.notifications[each.key] : upper(n.severity) if !contains(keys(var.topic_arns), n.severity)]))}: AWS Budgets refuses a notification with no subscriber. Add owners or those topics."
    }
  }
}

# ---------------------------------------------------------------------------
# Commitment limits: alert when coverage or utilization falls below target
# ---------------------------------------------------------------------------

# Commitment budgets measure against 100 percent with subscription costs only;
# RI budgets need one service.
# https://registry.terraform.io/providers/hashicorp/aws/6.57.1/docs/resources/budgets_budget
resource "aws_budgets_budget" "commitment" {
  for_each = local.commitment_limits

  name         = "${var.name}-${each.key}"
  budget_type  = each.value.type
  limit_amount = "100"
  limit_unit   = "PERCENTAGE"
  time_unit    = each.value.period
  tags         = local.tags

  cost_types {
    include_credit             = false
    include_discount           = false
    include_other_subscription = false
    include_recurring          = false
    include_refund             = false
    include_subscription       = true
    include_support            = false
    include_tax                = false
    include_upfront            = false
    use_blended                = false
  }

  dynamic "cost_filter" {
    for_each = length(each.value.scope.services) > 0 ? [1] : []
    content {
      name   = "Service"
      values = each.value.scope.services
    }
  }

  dynamic "cost_filter" {
    for_each = length(each.value.scope.accounts) > 0 ? [1] : []
    content {
      name   = "LinkedAccount"
      values = each.value.scope.accounts
    }
  }

  notification {
    comparison_operator        = "LESS_THAN"
    notification_type          = "ACTUAL"
    threshold                  = each.value.target_percent
    threshold_type             = "PERCENTAGE"
    subscriber_sns_topic_arns  = contains(keys(var.topic_arns), "warning") ? [var.topic_arns["warning"]] : []
    subscriber_email_addresses = each.value.owners
  }
}

# ---------------------------------------------------------------------------
# An anomaly monitor per limit, on exactly its scope
# ---------------------------------------------------------------------------

resource "aws_ce_anomaly_monitor" "this" {
  for_each = local.anomaly_limits

  name                  = "${var.name}-${each.key}"
  monitor_type          = "CUSTOM"
  monitor_specification = local.monitor_specification[each.key]
  tags                  = local.tags

  lifecycle {
    precondition {
      condition     = local.monitor_specification[each.key] != "" ? alltrue([for e in local.elements[each.key] : length(e.values) <= (e.kind == "cost_categories" ? 1 : 10)]) : false
      error_message = "Limit ${each.key} asks for an anomaly monitor, but a monitor watches exactly one tag key (up to ten values), one cost category (one value) or up to ten accounts; its scope has ${length(local.elements[each.key])} filters."
    }
    # https://docs.aws.amazon.com/cost-management/latest/userguide/management-limits.html
    precondition {
      condition     = contains(keys(var.topic_arns), var.tiers[each.value.tier].anomaly_severity)
      error_message = "Limit ${each.key}'s anomaly alerts go to the ${upper(var.tiers[each.value.tier].anomaly_severity)} topic, which topic_arns does not have; immediate anomaly alerts need an SNS topic."
    }
  }
}

resource "aws_ce_anomaly_subscription" "this" {
  for_each = local.anomaly_limits

  name             = "${var.name}-${each.key}"
  frequency        = "IMMEDIATE"
  monitor_arn_list = [aws_ce_anomaly_monitor.this[each.key].arn]
  tags             = local.tags

  subscriber {
    type    = "SNS"
    address = lookup(var.topic_arns, var.tiers[each.value.tier].anomaly_severity, "")
  }

  threshold_expression {
    dynamic "and" {
      for_each = each.value.anomaly.min_impact_percentage > 0 ? ["ABSOLUTE", "PERCENTAGE"] : []
      content {
        dimension {
          key           = "ANOMALY_TOTAL_IMPACT_${and.value}"
          match_options = ["GREATER_THAN_OR_EQUAL"]
          values        = [tostring(and.value == "ABSOLUTE" ? coalesce(each.value.anomaly.min_impact, var.tiers[each.value.tier].anomaly_min_impact) : each.value.anomaly.min_impact_percentage)]
        }
      }
    }
    dynamic "dimension" {
      for_each = each.value.anomaly.min_impact_percentage > 0 ? [] : [1]
      content {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(coalesce(each.value.anomaly.min_impact, var.tiers[each.value.tier].anomaly_min_impact))]
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Actions: a lock on roles, or an SCP, at the limit
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "lock" {
  for_each = local.lock_limits

  name        = "${var.name}-${each.key}-lock"
  description = "Attached by AWS Budgets when ${var.name}-${each.key} reaches its limit: denies the actions that start new spend."
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Sid = "LimitReached", Effect = "Deny", Action = coalesce(each.value.action.denied_actions, local.default_denied_actions), Resource = "*" }]
  })
  tags = local.tags
}

resource "aws_iam_role" "action" {
  for_each = merge(local.lock_limits, local.scp_limits)

  name_prefix          = "${substr("${var.name}-${each.key}", 0, 28)}-act-"
  description          = "AWS Budgets runs the action of limit ${var.name}-${each.key}"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:budgets::${local.account_id}:budget/*" }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "lock" {
  for_each = local.lock_limits

  name = "attach-lock"
  role = aws_iam_role.action[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AttachTheLockOnly"
      Effect    = "Allow"
      Action    = ["iam:AttachRolePolicy", "iam:DetachRolePolicy"]
      Resource  = flatten([for r in each.value.action.lock_roles : ["arn:${local.partition}:iam::${local.account_id}:role/${r}", "arn:${local.partition}:iam::${local.account_id}:role/*/${r}"]])
      Condition = { ArnEquals = { "iam:PolicyARN" = aws_iam_policy.lock[each.key].arn } }
    }]
  })
}

resource "aws_iam_role_policy" "scp" {
  for_each = local.scp_limits

  name = "apply-scp"
  role = aws_iam_role.action[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ApplyTheScpOnly"
      Effect = "Allow"
      Action = ["organizations:AttachPolicy", "organizations:DetachPolicy"]
      Resource = concat(
        ["arn:${local.partition}:organizations::${local.account_id}:policy/o-*/service_control_policy/${each.value.action.scp.policy_id}"],
        [for t in each.value.action.scp.target_ids : (
          startswith(t, "r-") ? "arn:${local.partition}:organizations::${local.account_id}:root/o-*/${t}" : (
            startswith(t, "ou-") ? "arn:${local.partition}:organizations::${local.account_id}:ou/o-*/${t}" :
            "arn:${local.partition}:organizations::${local.account_id}:account/o-*/${t}"
          )
        )],
      )
    }]
  })
}

resource "aws_budgets_budget_action" "this" {
  for_each = merge(local.lock_limits, local.scp_limits)

  budget_name        = aws_budgets_budget.spend[each.key].name
  action_type        = contains(keys(local.lock_limits), each.key) ? "APPLY_IAM_POLICY" : "APPLY_SCP_POLICY"
  approval_model     = each.value.action.approval
  notification_type  = "ACTUAL"
  execution_role_arn = aws_iam_role.action[each.key].arn
  tags               = local.tags

  action_threshold {
    action_threshold_type  = "PERCENTAGE"
    action_threshold_value = each.value.action.at_percent
  }

  definition {
    dynamic "iam_action_definition" {
      for_each = contains(keys(local.lock_limits), each.key) ? [1] : []
      content {
        policy_arn = aws_iam_policy.lock[each.key].arn
        roles      = each.value.action.lock_roles
      }
    }
    dynamic "scp_action_definition" {
      for_each = contains(keys(local.scp_limits), each.key) ? [1] : []
      content {
        policy_id  = each.value.action.scp.policy_id
        target_ids = each.value.action.scp.target_ids
      }
    }
  }

  subscriber {
    address           = lookup(var.topic_arns, "critical", "")
    subscription_type = "SNS"
  }

  lifecycle {
    precondition {
      condition     = contains(keys(var.topic_arns), "critical")
      error_message = "Limit ${each.key} has an action, which reports to the CRITICAL topic; topic_arns has none."
    }
  }

  depends_on = [aws_iam_role_policy.lock, aws_iam_role_policy.scp]
}
