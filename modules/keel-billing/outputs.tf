# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

output "topic_arns" {
  description = "The management account's severity topics in this Region, by severity: the organization's limits notify them, and they reach the control plane."
  value       = local.topic_arns
}

output "anomaly_alert_topic_arn" {
  description = "The immediate anomaly alert's topic: for people (anomaly_detection.alert.emails, a chat integration). The control plane gets the Anomaly Detected event instead."
  value       = one(aws_sns_topic.anomaly_alerts[*].arn)
}

output "cost_category_arns" {
  description = "Cost category ARNs, by name."
  value       = { for k, c in aws_ce_cost_category.this : k => c.arn }
}

output "anomaly_monitor_arns" {
  description = "Anomaly monitor ARNs, by key (services, accounts, category-<name>, tag-<key>)."
  value       = { for k, m in aws_ce_anomaly_monitor.this : k => m.arn }
}

output "budget_names" {
  description = "The organization's limits and commitment targets as budget names, by limit."
  value       = module.limits.budget_names
}

output "billing_view_arns" {
  description = "Custom billing view ARNs, by view. The accounts a view is shared with select it in Cost Explorer."
  value       = { for k, v in aws_billing_view.this : k => v.arn }
}

output "data_exports_stack" {
  description = "The CID data exports source stack: { name, outputs, template_url, reviewed_sha256 }, the last the sha256 of the template copy reviewed for this module (null for an unreviewed version). Null unless data_exports.enabled."
  value = !local.create || !var.data_exports.enabled ? null : {
    name            = aws_cloudformation_stack.data_exports_source[0].name
    outputs         = aws_cloudformation_stack.data_exports_source[0].outputs
    template_url    = aws_cloudformation_stack.data_exports_source[0].template_url
    reviewed_sha256 = local.data_exports_reviewed_sha256
  }
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

output "controls" {
  description = "The Keel controls this module implements, as register entries: FC-04, FC-05, ALLOCATION and LIMIT-<name> per limit and commitment target. Merge with the other Keel modules' to build the register."
  value = !local.create ? null : merge(
    length(local.spend_limit_keys) == 0 ? {} : {
      "FC-04" = {
        statement      = "A forecast overrun alerts the owner"
        type           = "Detect"
        threshold      = join("; ", [for k in local.spend_limit_keys : "${k}: ${join(", ", module.limits.thresholds[k])}"])
        evidence       = "Budget notification history; the signal on the control plane"
        implemented_by = sort([for k in local.spend_limit_keys : module.limits.budget_names[k]])
      }
    },
    length(local.active_monitors) == 0 ? {} : {
      "FC-05" = {
        statement = "A cost anomaly reaches an owner within a day"
        type      = "Detect"
        threshold = join("; ", concat(
          local.alert ? ["immediate from ${var.anomaly_detection.alert.min_impact_absolute}, routed by impact on the control plane"] : [],
          [for k, d in local.active_digests : "${k}: ${d.frequency} from ${d.min_impact_absolute}"],
        ))
        evidence       = "Anomaly history in Cost Anomaly Detection; Anomaly Detected events in the control plane's evidence store"
        implemented_by = sort([for k, m in aws_ce_anomaly_monitor.this : m.name])
      }
    },
    length(var.cost_categories) == 0 ? {} : {
      "ALLOCATION" = {
        statement      = "Spend is allocated to an owner through cost categories"
        type           = "Prevent"
        threshold      = "Default value ${join(", ", distinct([for c in var.cost_categories : c.default_value]))} shows what is unallocated"
        evidence       = "Cost category definitions (this configuration); the cost_category column of CUR 2.0"
        implemented_by = sort(keys(var.cost_categories))
      }
    },
    [for c in [module.limits.controls] : c if c != null]...
  )
}

output "finops_agent_setup" {
  description = "How the management account turns on AWS FinOps Agent's organization access, which Terraform cannot complete: the steps, the IAM policy the person doing it needs, and what the agent can then read. Null unless finops_agent.enabled."
  value = !local.finops_agent ? null : {
    console_region = "us-east-1"
    steps = concat(
      [
        "Acknowledge finops_agent_is_approved here once the data access below is approved.",
        "In the management account, us-east-1, open the AWS FinOps Agent console and enable organization-wide access. It creates AWSServiceRoleForFinOpsAgent and turns on trusted access with AWS Organizations.",
      ],
      var.finops_agent.delegated_admin_account_id == "" ? [] : [
        "Register ${var.finops_agent.delegated_admin_account_id} as the agent's delegated administrator: aws organizations register-delegated-administrator --account-id ${var.finops_agent.delegated_admin_account_id} --service-principal finops-agent.amazonaws.com",
      ],
      ["Check: aws organizations list-delegated-administrators --service-principal finops-agent.amazonaws.com"],
    )
    management_account_policy = jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [
          { Sid = "OrganizationAccess", Effect = "Allow", Action = ["finops-agent:GetOrganizationAccess", "finops-agent:UpdateOrganizationAccess"], Resource = "*" },
          {
            Sid       = "TrustedAccess"
            Effect    = "Allow"
            Action    = "organizations:EnableAWSServiceAccess"
            Resource  = "*"
            Condition = { StringEquals = { "organizations:ServicePrincipal" = "finops-agent.amazonaws.com" } }
          },
          {
            Sid       = "ServiceLinkedRole"
            Effect    = "Allow"
            Action    = "iam:CreateServiceLinkedRole"
            Resource  = "*"
            Condition = { StringEquals = { "iam:AWSServiceName" = "finops-agent.amazonaws.com" } }
          },
        ],
        var.finops_agent.delegated_admin_account_id == "" ? [] : [{
          Sid       = "DelegatedAdministrator"
          Effect    = "Allow"
          Action    = ["organizations:RegisterDelegatedAdministrator", "organizations:ListDelegatedAdministrators"]
          Resource  = "*"
          Condition = { StringEquals = { "organizations:ServicePrincipal" = "finops-agent.amazonaws.com" } }
        }],
      )
    })
    reads = "Every member account's cost, usage and resource data, CloudTrail events, CloudWatch metrics and CloudWatch Logs configuration (not log events), through a service-linked role SCPs do not restrict. Everyone who can use the organization-wide agent reads all of it; no account can be excluded."
  }
}

