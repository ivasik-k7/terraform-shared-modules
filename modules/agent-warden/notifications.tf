# One SNS topic backs every notification feature (real-time alerts, budget
# thresholds, daily digest, break-glass assumptions). Bring your own with
# alert_sns_topic_arn, or the module creates this one on demand.

resource "aws_sns_topic" "alerts" {
  count = local.create_topic ? 1 : 0

  name = "${var.name}-alerts"
  # SSE only with a CMK whose policy grants events/budgets; the AWS-managed
  # alias/aws/sns key can't be granted those, so it would block publishing.
  kms_master_key_id = var.alerts_kms_key_id != "" ? var.alerts_kms_key_id : null
  tags              = local.common_tags
}

# let CloudWatch/EventBridge and Budgets publish to the topic.
resource "aws_sns_topic_policy" "alerts" {
  count = local.create_topic ? 1 : 0

  arn = aws_sns_topic.alerts[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventBridgePublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts[0].arn
      },
      {
        Sid       = "AllowBudgetsPublish"
        Effect    = "Allow"
        Principal = { Service = "budgets.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts[0].arn
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.create_topic ? toset(var.alert_emails) : toset([])

  topic_arn = aws_sns_topic.alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}
