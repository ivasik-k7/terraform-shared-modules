# app auto scaling for opt-in services: target tracking (cpu/mem/alb/custom) + scheduled min/max.

locals {
  scheduled_actions = merge([
    for sk, s in local.services_autoscaled : {
      for name, sch in s.autoscaling.scheduled : "${sk}/${name}" => merge(sch, { service = sk })
    }
  ]...)
}

resource "aws_appautoscaling_target" "this" {
  for_each = local.services_autoscaled

  service_namespace  = "ecs"
  scalable_dimension = "ecs:service:DesiredCount"
  resource_id        = "service/${var.cluster_name}/${aws_ecs_service.autoscaled[each.key].name}"
  min_capacity       = each.value.autoscaling.min_capacity
  max_capacity       = each.value.autoscaling.max_capacity

  tags = local.common_tags
}

resource "aws_appautoscaling_policy" "cpu" {
  for_each = { for k, s in local.services_autoscaled : k => s if s.autoscaling.cpu_target != null }

  name               = "${each.key}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
    target_value       = each.value.autoscaling.cpu_target
    scale_in_cooldown  = each.value.autoscaling.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "memory" {
  for_each = { for k, s in local.services_autoscaled : k => s if s.autoscaling.memory_target != null }

  name               = "${each.key}-memory"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageMemoryUtilization"
    }
    target_value       = each.value.autoscaling.memory_target
    scale_in_cooldown  = each.value.autoscaling.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "alb_requests" {
  for_each = { for k, s in local.services_autoscaled : k => s if s.autoscaling.alb_request_target != null }

  name               = "${each.key}-alb-requests"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = each.value.autoscaling.alb_resource_label
    }
    target_value       = each.value.autoscaling.alb_request_target
    scale_in_cooldown  = each.value.autoscaling.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.scale_out_cooldown
  }
}

resource "aws_appautoscaling_policy" "custom" {
  for_each = { for k, s in local.services_autoscaled : k => s if s.autoscaling.custom_metric != null }

  name               = "${each.key}-custom"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.this[each.key].service_namespace
  scalable_dimension = aws_appautoscaling_target.this[each.key].scalable_dimension
  resource_id        = aws_appautoscaling_target.this[each.key].resource_id

  target_tracking_scaling_policy_configuration {
    customized_metric_specification {
      namespace   = each.value.autoscaling.custom_metric.namespace
      metric_name = each.value.autoscaling.custom_metric.metric_name
      statistic   = each.value.autoscaling.custom_metric.statistic
      unit        = each.value.autoscaling.custom_metric.unit

      dynamic "dimensions" {
        for_each = each.value.autoscaling.custom_metric.dimensions
        content {
          name  = dimensions.key
          value = dimensions.value
        }
      }
    }
    target_value       = each.value.autoscaling.custom_metric.target_value
    scale_in_cooldown  = each.value.autoscaling.scale_in_cooldown
    scale_out_cooldown = each.value.autoscaling.scale_out_cooldown
  }
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = local.scheduled_actions

  name               = each.key
  service_namespace  = aws_appautoscaling_target.this[each.value.service].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.value.service].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.value.service].scalable_dimension
  schedule           = each.value.schedule
  timezone           = each.value.timezone

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}
