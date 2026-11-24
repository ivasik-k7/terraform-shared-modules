locals {
  create = var.create

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "eu-west-2")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  module_tags = { ManagedBy = "Terraform", Module = "keel-control-plane" }
  tags        = merge(var.tags, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)

  severities = ["info", "warning", "high", "critical"]
  bus_name   = var.name
  bus_arn    = one(aws_cloudwatch_event_bus.this[*].arn)
  topic_arns = { for s, t in aws_sns_topic.severity : s => t.arn }

  # Anomaly impact bands, by severity: [from, to). EventBridge numeric matching.
  # https://docs.aws.amazon.com/eventbridge/latest/userguide/eb-create-pattern-operators.html
  # Held as JSON: the bands and routes differ in shape, and for_each needs a map.
  anomaly_bands = {
    info     = jsonencode([">=", 0, "<", var.severity.anomaly_warning])
    warning  = jsonencode([">=", var.severity.anomaly_warning, "<", var.severity.anomaly_high])
    high     = jsonencode([">=", var.severity.anomaly_high, "<", var.severity.anomaly_critical])
    critical = jsonencode([">=", var.severity.anomaly_critical])
  }

  alarm_routes = {
    critical = jsonencode([{ suffix = var.severity.critical_alarm_suffix }])
    high     = jsonencode([{ "anything-but" = { suffix = var.severity.critical_alarm_suffix } }])
  }

  emails = flatten([for s, list in var.severity.emails : [for e in list : { severity = s, email = e }]])

  evidence_bucket     = "${var.name}-evidence-${local.account_id}-${local.region}"
  evidence_bucket_arn = "arn:${local.partition}:s3:::${local.evidence_bucket}"
}

# ---------------------------------------------------------------------------
# The bus
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_bus" "this" {
  count = local.create ? 1 : 0

  name = local.bus_name
  tags = local.tags
}

resource "aws_cloudwatch_event_bus_policy" "this" {
  count = local.create ? 1 : 0

  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      var.sources.organization_id == "" ? [] : [{
        Sid       = "Organization"
        Effect    = "Allow"
        Principal = "*"
        Action    = "events:PutEvents"
        Resource  = aws_cloudwatch_event_bus.this[0].arn
        Condition = {
          StringEquals = { "aws:PrincipalOrgID" = var.sources.organization_id }
          ArnLike      = { "aws:PrincipalArn" = var.sources.principal_arn_patterns }
        }
      }],
      length(var.sources.account_ids) == 0 ? [] : [{
        Sid       = "Accounts"
        Effect    = "Allow"
        Principal = { AWS = [for a in var.sources.account_ids : "arn:${local.partition}:iam::${a}:root"] }
        Action    = "events:PutEvents"
        Resource  = aws_cloudwatch_event_bus.this[0].arn
        Condition = { ArnLike = { "aws:PrincipalArn" = var.sources.principal_arn_patterns } }
      }],
    )
  })
}

resource "aws_cloudwatch_event_archive" "this" {
  count = local.create ? 1 : 0

  name             = "${var.name}-signals"
  description      = "Every Keel signal, for replay"
  event_source_arn = aws_cloudwatch_event_bus.this[0].arn
  retention_days   = var.evidence.archive_days
}

