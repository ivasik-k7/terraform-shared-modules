# Core — what most callers wire into downstream modules.

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "service_names" {
  description = "Service name to ECS service name as registered in the cluster."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.name },
    { for k, v in aws_ecs_service.static : k => v.name }
  )
}

output "task_role_arns" {
  description = "Service name to task role ARN (identity the app code runs as)."
  value       = { for k, v in aws_iam_role.task : k => v.arn }
}

output "task_execution_role_arns" {
  description = "Service name to execution role ARN. All map to the same ARN when per_service_execution_role = false."
  value       = local.service_execution_role_arns
}

output "log_group_names" {
  description = "Service name to CloudWatch log group name."
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}

output "service_security_group_ids" {
  description = "Service name to managed SG ID. Empty for services without create_security_group = true."
  value       = { for k, v in aws_security_group.service : k => v.id }
}

output "summary" {
  description = "Consolidated cluster summary, useful for downstream modules and CI output."
  value = {
    cluster_name        = aws_ecs_cluster.this.name
    cluster_arn         = aws_ecs_cluster.this.arn
    region              = local.region
    environment         = var.environment
    services            = keys(local.services)
    autoscaled_services = keys(local.services_autoscaled)
    capacity_providers  = local.cluster_capacity_providers
    log_groups          = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
  }
}

# Advanced — for introspection, extra wiring, or debugging.

output "cluster_id" {
  description = "ECS cluster ID."
  value       = aws_ecs_cluster.this.id
}

output "cluster_capacity_providers" {
  description = "Capacity providers registered on the cluster."
  value       = local.cluster_capacity_providers
}

output "service_ids" {
  description = "Service name to ECS service ID."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.id },
    { for k, v in aws_ecs_service.static : k => v.id }
  )
}

output "service_deployment_controllers" {
  description = "Service name to deployment controller type (ECS / CODE_DEPLOY / EXTERNAL)."
  value       = { for k, v in local.services : k => v.deployment_controller }
}

output "task_definition_arns" {
  description = "Service name to current task definition ARN."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.arn }
}

output "task_definition_families" {
  description = "Service name to task definition family."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.family }
}

output "task_definition_revisions" {
  description = "Service name to current task definition revision."
  value       = { for k, v in aws_ecs_task_definition.this : k => v.revision }
}

output "container_names" {
  description = "Service name to the list of container names in its task definition."
  value       = { for k, v in local.services : k => [for c in v.containers : c.name] }
}

output "task_role_names" {
  description = "Service name to task role name."
  value       = { for k, v in aws_iam_role.task : k => v.name }
}

output "log_group_arns" {
  description = "Service name to log group ARN."
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.arn }
}

output "alarm_arns" {
  description = "Service name to alarm ARNs, split by metric."
  value = {
    for k in keys(local.services) : k => {
      cpu    = try(aws_cloudwatch_metric_alarm.cpu_high[k].arn, null)
      memory = try(aws_cloudwatch_metric_alarm.memory_high[k].arn, null)
    }
  }
}

output "scheduled_task_rule_arns" {
  description = "Service name to EventBridge rule ARN for services with run_schedule set."
  value       = { for k, v in aws_cloudwatch_event_rule.scheduled_task : k => v.arn }
}

output "scheduled_task_rule_names" {
  description = "Service name to EventBridge rule name for services with run_schedule set."
  value       = { for k, v in aws_cloudwatch_event_rule.scheduled_task : k => v.name }
}

output "autoscaling_target_resource_ids" {
  description = "Service name to App Autoscaling resource ID."
  value       = { for k, v in aws_appautoscaling_target.this : k => v.resource_id }
}

output "custom_scaling_policy_arns" {
  description = "Map of '<service>:<policy-name>' to custom target-tracking policy ARN."
  value       = { for k, v in aws_appautoscaling_policy.custom : k => v.arn }
}
