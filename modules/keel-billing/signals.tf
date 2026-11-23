# ---------------------------------------------------------------------------
# Severity topics for the organization's limits, forwarded to the control
# plane with the Anomaly Detected events
# ---------------------------------------------------------------------------

module "signals" {
  source = "../keel-signals"

  create                   = local.create
  name                     = var.name
  tags                     = local.tags
  kms_key_arn              = var.signals.kms_key_arn
  permissions_boundary_arn = var.permissions_boundary_arn
  emails                   = var.signals.emails
  control_plane_bus_arn    = var.signals.control_plane_bus_arn
  forward                  = { anomalies = local.forward_anomalies }
}

# ---------------------------------------------------------------------------
# The immediate anomaly alert's topic. Kept off the severity topics: the
# alert's Anomaly Detected event is what reaches the control plane, routed by
# impact there, so the SNS copy goes to people only.
# https://docs.aws.amazon.com/cost-management/latest/userguide/cad-eventbridge.html
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "anomaly_alerts" {
  count = local.alert ? 1 : 0

  name              = "${var.name}-anomaly-alerts"
  kms_master_key_id = var.signals.kms_key_arn != "" ? var.signals.kms_key_arn : null
  tags              = local.tags
}

# https://docs.aws.amazon.com/cost-management/latest/userguide/ad-SNS.html
resource "aws_sns_topic_policy" "anomaly_alerts" {
  count = local.alert ? 1 : 0

  arn = aws_sns_topic.anomaly_alerts[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountOwner"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
        Action    = ["SNS:Subscribe", "SNS:GetTopicAttributes", "SNS:SetTopicAttributes", "SNS:ListSubscriptionsByTopic"]
        Resource  = aws_sns_topic.anomaly_alerts[0].arn
      },
      {
        Sid       = "AnomalyDetectionPublish"
        Effect    = "Allow"
        Principal = { Service = "costalerts.amazonaws.com" }
        Action    = "SNS:Publish"
        Resource  = aws_sns_topic.anomaly_alerts[0].arn
        Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "anomaly_alerts" {
  for_each = local.alert ? toset(var.anomaly_detection.alert.emails) : toset([])

  topic_arn = aws_sns_topic.anomaly_alerts[0].arn
  protocol  = "email"
  endpoint  = each.value
}
