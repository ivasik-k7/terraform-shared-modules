locals {
  alarm_actions    = var.sns_topic_arn != "" ? [var.sns_topic_arn] : []
  log_metric_space = "${local.monitoring_namespace}/${var.name}"

  log_metrics = merge([for k, p in local.active_pools : {
    "${k}-errors" = {
      pool    = k
      name    = "ManagerErrors-${k}"
      pattern = "{ $.level = \"error\" }"
    }
    "${k}-system-failures" = {
      pool    = k
      name    = "SystemFailures-${k}"
      pattern = "{ $.failure_reason = \"runner_system_failure\" }"
    }
  }]...)
  alarmed_pools = var.monitoring.alarms ? local.active_pools : {}
}

resource "aws_cloudwatch_log_metric_filter" "manager" {
  for_each = local.log_metrics

  name           = "${var.name}-${each.key}"
  log_group_name = module.managers.log_group_names[each.value.pool]
  pattern        = each.value.pattern

  metric_transformation {
    namespace     = local.log_metric_space
    name          = each.value.name
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

resource "aws_cloudwatch_metric_alarm" "manager_errors" {
  for_each = local.alarmed_pools

  alarm_name          = "${var.name}-${each.key}-manager-errors"
  alarm_description   = "The ${each.key} runner manager logged ${var.monitoring.error_threshold} or more errors in 15 minutes: GitLab unreachable, the plugin denied, instances failing their ready command. verify_commands.${each.key}.manager_logs."
  namespace           = local.log_metric_space
  metric_name         = local.log_metrics["${each.key}-errors"].name
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.monitoring.error_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags

  depends_on = [aws_cloudwatch_log_metric_filter.manager]
}

resource "aws_cloudwatch_metric_alarm" "system_failures" {
  for_each = local.alarmed_pools

  alarm_name          = "${var.name}-${each.key}-system-failures"
  alarm_description   = "Jobs on ${each.key} failed with runner_system_failure ${var.monitoring.system_failure_threshold} or more times in 15 minutes: the infrastructure failed them, not their scripts (image pulls, Docker on the instance, instances that never became ready)."
  namespace           = local.log_metric_space
  metric_name         = local.log_metrics["${each.key}-system-failures"].name
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.monitoring.system_failure_threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags

  depends_on = [aws_cloudwatch_log_metric_filter.manager]
}

resource "aws_cloudwatch_metric_alarm" "at_ceiling" {
  for_each = local.alarmed_pools

  alarm_name          = "${var.name}-${each.key}-at-ceiling"
  alarm_description   = "${each.key} has wanted all ${each.value.max_instances} instances for ${var.monitoring.ceiling_minutes} minutes: jobs queue behind max_instances. Raise it or accept the wait."
  namespace           = "AWS/AutoScaling"
  metric_name         = "GroupDesiredCapacity"
  dimensions          = { AutoScalingGroupName = module.fleet[each.key].autoscaling_group_name }
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = var.monitoring.ceiling_minutes / 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = each.value.max_instances
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags
}

# Instances are protected from scale-in and only a manager removes them, so
# instances with no running manager bill until someone notices.
resource "aws_cloudwatch_metric_alarm" "instances_without_manager" {
  for_each = local.alarmed_pools

  alarm_name          = "${var.name}-${each.key}-instances-without-manager"
  alarm_description   = "${each.key} has instances in service and no running manager for 15 minutes. Nothing will remove them: start the manager (it deletes them at start) or terminate them. verify_commands.${each.key}.fleet_instances."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags

  metric_query {
    id          = "orphaned"
    expression  = "IF(FILL(tasks, 0) < 1 AND instances > 0, 1, 0)"
    label       = "Instances without a manager"
    return_data = true
  }

  metric_query {
    id = "instances"
    metric {
      namespace   = "AWS/AutoScaling"
      metric_name = "GroupInServiceInstances"
      dimensions  = { AutoScalingGroupName = module.fleet[each.key].autoscaling_group_name }
      stat        = "Maximum"
      period      = 300
    }
  }

  metric_query {
    id = "tasks"
    metric {
      namespace   = "ECS/ContainerInsights"
      metric_name = "RunningTaskCount"
      dimensions  = { ClusterName = var.name, ServiceName = each.key }
      stat        = "Maximum"
      period      = 300
    }
  }
}

# ---------------------------------------------------------------------------
# Runner metrics through the collector sidecar
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "metrics" {
  count = local.collect_metrics ? 1 : 0

  name              = local.metrics_log_group
  retention_in_days = var.monitoring.metrics_retention_days
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags              = local.tags
}

resource "aws_cloudwatch_metric_alarm" "acquire_timeouts" {
  for_each = local.collect_metrics ? local.alarmed_pools : {}

  alarm_name          = "${var.name}-${each.key}-acquire-timeouts"
  alarm_description   = "Jobs on ${each.key} timed out waiting for an instance in the last 15 minutes: launches failing, the fleet at its ceiling, or instances that never become ready."
  namespace           = local.monitoring_namespace
  metric_name         = "fleeting_taskscaler_task_operations_total"
  dimensions          = { pool = each.key, operation = "acquire_timeout" }
  statistic           = "Sum"
  period              = 900
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------

locals {
  dashboard_widgets = flatten([for i, k in sort(keys(local.active_pools)) : concat(
    [
      {
        type       = "text", x = 0, y = i * 13, width = 24, height = 1
        properties = { markdown = "## Pool ${k}" }
      },
      {
        type = "metric", x = 0, y = i * 13 + 1, width = 8, height = 6
        properties = {
          title = "${k}: instances", region = local.region, view = "timeSeries", stat = "Maximum", period = 60
          metrics = [for m in ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances"] :
          ["AWS/AutoScaling", m, "AutoScalingGroupName", module.fleet[k].autoscaling_group_name]]
          annotations = { horizontal = [{ label = "max_instances", value = local.active_pools[k].max_instances }] }
        }
      },
      {
        type = "metric", x = 8, y = i * 13 + 1, width = 8, height = 6
        properties = {
          title = "${k}: manager errors and system failures", region = local.region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [
            [local.log_metric_space, "ManagerErrors-${k}"],
            [local.log_metric_space, "SystemFailures-${k}"],
          ]
        }
      },
      {
        type = "metric", x = 16, y = i * 13 + 1, width = 8, height = 6
        properties = {
          title = "${k}: manager", region = local.region, view = "timeSeries", stat = "Maximum", period = 60
          metrics = [
            ["ECS/ContainerInsights", "RunningTaskCount", "ClusterName", var.name, "ServiceName", k],
            ["ECS/ContainerInsights", "CpuUtilized", "ClusterName", var.name, "ServiceName", k, { yAxis = "right" }],
            ["ECS/ContainerInsights", "MemoryUtilized", "ClusterName", var.name, "ServiceName", k, { yAxis = "right" }],
          ]
        }
      },
    ],
    !local.collect_metrics ? [] : [
      {
        type = "metric", x = 0, y = i * 13 + 7, width = 8, height = 6
        properties = {
          title   = "${k}: jobs by state", region = local.region, view = "timeSeries", stat = "Maximum", period = 60
          metrics = [for s in ["running", "pending"] : [local.monitoring_namespace, "gitlab_runner_jobs", "pool", k, "state", s]]
        }
      },
      {
        type = "metric", x = 8, y = i * 13 + 7, width = 8, height = 6
        properties = {
          title   = "${k}: tasks waiting for an instance", region = local.region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [for o in ["acquire", "acquire_timeout", "reserve_available_capacity_failure"] : [local.monitoring_namespace, "fleeting_taskscaler_task_operations_total", "pool", k, "operation", o]]
        }
      },
      {
        type = "metric", x = 16, y = i * 13 + 7, width = 8, height = 6
        properties = {
          title   = "${k}: failed jobs by reason", region = local.region, view = "timeSeries", stat = "Sum", period = 300
          metrics = [for r in ["runner_system_failure", "script_failure", "job_execution_timeout", "unknown_failure"] : [local.monitoring_namespace, "gitlab_runner_failed_jobs_total", "pool", k, "failure_reason", r]]
        }
      },
    ],
  )])
}

resource "aws_cloudwatch_dashboard" "this" {
  count = local.create && var.monitoring.dashboard && length(local.active_pools) > 0 ? 1 : 0

  dashboard_name = "${var.name}-gitlab-runner"
  dashboard_body = jsonencode({ widgets = local.dashboard_widgets })
}
