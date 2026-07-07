# alarms on an env = automatic rollback while a deployment rolls out / bakes.
# aws caps monitors at 5 per env. the alarms are the caller's cost ($0.10/mo each).

resource "aws_appconfig_environment" "this" {
  for_each = local.create ? var.environments : {}

  application_id = aws_appconfig_application.this[0].id
  name           = each.key
  description    = each.value.description

  dynamic "monitor" {
    for_each = each.value.alarm_arns
    content {
      alarm_arn      = monitor.value
      alarm_role_arn = local.monitor_role_arn
    }
  }

  tags = merge(local.common_tags, each.value.tags)
}

# appconfig polls alarm state with this role; without it monitors do nothing,
# silently. DescribeAlarms has no resource-level auth, hence Resource = "*".
resource "aws_iam_role" "monitor" {
  count = local.create_monitor_role ? 1 : 0

  name = "${var.name}-appconfig-monitor"
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

resource "aws_iam_role_policy" "monitor" {
  count = local.create_monitor_role ? 1 : 0

  name = "read-alarm-state"
  role = aws_iam_role.monitor[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DescribeAlarms"
      Effect   = "Allow"
      Action   = ["cloudwatch:DescribeAlarms"]
      Resource = "*"
    }]
  })
}
