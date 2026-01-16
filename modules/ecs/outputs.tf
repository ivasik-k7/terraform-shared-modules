output "cluster_id" {
  description = "ID of the ECS cluster"
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ARN of the ECS cluster"
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "Name of the ECS cluster"
  value       = aws_ecs_cluster.this.name
}

output "capacity_provider_arns" {
  description = "Map of capacity provider ARNs"
  value       = { for k, v in aws_ecs_capacity_provider.this : k => v.arn }
}

output "capacity_provider_ids" {
  description = "Map of capacity provider IDs"
  value       = { for k, v in aws_ecs_capacity_provider.this : k => v.id }
}

output "service_ids" {
  description = "Map of ECS service IDs"
  value       = { for k, v in aws_ecs_service.this : k => v.id }
}

output "service_arns" {
  description = "Map of ECS service ARNs"
  value       = { for k, v in aws_ecs_service.this : k => v.id }
}

output "service_names" {
  description = "Map of ECS service names"
  value       = { for k, v in aws_ecs_service.this : k => v.name }
}

output "task_definition_arns" {
  description = "Map of task definition ARNs"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_definition_families" {
  description = "Map of task definition families"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.family }
}

output "task_definition_revisions" {
  description = "Map of task definition revisions"
  value       = { for k, v in aws_ecs_task_definition.this : k => v.revision }
}

output "task_execution_role_arn" {
  description = "ARN of the task execution role"
  value       = var.task_execution_role_arn != null ? var.task_execution_role_arn : (var.create_task_execution_role ? aws_iam_role.task_execution[0].arn : null)
}

output "task_execution_role_name" {
  description = "Name of the task execution role"
  value       = var.create_task_execution_role && var.task_execution_role_arn == null ? aws_iam_role.task_execution[0].name : null
}

output "task_role_arns" {
  description = "Map of task role ARNs"
  value       = { for k, v in aws_iam_role.task : k => v.arn }
}

output "task_role_names" {
  description = "Map of task role names"
  value       = { for k, v in aws_iam_role.task : k => v.name }
}

output "log_group_names" {
  description = "Map of CloudWatch log group names"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.name }
}

output "log_group_arns" {
  description = "Map of CloudWatch log group ARNs"
  value       = { for k, v in aws_cloudwatch_log_group.this : k => v.arn }
}

output "autoscaling_target_ids" {
  description = "Map of auto scaling target IDs"
  value       = { for k, v in aws_appautoscaling_target.this : k => v.id }
}

output "autoscaling_policy_arns" {
  description = "Map of auto scaling policy ARNs (target tracking)"
  value       = { for k, v in aws_appautoscaling_policy.target_tracking : k => v.arn }
}

output "autoscaling_step_policy_arns" {
  description = "Map of auto scaling step policy ARNs"
  value       = { for k, v in aws_appautoscaling_policy.step_scaling : k => v.arn }
}

output "summary" {
  description = "Summary of ECS cluster and services"
  value = {
    cluster = {
      id                 = aws_ecs_cluster.this.id
      arn                = aws_ecs_cluster.this.arn
      name               = aws_ecs_cluster.this.name
      container_insights = var.enable_container_insights
    }
    services = {
      for k, v in aws_ecs_service.this : k => {
        id              = v.id
        name            = v.name
        desired_count   = v.desired_count
        task_definition = aws_ecs_task_definition.this[k].arn
        launch_type     = v.launch_type
      }
    }
    capacity_providers = {
      for k, v in aws_ecs_capacity_provider.this : k => {
        id  = v.id
        arn = v.arn
      }
    }
  }
}
