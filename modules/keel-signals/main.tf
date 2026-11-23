locals {
  create = var.create

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "eu-west-2")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  module_tags = { ManagedBy = "Terraform", Module = "keel-signals" }
  tags        = merge(var.tags, local.module_tags)

  severities = local.create ? toset(["info", "warning", "high", "critical"]) : toset([])
  forward    = local.create ? var.control_plane_bus_arn != "" : false
  bridged    = local.forward ? local.severities : toset([])

  default_bus_arn = "arn:${local.partition}:events:${local.region}:${local.account_id}:event-bus/default"
  emails          = flatten([for s, list in var.emails : [for e in list : { severity = s, email = e }]])
}

# ---------------------------------------------------------------------------
# Severity topics: budgets, anomaly alerts and alarms publish here
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "severity" {
  for_each = local.severities

  name              = "${var.name}-${each.key}"
  kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags              = merge(local.tags, { Severity = upper(each.key) })
}

# The publishing principals AWS documents for Budgets and Anomaly Detection.
# https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-sns-policy.html
# https://docs.aws.amazon.com/cost-management/latest/userguide/ad-SNS.html
resource "aws_sns_topic_policy" "severity" {
  for_each = aws_sns_topic.severity

  arn = each.value.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = ["SNS:Publish", "SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:ListSubscriptionsByTopic"]
        Resource  = each.value.arn
      },
      {
        Sid       = "BudgetsPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = each.value.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:budgets::${local.account_id}:*" }
        }
      },
      {
        Sid       = "AnomalyDetectionPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = each.value.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
      {
        Sid       = "CloudWatchPublish"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = each.value.arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "emails" {
  for_each = { for e in local.emails : "${e.severity}/${e.email}" => e if local.create }

  topic_arn = aws_sns_topic.severity[each.value.severity].arn
  protocol  = "email"
  endpoint  = each.value.email
}

# ---------------------------------------------------------------------------
# Topics to EventBridge: SNS to SQS, then a pipe per severity to the default
# bus. A pipe can target only the default bus of its own account and Region,
# so a rule forwards from there.
# https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-pipes-event-target.html
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "signals" {
  count = local.forward ? 1 : 0

  name                      = "${var.name}-signals"
  message_retention_seconds = 345600
  kms_master_key_id         = var.kms_key_arn != "" ? var.kms_key_arn : null
  sqs_managed_sse_enabled   = var.kms_key_arn == "" ? true : null
  tags                      = local.tags
}

resource "aws_sqs_queue_policy" "signals" {
  count = local.forward ? 1 : 0

  queue_url = aws_sqs_queue.signals[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SeverityTopics"
      Effect    = "Allow"
      Principal = { Service = "sns.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.signals[0].arn
      Condition = { ArnEquals = { "aws:SourceArn" = [for t in aws_sns_topic.severity : t.arn] } }
    }]
  })
}

resource "aws_sns_topic_subscription" "to_queue" {
  for_each = local.bridged

  topic_arn = aws_sns_topic.severity[each.key].arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.signals[0].arn

  depends_on = [aws_sqs_queue_policy.signals]
}

resource "aws_iam_role" "pipes" {
  count = local.forward ? 1 : 0

  name_prefix          = "${substr(var.name, 0, 20)}-signal-pipes-"
  description          = "EventBridge Pipes moving ${var.name}'s signals from the queue to the default bus"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "pipes.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "pipes" {
  count = local.forward ? 1 : 0

  name = "queue-to-bus"
  role = aws_iam_role.pipes[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        { Sid = "ReadQueue", Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.signals[0].arn },
        { Sid = "PutOnDefaultBus", Effect = "Allow", Action = "events:PutEvents", Resource = local.default_bus_arn },
      ],
      var.kms_key_arn == "" ? [] : [{
        Sid       = "DecryptQueue"
        Effect    = "Allow"
        Action    = "kms:Decrypt"
        Resource  = var.kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = "sqs.${local.region}.amazonaws.com" } }
      }],
    )
  })
}

# One pipe per severity, selected by the topic the message came through; the
# severity travels in the event source (keel.<severity>).
resource "aws_pipes_pipe" "severity" {
  for_each = local.bridged

  name     = "${var.name}-${each.key}-signals"
  role_arn = aws_iam_role.pipes[0].arn
  source   = aws_sqs_queue.signals[0].arn
  target   = local.default_bus_arn
  tags     = local.tags

  source_parameters {
    filter_criteria {
      filter {
        pattern = jsonencode({ body = { TopicArn = [aws_sns_topic.severity[each.key].arn] } })
      }
    }
    sqs_queue_parameters {
      batch_size = 1
    }
  }

  target_parameters {
    eventbridge_event_bus_parameters {
      source      = "keel.${each.key}"
      detail_type = "Keel Signal"
    }
  }

  depends_on = [aws_iam_role_policy.pipes]
}

# ---------------------------------------------------------------------------
# Default bus to the control plane
# ---------------------------------------------------------------------------

locals {
  forward_rules = !local.forward ? {} : merge(
    { signals = jsonencode({ source = [{ prefix = "keel." }] }) },
    length(var.forward.alarm_name_prefixes) == 0 ? {} : {
      alarms = jsonencode({
        source        = ["aws.cloudwatch"]
        "detail-type" = ["CloudWatch Alarm State Change"]
        detail        = { alarmName = [for p in var.forward.alarm_name_prefixes : { prefix = p }] }
      })
    },
    !var.forward.anomalies ? {} : {
      anomalies = jsonencode({ source = ["aws.ce"], "detail-type" = ["Anomaly Detected"] })
    },
  )
}

resource "aws_cloudwatch_event_rule" "forward" {
  for_each = local.forward_rules

  name          = "${var.name}-${each.key}-to-control-plane"
  description   = "${each.key} to the Keel control plane"
  event_pattern = each.value
  tags          = local.tags
}

resource "aws_cloudwatch_event_target" "forward" {
  for_each = aws_cloudwatch_event_rule.forward

  rule     = each.value.name
  arn      = var.control_plane_bus_arn
  role_arn = aws_iam_role.forward[0].arn
}

resource "aws_iam_role" "forward" {
  count = local.forward ? 1 : 0

  name_prefix          = "${substr(var.name, 0, 20)}-signal-forward-"
  description          = "EventBridge forwarding ${var.name}'s signals to the Keel control plane bus"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "forward" {
  count = local.forward ? 1 : 0

  name = "put-events"
  role = aws_iam_role.forward[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "events:PutEvents", Resource = var.control_plane_bus_arn }]
  })
}
