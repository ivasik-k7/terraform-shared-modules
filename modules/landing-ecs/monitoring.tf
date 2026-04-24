resource "aws_cloudwatch_log_group" "service" {
  for_each = local.services

  name              = each.value.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn

  tags = each.value.tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = var.create_cloudwatch_alarms ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-cpu-high"
  alarm_description   = "CPU utilization > ${each.value.alarm_cpu_threshold}% for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = each.value.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.cluster_name}-${each.key}"
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.alarm_actions

  tags = each.value.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.create_cloudwatch_alarms ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-memory-high"
  alarm_description   = "Memory utilization > ${each.value.alarm_memory_threshold}% for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = each.value.alarm_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.cluster_name}-${each.key}"
  }

  alarm_actions = each.value.alarm_actions
  ok_actions    = each.value.alarm_actions

  tags = each.value.tags
}
