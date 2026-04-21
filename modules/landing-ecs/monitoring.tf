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
  alarm_description   = "CPU utilization > ${var.alarm_cpu_threshold}% for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.cluster_name}-${each.key}"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = each.value.tags
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  for_each = var.create_cloudwatch_alarms ? local.services : {}

  alarm_name          = "${var.cluster_name}-${each.key}-memory-high"
  alarm_description   = "Memory utilization > ${var.alarm_memory_threshold}% for ${each.key}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "MemoryUtilization"
  namespace           = "AWS/ECS"
  period              = 60
  statistic           = "Average"
  threshold           = var.alarm_memory_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    ClusterName = var.cluster_name
    ServiceName = "${var.cluster_name}-${each.key}"
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = each.value.tags
}

# Auto-generated dashboard layout: one row per service (CPU left, memory
# right), plus a shared running-task-count widget at the bottom.
locals {
  # Only evaluated when the dashboard is on, so plans stay cheap when it's off.
  dashboard_widgets = !var.create_cloudwatch_dashboard ? [] : flatten([
    # per-service CPU + memory rows
    [
      for idx, svc_name in sort(keys(local.services)) : [
        {
          type   = "metric"
          x      = 0
          y      = idx * 6
          width  = 12
          height = 6
          properties = {
            title  = "CPU - ${svc_name}"
            region = local.region
            view   = "timeSeries"
            stat   = "Average"
            period = 60
            metrics = [
              ["AWS/ECS", "CPUUtilization", "ClusterName", var.cluster_name, "ServiceName", "${var.cluster_name}-${svc_name}", { label = "CPU %" }]
            ]
            annotations = {
              horizontal = [{ value = var.alarm_cpu_threshold, label = "Alarm threshold", color = "#ff6961" }]
            }
            yAxis = { left = { min = 0, max = 100 } }
          }
        },
        {
          type   = "metric"
          x      = 12
          y      = idx * 6
          width  = 12
          height = 6
          properties = {
            title  = "Memory - ${svc_name}"
            region = local.region
            view   = "timeSeries"
            stat   = "Average"
            period = 60
            metrics = [
              ["AWS/ECS", "MemoryUtilization", "ClusterName", var.cluster_name, "ServiceName", "${var.cluster_name}-${svc_name}", { label = "Memory %" }]
            ]
            annotations = {
              horizontal = [{ value = var.alarm_memory_threshold, label = "Alarm threshold", color = "#ff6961" }]
            }
            yAxis = { left = { min = 0, max = 100 } }
          }
        }
      ]
    ],
    # shared running-task-count row (one metric per service)
    [
      {
        type   = "metric"
        x      = 0
        y      = length(local.services) * 6
        width  = 24
        height = 6
        properties = {
          title  = "Running task count - all services"
          region = local.region
          view   = "timeSeries"
          stat   = "Average"
          period = 60
          metrics = [
            for svc_name in sort(keys(local.services)) : [
              "ECS/ContainerInsights", "RunningTaskCount",
              "ClusterName", var.cluster_name,
              "ServiceName", "${var.cluster_name}-${svc_name}",
              { label = svc_name }
            ]
          ]
        }
      }
    ]
  ])
}

resource "aws_cloudwatch_dashboard" "this" {
  count = var.create_cloudwatch_dashboard ? 1 : 0

  dashboard_name = var.cluster_name
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