# ---------------------------------------------------------------------------
# Severity topics
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "severity" {
  for_each = local.create ? toset(local.severities) : toset([])

  name              = "${var.name}-${each.key}"
  kms_master_key_id = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags              = merge(local.tags, { Severity = upper(each.key) })
}

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
        Sid       = "KeelRules"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = each.value.arn
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${local.bus_name}/*" } }
      },
      {
        Sid       = "HealthAlarms"
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

resource "aws_sqs_queue" "dead_letters" {
  count = local.create ? 1 : 0

  name                      = "${var.name}-undelivered"
  message_retention_seconds = 1209600
  kms_master_key_id         = var.kms_key_arn != "" ? var.kms_key_arn : null
  sqs_managed_sse_enabled   = var.kms_key_arn == "" ? true : null
  tags                      = local.tags
}

resource "aws_sqs_queue_policy" "dead_letters" {
  count = local.create ? 1 : 0

  queue_url = aws_sqs_queue.dead_letters[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "KeelRules"
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.dead_letters[0].arn
      Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${local.bus_name}/*" } }
    }]
  })
}

# ---------------------------------------------------------------------------
# Routing: anomalies by impact, alarms by name, Keel events by their own field
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "anomaly" {
  for_each = local.create ? local.anomaly_bands : {}

  name           = "${var.name}-anomaly-${each.key}"
  description    = "Cost anomalies with a total impact in the ${upper(each.key)} band"
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  event_pattern = jsonencode({
    source        = ["aws.ce"]
    "detail-type" = ["Anomaly Detected"]
    detail        = { impact = { totalImpact = [{ numeric = jsondecode(each.value) }] } }
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "anomaly" {
  for_each = aws_cloudwatch_event_rule.anomaly

  rule           = each.value.name
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  arn            = aws_sns_topic.severity[each.key].arn

  input_transformer {
    input_paths = {
      impact  = "$.detail.impact.totalImpact"
      value   = "$.detail.dimensionValue"
      account = "$.detail.accountName"
      monitor = "$.detail.monitorName"
      link    = "$.detail.anomalyDetailsLink"
    }
    input_template = "\"${upper(each.key)} · Cost anomaly in <value> (<account>): impact <impact>, monitor <monitor>. <link>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.dead_letters[0].arn
  }
}

resource "aws_cloudwatch_event_rule" "alarm" {
  for_each = local.create ? local.alarm_routes : {}

  name           = "${var.name}-alarm-${each.key}"
  description    = "Cost alarms entering ALARM, routed as ${upper(each.key)}"
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  event_pattern = jsonencode({
    source        = ["aws.cloudwatch"]
    "detail-type" = ["CloudWatch Alarm State Change"]
    detail        = { state = { value = ["ALARM"] }, alarmName = jsondecode(each.value) }
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "alarm" {
  for_each = aws_cloudwatch_event_rule.alarm

  rule           = each.value.name
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  arn            = aws_sns_topic.severity[each.key].arn

  input_transformer {
    input_paths = {
      alarm   = "$.detail.alarmName"
      reason  = "$.detail.state.reason"
      account = "$.account"
    }
    input_template = "\"${upper(each.key)} · <alarm> in account <account>: <reason>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.dead_letters[0].arn
  }
}

resource "aws_cloudwatch_event_rule" "keel" {
  for_each = local.create ? toset(local.severities) : toset([])

  name           = "${var.name}-keel-${each.key}"
  description    = "Keel events that declare themselves ${upper(each.key)}"
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  event_pattern = jsonencode({
    source = ["keel"]
    detail = { severity = [each.key] }
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "keel" {
  for_each = aws_cloudwatch_event_rule.keel

  rule           = each.value.name
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  arn            = aws_sns_topic.severity[each.key].arn

  dead_letter_config {
    arn = aws_sqs_queue.dead_letters[0].arn
  }
}

# keel-signals moves what reaches an account's severity topics (budgets, limit
# anomalies, alarms) here as source keel.<severity>, with the SNS envelope in
# detail.sns.
resource "aws_cloudwatch_event_rule" "signal" {
  for_each = local.create ? toset(local.severities) : toset([])

  name           = "${var.name}-signal-${each.key}"
  description    = "Signals from the accounts' ${upper(each.key)} topics"
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  event_pattern = jsonencode({
    source        = ["keel.${each.key}"]
    "detail-type" = ["Keel Signal"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "signal" {
  for_each = aws_cloudwatch_event_rule.signal

  rule           = each.value.name
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  arn            = aws_sns_topic.severity[each.key].arn

  input_transformer {
    input_paths = {
      subject = "$.detail.sns.Subject"
      message = "$.detail.sns.Message"
      account = "$.account"
      region  = "$.region"
    }
    input_template = "\"${upper(each.key)} · <subject> (account <account>, <region>): <message>\""
  }

  dead_letter_config {
    arn = aws_sqs_queue.dead_letters[0].arn
  }
}