output "kms_key_policy_requirements" {
  description = "What the customer managed key in signals.kms_key_arn must allow, in contract version 2: the severity topics and queue (keel-signals) and the anomaly alert topic."
  value = !local.create || var.signals.kms_key_arn == "" ? null : concat(
    module.signals.kms_key_policy_requirements,
    !local.alert ? [] : [{
      key        = var.signals.kms_key_arn
      sid        = "AnomalyDetectionPublishToAnomalyAlerts"
      principals = { services = ["costalerts.amazonaws.com"], arns = [], roles = [] }
      actions    = ["kms:GenerateDataKey*", "kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
      purpose    = "Cost Anomaly Detection publishes the immediate alert to the encrypted anomaly alert topic."
    }],
  )
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs in the management account."
  value = !local.create ? null : {
    actions = concat(
      ["ce:TagResource", "ce:UntagResource", "ce:ListTagsForResource", "ce:UpdateCostAllocationTagsStatus", "ce:ListCostAllocationTags"],
      ["ce:CreateCostCategoryDefinition", "ce:UpdateCostCategoryDefinition", "ce:DeleteCostCategoryDefinition", "ce:DescribeCostCategoryDefinition"],
      ["ce:CreateAnomalyMonitor", "ce:UpdateAnomalyMonitor", "ce:DeleteAnomalyMonitor", "ce:GetAnomalyMonitors"],
      ["ce:CreateAnomalySubscription", "ce:UpdateAnomalySubscription", "ce:DeleteAnomalySubscription", "ce:GetAnomalySubscriptions"],
      ["budgets:ModifyBudget", "budgets:ViewBudget", "budgets:TagResource", "budgets:ListTagsForResource", "budgets:CreateBudgetAction", "budgets:UpdateBudgetAction", "budgets:DeleteBudgetAction", "budgets:DescribeBudgetAction"],
      ["cost-optimization-hub:UpdateEnrollmentStatus", "cost-optimization-hub:GetPreferences", "cost-optimization-hub:UpdatePreferences", "cost-optimization-hub:ListEnrollmentStatuses"],
      ["compute-optimizer:UpdateEnrollmentStatus", "compute-optimizer:GetEnrollmentStatus"],
      ["sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:GetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe", "sns:TagResource"],
      var.signals.control_plane_bus_arn == "" ? [] : ["sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:GetQueueAttributes", "sqs:TagQueue", "pipes:CreatePipe", "pipes:DeletePipe", "pipes:UpdatePipe", "pipes:DescribePipe", "pipes:TagResource", "events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:DescribeRule"],
      ["iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole", "iam:CreatePolicy", "iam:DeletePolicy"],
      length(local.billing_views) == 0 ? [] : ["billing:CreateBillingView", "billing:UpdateBillingView", "billing:DeleteBillingView", "billing:GetBillingView", "billing:ListBillingViews", "billing:TagResource"],
      length(local.shared_views) == 0 ? [] : ["ram:CreateResourceShare", "ram:DeleteResourceShare", "ram:AssociateResourceShare", "ram:DisassociateResourceShare", "ram:GetResourceShares", "ram:TagResource"],
      var.data_exports.enabled ? ["cloudformation:CreateStack", "cloudformation:UpdateStack", "cloudformation:DeleteStack", "cloudformation:DescribeStacks", "plus what the CID data exports template creates: IAM roles, S3, BCM Data Exports, Lambda"] : [],
    )
    service_linked_roles = var.optimization.compute_optimizer || var.optimization.cost_optimization_hub ? ["Compute Optimizer and Cost Optimization Hub create their own service-linked roles on enrollment"] : []
  }
}

output "governance" {
  description = "The posture as data: what is allocated, watched, budgeted and exported."
  value = !local.create ? null : {
    cost_allocation_tags   = sort(var.cost_allocation_tags)
    cost_categories        = sort(keys(var.cost_categories))
    inactive_category_tags = local.inactive_category_tags
    anomaly_monitors       = sort(keys(local.active_monitors))
    anomaly_alerts         = { for k, a in local.subscriptions : k => "${a.frequency} at ${a.min_impact_absolute}${a.min_impact_percentage > 0 ? " and ${a.min_impact_percentage}%" : ""}" }
    limits                 = module.limits.governance
    billing_views          = { for k, v in local.billing_views : k => { filter = length(v.accounts) > 0 ? "accounts ${join(", ", v.accounts)}" : "${v.tag.key} = ${join(" | ", v.tag.values)}", shared_with = sort(v.share_with) } }
    finops_agent           = !local.finops_agent ? null : { administrator = var.finops_agent.delegated_admin_account_id != "" ? var.finops_agent.delegated_admin_account_id : local.account_id, runs_in = "us-east-1", set_up_by = "the agent's console (output.finops_agent_setup)" }
    cost_optimization_hub  = var.optimization.cost_optimization_hub
    compute_optimizer      = var.optimization.compute_optimizer
    to_control_plane       = var.signals.control_plane_bus_arn != ""
    data_exports           = var.data_exports.enabled ? { destination = var.data_exports.destination_account_id, cur2 = var.data_exports.cur2, focus = var.data_exports.focus, coh = var.data_exports.coh, version = var.data_exports.version } : null
    acknowledged_checks    = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "Read-only commands to run from CloudShell in the management account after an apply."
  value = !local.create ? null : {
    cost_categories   = "aws ce list-cost-category-definitions --query 'CostCategoryReferences[].[Name,NumberOfRules]' --output table"
    allocation_tags   = "aws ce list-cost-allocation-tags --status Active --type UserDefined --query 'CostAllocationTags[].TagKey'"
    anomaly_monitors  = "aws ce get-anomaly-monitors --query 'AnomalyMonitors[].[MonitorName,MonitorDimension,LastEvaluatedDate]' --output table"
    recent_anomalies  = "aws ce get-anomalies --date-interval StartDate=$(date -d '-30 days' +%F) --query 'Anomalies[].[AnomalyStartDate,Impact.TotalImpact,DimensionValue]' --output table"
    budgets           = "aws budgets describe-budgets --account-id ${local.account_id} --query 'Budgets[].[BudgetName,BudgetLimit.Amount,CalculatedSpend.ForecastedSpend.Amount]' --output table"
    optimization_hub  = "aws cost-optimization-hub list-enrollment-statuses --include-organization-info"
    compute_optimizer = "aws compute-optimizer get-enrollment-status"
    data_exports      = "aws bcm-data-exports list-exports --region us-east-1"
    template          = !var.data_exports.enabled ? null : (local.data_exports_reviewed_sha256 == null ? "curl -fsS ${var.data_exports.template_url_prefix}/${local.data_exports_template} | sha256sum   # an unreviewed version: review it, then record its hash" : "test \"$(curl -fsS ${var.data_exports.template_url_prefix}/${local.data_exports_template} | sha256sum | cut -d' ' -f1)\" = ${local.data_exports_reviewed_sha256} && echo reviewed || echo CHANGED")
    billing_views     = "aws billing list-billing-views --region us-east-1 --query 'billingViews[].[name,billingViewType,arn]' --output table"
    finops_agent      = "aws organizations list-delegated-administrators --service-principal finops-agent.amazonaws.com"
  }
}
