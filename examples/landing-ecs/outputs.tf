output "cluster_arn" {
  description = "ECS cluster ARN."
  value       = module.ecs.cluster_arn
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = module.ecs.cluster_name
}

output "service_names" {
  description = "All ECS service names."
  value       = module.ecs.service_names
}

output "task_execution_role_arns" {
  description = "Per-service task execution role ARNs (one per service when per_service_execution_role = true, which is the default)."
  value       = module.ecs.task_execution_role_arns
}

output "task_role_arns" {
  description = "Per-service task role ARNs."
  value       = module.ecs.task_role_arns
}

output "log_group_names" {
  description = "CloudWatch log group names per service."
  value       = module.ecs.log_group_names
}

output "api_security_group_id" {
  description = "Security group ID for the API service — add your ingress rules here."
  value       = module.ecs.service_security_group_ids["api"]
}

output "summary" {
  description = "Full cluster summary."
  value       = module.ecs.summary
}

output "alb_dns_name" {
  description = "ALB DNS name for the API."
  value       = aws_lb.api.dns_name
}
