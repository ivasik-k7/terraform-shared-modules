################################################################################
# Repository Information
################################################################################

output "repository_url" {
  description = "The URL of the repository (format: ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/REPOSITORY_NAME)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "The full ARN of the repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "The name of the repository"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "The AWS account ID (registry ID) where the repository was created"
  value       = aws_ecr_repository.this.registry_id
}

################################################################################
# Repository Configuration Information
################################################################################

output "image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  value       = aws_ecr_repository.this.image_tag_mutability
}

output "image_scanning_configuration" {
  description = "The image scanning configuration of the repository"
  value = {
    scan_on_push = aws_ecr_repository.this.image_scanning_configuration[0].scan_on_push
  }
}

output "encryption_configuration" {
  description = "The encryption configuration of the repository"
  value = {
    encryption_type = aws_ecr_repository.this.encryption_configuration[0].encryption_type
    kms_key_arn     = aws_ecr_repository.this.encryption_configuration[0].kms_key
  }
  sensitive = true
}

################################################################################
# Policy Information
################################################################################

# output "repository_policy_arn" {
#   description = "The ARN of the repository policy (if created)"
#   value       = try(aws_ecr_repository_policy.this[0].arn, null)
# }

output "repository_policy_statements" {
  description = "The combined policy statements for the repository (custom + auto-generated)"
  value       = var.create_repository_policy ? local.all_policy_statements : []
  sensitive   = true
}

################################################################################
# Lifecycle Policy Information
################################################################################

output "lifecycle_policy_created" {
  description = "Whether a lifecycle policy was created"
  value       = var.enable_lifecycle_policy
}

output "lifecycle_rules" {
  description = "The lifecycle rules applied to the repository"
  value       = var.enable_lifecycle_policy ? var.lifecycle_rules : []
}

################################################################################
# Replication Information
################################################################################

output "replication_enabled" {
  description = "Whether replication is enabled"
  value       = var.enable_replication
}

output "replication_configuration" {
  description = "The replication configuration (if enabled)"
  value       = var.enable_replication ? var.replication_rules : []
}

################################################################################
# Logging Information
################################################################################

output "log_group_name" {
  description = "CloudWatch log group name for ECR logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.ecr[0].name : null
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for ECR logs"
  value       = var.enable_logging ? aws_cloudwatch_log_group.ecr[0].arn : null
}

################################################################################
# Access Control Information
################################################################################

output "allowed_push_principals" {
  description = "AWS principals with push/pull access to the repository"
  value       = var.allowed_principals
}

output "allowed_pull_principals" {
  description = "AWS principals with read-only (pull) access to the repository"
  value       = var.allowed_pull_principals
}
