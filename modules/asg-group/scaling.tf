resource "aws_autoscaling_policy" "target_tracking" {
  for_each = local.create ? var.target_tracking_policies : {}

  name                      = "${var.name}-${each.key}"
  autoscaling_group_name    = local.group_name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = each.value.estimated_instance_warmup != -1 ? each.value.estimated_instance_warmup : null

  target_tracking_configuration {
    target_value     = each.value.target_value
    disable_scale_in = each.value.disable_scale_in

    dynamic "predefined_metric_specification" {
      for_each = each.value.predefined_metric_type != "" ? [each.value] : []
      content {
        predefined_metric_type = predefined_metric_specification.value.predefined_metric_type
        resource_label         = predefined_metric_specification.value.resource_label != "" ? predefined_metric_specification.value.resource_label : null
      }
    }

    dynamic "customized_metric_specification" {
      for_each = each.value.customized != null ? [each.value.customized] : []
      content {
        namespace   = customized_metric_specification.value.namespace
        metric_name = customized_metric_specification.value.metric_name
        statistic   = customized_metric_specification.value.statistic
        unit        = customized_metric_specification.value.unit != "" ? customized_metric_specification.value.unit : null

        dynamic "metric_dimension" {
          for_each = customized_metric_specification.value.dimensions
          content {
            name  = metric_dimension.key
            value = metric_dimension.value
          }
        }
      }
    }
  }
}

resource "aws_autoscaling_policy" "predictive" {
  count = local.create ? (var.predictive_scaling.enabled ? 1 : 0) : 0

  name                   = "${var.name}-predictive"
  autoscaling_group_name = local.group_name
  policy_type            = "PredictiveScaling"

  predictive_scaling_configuration {
    mode                         = var.predictive_scaling.mode
    scheduling_buffer_time       = var.predictive_scaling.scheduling_buffer_seconds != -1 ? tostring(var.predictive_scaling.scheduling_buffer_seconds) : null
    max_capacity_breach_behavior = var.predictive_scaling.max_capacity_breach_behavior
    max_capacity_buffer          = var.predictive_scaling.max_capacity_buffer != -1 ? tostring(var.predictive_scaling.max_capacity_buffer) : null

    metric_specification {
      target_value = var.predictive_scaling.target_value

      predefined_metric_pair_specification {
        predefined_metric_type = local.predictive_metric_pair[var.predictive_scaling.metric]
        resource_label         = var.predictive_scaling.resource_label != "" ? var.predictive_scaling.resource_label : null
      }
    }
  }
}

resource "aws_autoscaling_schedule" "this" {
  for_each = local.create ? var.scheduled_actions : {}

  scheduled_action_name  = each.key
  autoscaling_group_name = local.group_name

  # -1 leaves that bound unchanged.
  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_capacity

  recurrence = each.value.recurrence != "" ? each.value.recurrence : null
  start_time = each.value.start_time != "" ? each.value.start_time : null
  end_time   = each.value.end_time != "" ? each.value.end_time : null
  time_zone  = each.value.time_zone != "" ? each.value.time_zone : null
}
