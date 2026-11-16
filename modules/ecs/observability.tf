resource "aws_cloudwatch_log_group" "this" {
  for_each = local.created_log_groups

  name              = local.log_group_name[each.key]
  retention_in_days = local.log_retention[each.key]
  kms_key_id        = local.log_key[each.key] != "" ? local.log_key[each.key] : null
  skip_destroy      = var.log_skip_destroy

  tags = local.workload_tags[each.key]
}

# ---------------------------------------------------------------------------
# Alarms. Dimensions are the cluster and service names, as AWS/ECS publishes them.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each = local.alarmed

  alarm_name          = "${var.name}-${each.key}-cpu"
  alarm_description   = "${each.key} on ${var.name}: average CPU above ${each.value.alarms.cpu_percent > 0 ? each.value.alarms.cpu_percent : var.alarm_cpu_percent}% for ${var.alarm_evaluation_periods} periods of ${var.alarm_period} seconds. Tasks are CPU-starved; with autoscaling, it is at max or not keeping up."
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = { ClusterName = var.name, ServiceName = each.key }
  statistic           = "Average"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.alarms.cpu_percent > 0 ? each.value.alarms.cpu_percent : var.alarm_cpu_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  tags = local.workload_tags[each.key]
}

resource "aws_cloudwatch_metric_alarm" "memory" {
  for_each = local.alarmed

  alarm_name          = "${var.name}-${each.key}-memory"
  alarm_description   = "${each.key} on ${var.name}: average memory above ${each.value.alarms.memory_percent > 0 ? each.value.alarms.memory_percent : var.alarm_memory_percent}% for ${var.alarm_evaluation_periods} periods of ${var.alarm_period} seconds. A container that reaches its hard limit is killed (exit code 137)."
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = { ClusterName = var.name, ServiceName = each.key }
  statistic           = "Average"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.alarms.memory_percent > 0 ? each.value.alarms.memory_percent : var.alarm_memory_percent
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  tags = local.workload_tags[each.key]
}

# Missing data is breaching: a service with no running tasks publishes nothing.
resource "aws_cloudwatch_metric_alarm" "running_tasks" {
  for_each = local.running_task_alarms

  alarm_name          = "${var.name}-${each.key}-running-tasks"
  alarm_description   = "${each.key} on ${var.name}: fewer than ${each.value} running tasks for ${var.alarm_evaluation_periods} periods of ${var.alarm_period} seconds. Tasks are failing to start or being stopped faster than they are replaced."
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = { ClusterName = var.name, ServiceName = each.key }
  statistic           = "Minimum"
  period              = var.alarm_period
  evaluation_periods  = var.alarm_evaluation_periods
  comparison_operator = "LessThanThreshold"
  threshold           = each.value
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.ok_actions

  tags = local.workload_tags[each.key]
}

# ---------------------------------------------------------------------------
# Events: the failures that leave an apply green.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name          = "${var.name}-${each.key}"
  description   = each.value.description
  event_pattern = each.value.pattern

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "sns"
  arn       = var.sns_topic_arn
}
