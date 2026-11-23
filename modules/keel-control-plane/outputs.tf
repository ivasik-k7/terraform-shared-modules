# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

output "event_bus_arn" {
  description = "The Keel event bus. Give it to keel-billing and keel-team as signals.control_plane_bus_arn."
  value       = local.bus_arn
}

output "topic_arns" {
  description = "The severity topics, by severity (info, warning, high, critical). Subscribe chat, ticketing or paging tools here."
  value       = local.topic_arns
}

output "evidence_bucket" {
  description = "The Object Lock bucket every signal is kept in, under events/yyyy/MM/dd/."
  value       = local.create ? local.evidence_bucket : null
}

output "dead_letter_queue_arn" {
  description = "Where signals EventBridge could not deliver wait. An alarm watches it."
  value       = one(aws_sqs_queue.dead_letters[*].arn)
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

output "routing" {
  description = "How signals map to severities, as data: for the register and for the people subscribing."
  value = !local.create ? null : {
    anomaly = {
      info     = "impact below ${var.severity.anomaly_warning}"
      warning  = "impact ${var.severity.anomaly_warning} to ${var.severity.anomaly_high}"
      high     = "impact ${var.severity.anomaly_high} to ${var.severity.anomaly_critical}"
      critical = "impact ${var.severity.anomaly_critical} or more"
    }
    alarms = {
      critical = "alarm names ending ${var.severity.critical_alarm_suffix}"
      high     = "every other alarm forwarded to the bus"
    }
    keel_events = "source keel, detail.severity info, warning, high or critical"
    signals     = "source keel.<severity> (keel-signals): budgets, limit anomalies and alarms published to an account's severity topic, routed at that severity"
  }
}

output "controls" {
  description = "The Keel controls this module implements, as register entries."
  value = !local.create ? null : {
    "FC-05" = {
      statement      = "A cost anomaly reaches an owner within a day"
      type           = "Detect"
      threshold      = "Routed by impact: ${var.severity.anomaly_warning} / ${var.severity.anomaly_high} / ${var.severity.anomaly_critical}"
      evidence       = "The anomaly event in the evidence bucket; topic delivery"
      implemented_by = sort([for r in aws_cloudwatch_event_rule.anomaly : r.name])
    }
    "FC-08" = {
      statement      = "Every alert and action is recorded, immutably"
      type           = "Prove"
      threshold      = "${var.evidence.retention_days} days, ${var.evidence.mode} mode"
      evidence       = "s3://${local.evidence_bucket}/events/; the bus archive for ${var.evidence.archive_days} days"
      implemented_by = [aws_kinesis_firehose_delivery_stream.evidence[0].name, local.evidence_bucket]
    }
  }
}

output "kms_key_policy_requirements" {
  description = "What the customer managed key must allow, in contract version 2: the evidence bucket's entries from modules/s3 (prefixed Evidence) and the services that use the topics and queue."
  value = !local.create || var.kms_key_arn == "" ? null : concat(
    [for r in coalesce(module.evidence.kms_key_policy_requirements, []) : merge(r, { sid = "Evidence${r.sid}" }) if !contains(["BucketWriters", "BucketReaders"], r.sid)],
    [
      {
        key        = var.kms_key_arn
        sid        = "EvidenceStream"
        principals = { services = [], arns = [aws_iam_role.firehose[0].arn], roles = [] }
        actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
        purpose    = "Data Firehose writes encrypted evidence objects."
      },
      {
        key        = var.kms_key_arn
        sid        = "EventBridgeToEncryptedTopicsAndQueue"
        principals = { services = ["events.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
        purpose    = "EventBridge publishes to the encrypted severity topics and the dead-letter queue."
      },
      {
        key        = var.kms_key_arn
        sid        = "HealthAlarmsToEncryptedTopic"
        principals = { services = ["cloudwatch.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
        conditions = [{ test = "StringEquals", variable = "aws:SourceAccount", values = [local.account_id] }]
        purpose    = "The control plane's own alarms publish to the encrypted HIGH topic."
      },
    ],
  )
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs in the FinOps account, besides modules/s3's for the evidence bucket."
  value = !local.create ? null : {
    actions = [
      "events:CreateEventBus", "events:DeleteEventBus", "events:PutPermission", "events:RemovePermission", "events:DescribeEventBus",
      "events:CreateArchive", "events:DeleteArchive", "events:DescribeArchive", "events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:TagResource",
      "sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:GetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe", "sns:TagResource",
      "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:GetQueueAttributes", "sqs:TagQueue",
      "firehose:CreateDeliveryStream", "firehose:DeleteDeliveryStream", "firehose:UpdateDestination", "firehose:DescribeDeliveryStream", "firehose:StartDeliveryStreamEncryption", "firehose:TagDeliveryStream",
      "logs:CreateLogGroup", "logs:CreateLogStream", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:AssociateKmsKey",
      "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:GetRole", "iam:PassRole", "iam:TagRole",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms", "cloudwatch:TagResource",
    ]
  }
}

output "governance" {
  description = "The control plane's posture as data."
  value = !local.create ? null : {
    sources             = { organization = var.sources.organization_id, accounts = sort(var.sources.account_ids) }
    severity_emails     = { for s in local.severities : s => length(lookup(var.severity.emails, s, [])) }
    silent_severities   = local.silent_severities
    evidence            = { mode = var.evidence.mode, retention_days = var.evidence.retention_days, archive_days = var.evidence.archive_days }
    customer_key        = var.kms_key_arn != ""
    acknowledged_checks = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "Commands to run from CloudShell in the FinOps account: send a test signal and find it in the evidence."
  value = !local.create ? null : {
    test_signal   = "aws events put-events --entries '[{\"EventBusName\":\"${local.bus_name}\",\"Source\":\"keel\",\"DetailType\":\"Test\",\"Detail\":\"{\\\"severity\\\":\\\"info\\\",\\\"message\\\":\\\"Keel control plane test\\\"}\"}]'"
    evidence      = "aws s3 ls s3://${local.evidence_bucket}/events/ --recursive | tail -5"
    undelivered   = "aws sqs get-queue-attributes --queue-url ${one(aws_sqs_queue.dead_letters[*].url)} --attribute-names ApproximateNumberOfMessages"
    stream_errors = "aws logs tail /aws/kinesisfirehose/${var.name}-evidence --since 1h"
  }
}
