output "role_arn" {
  description = "ARN of the IAM role"
  value       = var.create_role ? aws_iam_role.this[0].arn : var.existing_role_arn
}

output "role_name" {
  description = "Name of the IAM role"
  value       = var.create_role ? aws_iam_role.this[0].name : null
}

output "role_unique_id" {
  description = "Unique ID of the IAM role"
  value       = var.create_role ? aws_iam_role.this[0].unique_id : null
}

output "role_path" {
  description = "Path of the IAM role"
  value       = var.create_role ? aws_iam_role.this[0].path : null
}

output "service_account_name" {
  description = "Name of the Kubernetes service account"
  value       = var.service_account_name
}

output "service_account_namespace" {
  description = "Namespace of the Kubernetes service account"
  value       = var.service_account_namespace
}

output "policy_arns" {
  description = "List of policy ARNs attached to the role"
  value       = local.policy_arns
}
