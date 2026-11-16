resource "aws_appautoscaling_target" "this" {
  for_each = local.scaled

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.name}/${each.key}"
  min_capacity       = each.value.autoscaling.min
  max_capacity       = each.value.autoscaling.max

  tags = local.workload_tags[each.key]

  depends_on = [aws_ecs_service.autoscaled, aws_ecs_service.autoscaled_ignored]
}

resource "aws_appautoscaling_policy" "target_tracking" {
  for_each = local.scaling_policies

  name               = "${var.name}-${replace(each.key, "/", "-")}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.value.service].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.value.service].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.value.service].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target
    scale_in_cooldown  = local.scaled[each.value.service].autoscaling.scale_in_cooldown
    scale_out_cooldown = local.scaled[each.value.service].autoscaling.scale_out_cooldown
    disable_scale_in   = local.scaled[each.value.service].autoscaling.disable_scale_in

    predefined_metric_specification {
      predefined_metric_type = each.value.metric
      resource_label         = each.value.label != "" ? each.value.label : null
    }
  }
}

resource "aws_appautoscaling_policy" "custom" {
  for_each = local.custom_scaling_policies

  name               = "${var.name}-${each.value.service}-custom-${each.value.name}"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.value.service].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.value.service].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.value.service].resource_id

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_value
    scale_in_cooldown  = local.scaled[each.value.service].autoscaling.scale_in_cooldown
    scale_out_cooldown = local.scaled[each.value.service].autoscaling.scale_out_cooldown
    disable_scale_in   = local.scaled[each.value.service].autoscaling.disable_scale_in

    customized_metric_specification {
      namespace   = each.value.namespace
      metric_name = each.value.metric_name
      statistic   = each.value.statistic
      unit        = each.value.unit != "" ? each.value.unit : null

      dynamic "dimensions" {
        for_each = each.value.dimensions
        content {
          name  = dimensions.key
          value = dimensions.value
        }
      }
    }
  }
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = local.scaling_schedules

  name               = "${var.name}-${each.value.service}-${each.value.name}"
  service_namespace  = aws_appautoscaling_target.this[each.value.service].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.value.service].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.value.service].resource_id
  schedule           = each.value.schedule
  timezone           = each.value.timezone

  scalable_target_action {
    min_capacity = each.value.min
    max_capacity = each.value.max
  }
}
