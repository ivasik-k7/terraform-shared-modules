resource "aws_appautoscaling_target" "this" {
  for_each = var.auto_scaling_policies

  max_capacity       = each.value.max_capacity
  min_capacity       = each.value.min_capacity
  resource_id        = "service/${aws_ecs_cluster.this.name}/${each.value.service_name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"

  depends_on = [aws_ecs_service.this]
}

resource "aws_appautoscaling_policy" "target_tracking" {
  for_each = merge([
    for policy_key, policy in var.auto_scaling_policies : {
      for idx, target_policy in coalesce(policy.target_tracking_policies, []) : "${policy_key}-${target_policy.name}" => {
        policy_key             = policy_key
        service_name           = policy.service_name
        name                   = target_policy.name
        target_value           = target_policy.target_value
        scale_in_cooldown      = target_policy.scale_in_cooldown
        scale_out_cooldown     = target_policy.scale_out_cooldown
        predefined_metric_type = target_policy.predefined_metric_type
        resource_label         = target_policy.resource_label
        custom_metric          = target_policy.custom_metric
      }
    }
  ]...)

  name               = each.value.name
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.this[each.value.policy_key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.value.policy_key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.value.policy_key].service_namespace

  target_tracking_scaling_policy_configuration {
    target_value       = each.value.target_value
    scale_in_cooldown  = each.value.scale_in_cooldown
    scale_out_cooldown = each.value.scale_out_cooldown

    dynamic "predefined_metric_specification" {
      for_each = each.value.predefined_metric_type != null ? [1] : []
      content {
        predefined_metric_type = each.value.predefined_metric_type
        resource_label         = each.value.resource_label
      }
    }

    dynamic "customized_metric_specification" {
      for_each = each.value.custom_metric != null ? [each.value.custom_metric] : []
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

resource "aws_appautoscaling_policy" "step_scaling" {
  for_each = merge([
    for policy_key, policy in var.auto_scaling_policies : {
      for idx, step_policy in coalesce(policy.step_scaling_policies, []) : "${policy_key}-${step_policy.name}" => {
        policy_key              = policy_key
        service_name            = policy.service_name
        name                    = step_policy.name
        adjustment_type         = step_policy.adjustment_type
        cooldown                = step_policy.cooldown
        metric_aggregation_type = step_policy.metric_aggregation_type
        step_adjustments        = step_policy.step_adjustments
        alarm_name              = step_policy.alarm_name
        alarm_description       = step_policy.alarm_description
        comparison_operator     = step_policy.comparison_operator
        evaluation_periods      = step_policy.evaluation_periods
        metric_name             = step_policy.metric_name
        namespace               = step_policy.namespace
        period                  = step_policy.period
        statistic               = step_policy.statistic
        threshold               = step_policy.threshold
        dimensions              = step_policy.dimensions
      }
    }
  ]...)

  name               = each.value.name
  policy_type        = "StepScaling"
  resource_id        = aws_appautoscaling_target.this[each.value.policy_key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.value.policy_key].scalable_dimension
  service_namespace  = aws_appautoscaling_target.this[each.value.policy_key].service_namespace

  step_scaling_policy_configuration {
    adjustment_type         = each.value.adjustment_type
    cooldown                = each.value.cooldown
    metric_aggregation_type = each.value.metric_aggregation_type

    dynamic "step_adjustment" {
      for_each = each.value.step_adjustments
      content {
        scaling_adjustment          = step_adjustment.value.scaling_adjustment
        metric_interval_lower_bound = step_adjustment.value.metric_interval_lower_bound
        metric_interval_upper_bound = step_adjustment.value.metric_interval_upper_bound
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "step_scaling" {
  for_each = merge([
    for policy_key, policy in var.auto_scaling_policies : {
      for idx, step_policy in coalesce(policy.step_scaling_policies, []) : "${policy_key}-${step_policy.name}" => {
        policy_key          = policy_key
        service_name        = policy.service_name
        alarm_name          = step_policy.alarm_name
        alarm_description   = step_policy.alarm_description
        comparison_operator = step_policy.comparison_operator
        evaluation_periods  = step_policy.evaluation_periods
        metric_name         = step_policy.metric_name
        namespace           = step_policy.namespace
        period              = step_policy.period
        statistic           = step_policy.statistic
        threshold           = step_policy.threshold
        dimensions          = step_policy.dimensions
      }
    }
  ]...)

  alarm_name          = each.value.alarm_name
  alarm_description   = each.value.alarm_description
  comparison_operator = each.value.comparison_operator
  evaluation_periods  = each.value.evaluation_periods
  metric_name         = each.value.metric_name
  namespace           = each.value.namespace
  period              = each.value.period
  statistic           = each.value.statistic
  threshold           = each.value.threshold
  dimensions = merge(
    each.value.dimensions,
    {
      ClusterName = aws_ecs_cluster.this.name
      ServiceName = each.value.service_name
    }
  )

  alarm_actions = [aws_appautoscaling_policy.step_scaling[each.key].arn]

  tags = var.tags
}

resource "aws_appautoscaling_scheduled_action" "this" {
  for_each = merge([
    for policy_key, policy in var.auto_scaling_policies : {
      for idx, scheduled_action in coalesce(policy.scheduled_actions, []) : "${policy_key}-${scheduled_action.name}" => {
        policy_key   = policy_key
        service_name = policy.service_name
        name         = scheduled_action.name
        schedule     = scheduled_action.schedule
        min_capacity = scheduled_action.min_capacity
        max_capacity = scheduled_action.max_capacity
        timezone     = scheduled_action.timezone
      }
    }
  ]...)

  name               = each.value.name
  service_namespace  = aws_appautoscaling_target.this[each.value.policy_key].service_namespace
  resource_id        = aws_appautoscaling_target.this[each.value.policy_key].resource_id
  scalable_dimension = aws_appautoscaling_target.this[each.value.policy_key].scalable_dimension
  schedule           = each.value.schedule
  timezone           = each.value.timezone

  scalable_target_action {
    min_capacity = each.value.min_capacity
    max_capacity = each.value.max_capacity
  }
}
