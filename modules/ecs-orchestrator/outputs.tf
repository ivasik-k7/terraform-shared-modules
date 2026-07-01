# ============================================================================
# CLUSTER
# ============================================================================

output "cluster_id" {
  description = "ECS cluster ID."
  value       = one(aws_ecs_cluster.this[*].id)
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = one(aws_ecs_cluster.this[*].arn)
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = one(aws_ecs_cluster.this[*].name)
}

output "capacity_providers" {
  description = "Capacity providers registered on the cluster."
  value       = local.create ? local.cluster_capacity_providers : []
}

output "ec2_capacity_provider_names" {
  description = "Names of the EC2 capacity providers created by this module."
  value       = [for k, v in aws_ecs_capacity_provider.ec2 : v.name]
}

# ============================================================================
# SERVICES
# ============================================================================

output "service_names" {
  description = "Map of service key to ECS service name."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.name },
    { for k, v in aws_ecs_service.static : k => v.name },
  )
}

output "service_arns" {
  description = "Map of service key to ECS service ARN (id)."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.id },
    { for k, v in aws_ecs_service.static : k => v.id },
  )
}

output "task_definition_arns" {
  description = "Map of service key to task definition ARN."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "service_security_group_ids" {
  description = "Map of service key to the security group ID created for it (only services with create_security_group)."
  value       = { for k, v in aws_security_group.service : k => v.id }
}

# ============================================================================
# IAM
# ============================================================================

output "task_execution_role_arn" {
  description = "ARN of the shared task execution role (null when external/none)."
  value       = local.shared_execution_role_arn
}

output "task_role_arns" {
  description = "Map of service key to task role ARN (created or provided)."
  value       = local.service_task_role_arn
}

# ============================================================================
# OBSERVABILITY / DISCOVERY
# ============================================================================

output "log_group_names" {
  description = "Map of service key to CloudWatch log group name."
  value       = local.service_log_group
}

output "service_discovery_arns" {
  description = "Map of service key to Cloud Map service ARN (only services with service_discovery)."
  value       = { for k, v in aws_service_discovery_service.this : k => v.arn }
}

output "autoscaling_target_ids" {
  description = "Map of service key to Application Auto Scaling target resource id."
  value       = { for k, v in aws_appautoscaling_target.this : k => v.resource_id }
}

output "cloudwatch_alarm_names" {
  description = "Names of the per-service CloudWatch alarms created (empty when disabled)."
  value = concat(
    [for k, a in aws_cloudwatch_metric_alarm.cpu_high : a.alarm_name],
    [for k, a in aws_cloudwatch_metric_alarm.memory_high : a.alarm_name],
    [for k, a in aws_cloudwatch_metric_alarm.running_tasks_low : a.alarm_name],
  )
}
