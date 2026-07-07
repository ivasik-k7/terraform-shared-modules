# deployment events -> sns via an extension association on the app.
# email subscriptions need manual confirmation. topic cost is noise.

resource "aws_sns_topic" "events" {
  count = local.create_topic ? 1 : 0

  name = "${var.name}-appconfig-events"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  for_each = local.create_topic ? toset(var.alert_emails) : toset([])

  topic_arn = aws_sns_topic.events[0].arn
  protocol  = "email"
  endpoint  = each.value
}

# publish role, scoped to the one topic
resource "aws_iam_role" "events" {
  count = local.create && var.enable_notifications ? 1 : 0

  name = "${var.name}-appconfig-events"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "appconfig.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "events" {
  count = local.create && var.enable_notifications ? 1 : 0

  name = "publish-deployment-events"
  role = aws_iam_role.events[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "Publish"
      Effect   = "Allow"
      Action   = ["sns:Publish"]
      Resource = local.topic_arn
    }]
  })
}

resource "aws_appconfig_extension" "events" {
  count = local.create && var.enable_notifications ? 1 : 0

  name        = "${var.name}-deployment-events"
  description = "Deployment lifecycle events for ${var.name} to SNS."

  dynamic "action_point" {
    for_each = toset(var.notification_points)
    content {
      point = action_point.value
      action {
        name     = "notify-${lower(replace(action_point.value, "_", "-"))}"
        uri      = local.topic_arn
        role_arn = aws_iam_role.events[0].arn
      }
    }
  }

  tags = local.common_tags
}

resource "aws_appconfig_extension_association" "events" {
  count = local.create && var.enable_notifications ? 1 : 0

  extension_arn = aws_appconfig_extension.events[0].arn
  resource_arn  = aws_appconfig_application.this[0].arn
}
