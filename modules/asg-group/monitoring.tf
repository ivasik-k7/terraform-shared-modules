# optional alarms. cpu_high comes from AWS/EC2 (per-ASG dimension); in_service_low
# uses GroupInServiceInstances (AWS/AutoScaling) which enabled_metrics collects.

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  count = local.create && var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-cpu-high"
  namespace           = "AWS/EC2"
  metric_name         = "CPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Node group ${var.name} average CPU above ${var.alarm_cpu_threshold}%"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this[0].name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.tags, { Name = "${var.name}-cpu-high" })
}

# GroupInServiceInstances only exists when enabled_metrics collects it -
# otherwise the alarm would sit in INSUFFICIENT_DATA / permanently breaching.
resource "aws_cloudwatch_metric_alarm" "in_service_low" {
  count = local.create && var.create_cloudwatch_alarms && contains(var.enabled_metrics, "GroupInServiceInstances") ? 1 : 0

  alarm_name          = "${var.name}-in-service-low"
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupInServiceInstances"
  comparison_operator = "LessThanThreshold"
  threshold           = coalesce(var.alarm_min_in_service, var.min_size)
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Average"
  treat_missing_data  = "breaching"
  alarm_description   = "Node group ${var.name} in-service instances below ${coalesce(var.alarm_min_in_service, var.min_size)}"

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this[0].name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.tags, { Name = "${var.name}-in-service-low" })
}
