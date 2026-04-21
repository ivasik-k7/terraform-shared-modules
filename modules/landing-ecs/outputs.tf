# Cluster

output "cluster_id" {
  description = "ECS cluster ID."
  value       = aws_ecs_cluster.this.id
}

output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = aws_ecs_cluster.this.arn
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

# Services

output "service_ids" {
  description = "Service name to ECS service ID."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.id },
    { for k, v in aws_ecs_service.static : k => v.id }
  )
}

output "service_names" {
  description = "Service name to ECS service name as registered in the cluster."
  value = merge(
    { for k, v in aws_ecs_service.autoscaled : k => v.name },
    { for k, v in aws_ecs_service.static : k => v.name }
  )
}

# Task definitions

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

# IAM

output "task_execution_role_arn" {
  description = "ARN of the shared task execution role."
  value       = aws_iam_role.task_execution.arn
}

output "task_execution_role_name" {
  description = "Name of the shared task execution role."
  value       = aws_iam_role.task_execution.name
}

output "task_role_arns" {
  description = "Service name to task role ARN."
  value       = { for k, v in aws_iam_role.task : k => v.arn }
}

output "task_role_names" {
  description = "Service name to task role name."
  value       = { for k, v in aws_iam_role.task : k => v.name }
}

# Networking

output "service_security_group_ids" {
  description = "Service name to managed security group ID. Empty for services without create_security_group = true."
  value       = { for k, v in aws_security_group.service : k => v.id }
}

# Observability

output "log_group_names" {
  description = "Service name to CloudWatch log group name."
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
}

output "log_group_arns" {
  description = "Service name to CloudWatch log group ARN."
  value       = { for k, v in aws_cloudwatch_log_group.service : k => v.arn }
}

output "dashboard_arn" {
  description = "CloudWatch dashboard ARN. Null when create_cloudwatch_dashboard = false."
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.this[0].dashboard_arn : null
}

output "dashboard_name" {
  description = "CloudWatch dashboard name. Null when create_cloudwatch_dashboard = false."
  value       = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
}

# Scheduled tasks (EventBridge)

output "scheduled_task_rule_arns" {
  description = "Service name to EventBridge rule ARN for services with run_schedule set."
  value       = { for k, v in aws_cloudwatch_event_rule.scheduled_task : k => v.arn }
}

output "scheduled_task_rule_names" {
  description = "Service name to EventBridge rule name for services with run_schedule set."
  value       = { for k, v in aws_cloudwatch_event_rule.scheduled_task : k => v.name }
}

# Autoscaling

output "autoscaling_target_resource_ids" {
  description = "Service name to App Autoscaling resource ID."
  value       = { for k, v in aws_appautoscaling_target.this : k => v.resource_id }
}

# Cost estimates

output "cost_estimates" {
  description = <<-EOT
    Rough monthly cost estimate per task (USD). Based on us-east-1 on-demand
    Fargate pricing (vCPU $0.04048/hr, memory $0.004445/GB/hr) with spot and
    economy discounts applied. Real costs depend on region, reserved capacity,
    and actual usage.
  EOT
  value = {
    for name, est in local.service_cost_estimates : name => {
      strategy                       = est.strategy
      vcpu_per_task                  = est.vcpu_per_task
      memory_gb_per_task             = est.memory_gb
      estimated_monthly_usd_per_task = est.estimated_monthly_usd_per_task
    }
  }
}

# Consolidated summary, useful for passing into dependent modules or CI output.

output "summary" {
  description = "Consolidated cluster summary."
  value = {
    cluster_name        = aws_ecs_cluster.this.name
    cluster_arn         = aws_ecs_cluster.this.arn
    region              = local.region
    environment         = var.environment
    services            = keys(local.services)
    autoscaled_services = keys(local.services_autoscaled)
    task_execution_role = aws_iam_role.task_execution.arn
    log_groups          = { for k, v in aws_cloudwatch_log_group.service : k => v.name }
    dashboard           = var.create_cloudwatch_dashboard ? aws_cloudwatch_dashboard.this[0].dashboard_name : null
  }
}
