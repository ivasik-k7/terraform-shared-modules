resource "aws_appautoscaling_target" "this" {
  for_each = local.services_autoscaled

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${var.cluster_name}-${each.key}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.min_count
  max_capacity       = each.value.max_count

  depends_on = [aws_ecs_service.autoscaled]
}

# CPU target tracking. Opt out per service with enable_cpu_autoscaling = false.
resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.services_with_cpu_autoscale

  name               = "${var.cluster_name}-${each.key}-cpu"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.cpu_target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

# Memory target tracking. Skip via enable_memory_autoscaling = false when
# memory is flat (then CPU is the useful signal on its own).
resource "aws_appautoscaling_policy" "memory" {
  for_each = local.services_with_memory_autoscale

  name               = "${var.cluster_name}-${each.key}-memory"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.memory_target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# Custom target tracking (ALB request count, SQS depth, any CW metric).
# Keyed as "<service>:<policy>" so multiple per service coexist cleanly.
resource "aws_appautoscaling_policy" "custom" {
  for_each = local.custom_scaling_policies_flat

  name               = "${var.cluster_name}-${each.value.service}-${each.value.name}"
  service_namespace  = aws_appautoscaling_target.this[each.value.service].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.value.service].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.value.service].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_value
    scale_in_cooldown  = coalesce(each.value.scale_in_cooldown, var.default_scale_in_cooldown)
    scale_out_cooldown = coalesce(each.value.scale_out_cooldown, var.default_scale_out_cooldown)
    disable_scale_in   = each.value.disable_scale_in

    dynamic "predefined_metric_specification" {
      for_each = each.value.predefined_metric_type != null ? [1] : []
      content {
        predefined_metric_type = each.value.predefined_metric_type
        resource_label         = each.value.resource_label
      }
    }

    dynamic "customized_metric_specification" {
      for_each = each.value.customized_metric != null ? [each.value.customized_metric] : []
      content {
        metric_name = customized_metric_specification.value.metric_name
        namespace   = customized_metric_specification.value.namespace
        statistic   = customized_metric_specification.value.statistic
        unit        = customized_metric_specification.value.unit

        dynamic "dimensions" {
          for_each = customized_metric_specification.value.dimensions
          content {
            name  = dimensions.value.name
            value = dimensions.value.value
          }
        }
      }
    }
  }
}

# Scheduled actions: scale the target down at scale_down_cron, back up at
# scale_up_cron. Common use is non-prod overnight/weekend hibernation.
resource "aws_appautoscaling_scheduled_action" "scale_down" {
  for_each = local.services_with_schedule

  name               = "${var.cluster_name}-${each.key}-scale-down"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  schedule           = each.value.schedule_scaling.scale_down_cron

  scalable_target_action {
    min_capacity = each.value.schedule_scaling.scale_down_min_cap
    max_capacity = each.value.schedule_scaling.scale_down_max_cap
  }
}

resource "aws_appautoscaling_scheduled_action" "scale_up" {
  for_each = local.services_with_schedule

  name               = "${var.cluster_name}-${each.key}-scale-up"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  schedule           = each.value.schedule_scaling.scale_up_cron

  scalable_target_action {
    min_capacity = each.value.schedule_scaling.scale_up_min_cap
    max_capacity = each.value.schedule_scaling.scale_up_max_cap
  }
}
