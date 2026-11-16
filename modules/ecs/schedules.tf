resource "aws_scheduler_schedule_group" "this" {
  count = length(local.scheduled) > 0 ? 1 : 0

  name = var.name
  tags = local.common_tags
}

resource "aws_scheduler_schedule" "this" {
  for_each = local.scheduled

  name                         = each.key
  group_name                   = aws_scheduler_schedule_group.this[0].name
  description                  = "Runs ${var.name}-${each.key} on ECS cluster ${var.name}."
  schedule_expression          = each.value.schedule.expression
  schedule_expression_timezone = each.value.schedule.timezone
  state                        = each.value.schedule.enabled ? "ENABLED" : "DISABLED"

  flexible_time_window {
    mode                      = each.value.schedule.flexible_window_minutes > 0 ? "FLEXIBLE" : "OFF"
    maximum_window_in_minutes = each.value.schedule.flexible_window_minutes > 0 ? each.value.schedule.flexible_window_minutes : null
  }

  target {
    arn      = aws_ecs_cluster.this[0].arn
    role_arn = aws_iam_role.scheduler[0].arn

    retry_policy {
      maximum_retry_attempts       = each.value.schedule.maximum_retry_attempts
      maximum_event_age_in_seconds = each.value.schedule.maximum_event_age_seconds
    }

    dynamic "dead_letter_config" {
      for_each = each.value.schedule.dead_letter_queue_arn != "" ? [each.value.schedule.dead_letter_queue_arn] : []
      content {
        arn = dead_letter_config.value
      }
    }

    ecs_parameters {
      task_definition_arn     = aws_ecs_task_definition.this[each.key].arn
      task_count              = each.value.schedule.task_count
      platform_version        = each.value.launch == "FARGATE" ? each.value.platform_version : null
      enable_ecs_managed_tags = true
      propagate_tags          = each.value.propagate_tags == "TASK_DEFINITION" ? "TASK_DEFINITION" : null
      tags                    = local.workload_tags[each.key]
      enable_execute_command  = each.value.enable_execute_command

      dynamic "capacity_provider_strategy" {
        for_each = local.strategy[each.key]
        content {
          capacity_provider = capacity_provider_strategy.value.capacity_provider
          weight            = capacity_provider_strategy.value.weight
          base              = capacity_provider_strategy.value.base
        }
      }

      dynamic "network_configuration" {
        for_each = each.value.network_mode == "awsvpc" ? [each.value] : []
        content {
          subnets          = local.subnets[each.key]
          security_groups  = local.security_groups[each.key]
          assign_public_ip = network_configuration.value.assign_public_ip
        }
      }

      dynamic "placement_constraints" {
        for_each = each.value.placement_constraints
        content {
          type       = placement_constraints.value.type
          expression = placement_constraints.value.expression != "" ? placement_constraints.value.expression : null
        }
      }

      dynamic "placement_strategy" {
        for_each = each.value.ordered_placement_strategy
        content {
          type  = placement_strategy.value.type
          field = placement_strategy.value.field != "" ? placement_strategy.value.field : null
        }
      }
    }
  }

  lifecycle {
    # aws_scheduler_schedule's ecs_parameters accepts at most six strategy entries.
    precondition {
      condition     = length(local.strategy[each.key]) <= 6
      error_message = "services.${each.key}: a scheduled workload's capacity_provider_strategy can have at most 6 entries; EventBridge Scheduler accepts no more."
    }
  }

  depends_on = [
    aws_iam_role_policy.scheduler,
    aws_ecs_cluster_capacity_providers.this,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_module,
    aws_cloudwatch_log_group.this,
  ]
}
