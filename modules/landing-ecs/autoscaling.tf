resource "aws_appautoscaling_target" "this" {
  for_each = local.services_autoscaled

  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.this.name}/${var.cluster_name}-${each.key}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = each.value.min_count
  max_capacity       = each.value.max_count

  depends_on = [aws_ecs_service.autoscaled]
}

# CPU target tracking — keep average CPU below target_value.
resource "aws_appautoscaling_policy" "cpu" {
  for_each = local.services_autoscaled

  name               = "${var.cluster_name}-${each.key}-cpu-scaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = 60.0 # scale out before saturation
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

resource "aws_appautoscaling_policy" "memory" {
  for_each = local.services_autoscaled

  name               = "${var.cluster_name}-${each.key}-memory-scaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  policy_type        = "TargetTrackingScaling"

  target_tracking_scaling_policy_configuration {
    target_value       = 70.0
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
  }
}

# Scheduled scale-down/up windows (e.g. non-prod overnight savings).
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
