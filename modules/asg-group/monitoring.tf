resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = local.cpu_alarm ? 1 : 0

  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "${var.name}: average CPU above ${var.alarm_cpu_percent}% for ${var.alarm_evaluation_periods} periods of ${var.alarm_period} seconds. With scaling at max_size, the fleet is out of headroom."
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  dimensions          = { AutoScalingGroupName = local.group_name }
  statistic           = "Average"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  tags = local.common_tags
}

# Missing data is breaching: a group with nothing in service publishes nothing.
resource "aws_cloudwatch_metric_alarm" "in_service_low" {
  count = local.in_service_alarm ? 1 : 0

  alarm_name          = "${var.name}-in-service-low"
  alarm_description   = "${var.name}: fewer than ${local.in_service_threshold} instances in service for ${var.alarm_evaluation_periods} periods of ${var.alarm_period} seconds. Launches are failing, or instances are being replaced faster than they become healthy."
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  dimensions          = { AutoScalingGroupName = local.group_name }
  statistic           = "Minimum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  comparison_operator = "LessThanThreshold"
  threshold           = local.in_service_threshold
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Events: the failures that leave an apply green.
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-event-reference.html
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name        = "${var.name}-${each.key}"
  description = each.value.description
  event_pattern = jsonencode({
    source        = ["aws.autoscaling"]
    "detail-type" = each.value.detail_type
    detail        = { AutoScalingGroupName = [local.group_name] }
  })

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "sns"
  arn       = var.sns_topic_arn
}
