# optional per-service alarms. cpu/memory come from AWS/ECS (always available);
# running-task-count needs Container Insights so it's gated on that.

resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  for_each = local.create && var.create_cloudwatch_alarms ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-cpu-high"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Service ${each.key} CPU above ${var.alarm_cpu_threshold}%"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}-cpu-high" })
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = local.create && var.create_cloudwatch_alarms ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-memory-high"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_memory_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Average"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Service ${each.key} memory above ${var.alarm_memory_threshold}%"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}-memory-high" })
}

# RunningTaskCount only exists under ECS/ContainerInsights.
resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  for_each = local.create && var.create_cloudwatch_alarms && var.enable_container_insights ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-running-tasks-low"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_min_running_tasks
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Average"
  treat_missing_data  = "breaching"
  alarm_description   = "Service ${each.key} running tasks below ${var.alarm_min_running_tasks}"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = each.key
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}-running-tasks-low" })
}
