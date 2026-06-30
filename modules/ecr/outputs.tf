################################################################################
# Repository Information
################################################################################

output "repository_url" {
  description = "The URL of the repository (format: ACCOUNT_ID.dkr.ecr.REGION.amazonaws.com/REPOSITORY_NAME)"
  value       = local.create ? aws_ecr_repository.this[0].repository_url : null
}

output "repository_arn" {
  description = "The full ARN of the repository"
  value       = local.create ? aws_ecr_repository.this[0].arn : null
}

output "repository_name" {
  description = "The name of the repository"
  value       = local.create ? aws_ecr_repository.this[0].name : null
}

output "registry_id" {
  description = "The AWS account ID (registry ID) where the repository was created"
  value       = local.create ? aws_ecr_repository.this[0].registry_id : null
}

output "kms_key_arn" {
  description = "KMS key ARN protecting the repository (null for AES256). Grant kms:Decrypt on this to image pullers when encryption_type = KMS."
  value       = local.create && var.encryption_type == "KMS" ? var.kms_key_arn : null
}

################################################################################
# Least-privilege IAM policy documents (attach to CONSUMER roles)
################################################################################
# These are identity policies scoped to THIS repository. Other modules in the
# fleet attach them to their own roles instead of hand-writing ECR permissions:
#   resource "aws_iam_role_policy" "pull" {
#     role   = module.ecs.task_execution_role_name
#     policy = module.ecr.pull_policy_json
#   }

output "pull_policy_json" {
  description = "Least-privilege IAM policy JSON granting image PULL from this repository (+ auth token). Attach to consumer roles."
  value       = local.pull_policy_json
}

output "push_policy_json" {
  description = "Least-privilege IAM policy JSON granting image PULL+PUSH to this repository (+ auth token). Attach to CI/build roles."
  value       = local.push_policy_json
}

################################################################################
# Repository Configuration Information
################################################################################

output "image_tag_mutability" {
  description = "The tag mutability setting for the repository"
  value       = local.create ? aws_ecr_repository.this[0].image_tag_mutability : null
}

output "image_scanning_configuration" {
  description = "The image scanning configuration of the repository"
  value = local.create ? {
    scan_on_push = aws_ecr_repository.this[0].image_scanning_configuration[0].scan_on_push
  } : null
}

output "encryption_configuration" {
  description = "The encryption configuration of the repository"
  value = local.create ? {
    encryption_type = aws_ecr_repository.this[0].encryption_configuration[0].encryption_type
    kms_key_arn     = aws_ecr_repository.this[0].encryption_configuration[0].kms_key
  } : null
  sensitive = true
}

################################################################################
# Policy Information
################################################################################

output "repository_policy_statements" {
  description = "The combined policy statements for the repository (baseline + custom + principals). null when no policy is created. Statements are heterogeneous objects, so this is a tuple, not a list."
  value       = local.create && local.policy_enabled ? local.all_policy_statements : null
  sensitive   = true
}

################################################################################
# Lifecycle Policy Information
################################################################################

output "lifecycle_policy_created" {
  description = "Whether a lifecycle policy was actually created (true only when enabled AND rules are present)."
  value       = local.create && var.enable_lifecycle_policy && length(var.lifecycle_rules) > 0
}

output "lifecycle_rules" {
  description = "The lifecycle rules applied to the repository"
  value       = local.create && var.enable_lifecycle_policy ? var.lifecycle_rules : []
}

################################################################################
# Replication Information
################################################################################

output "replication_enabled" {
  description = "Whether replication is enabled"
  value       = local.create && var.enable_replication
}

output "replication_configuration" {
  description = "The replication configuration (if enabled)"
  value       = local.create && var.enable_replication ? var.replication_rules : []
}

################################################################################
# Logging Information
################################################################################

output "log_group_name" {
  description = "CloudWatch log group name for ECR logs"
  value       = local.create && var.enable_logging ? aws_cloudwatch_log_group.ecr[0].name : null
}

output "log_group_arn" {
  description = "CloudWatch log group ARN for ECR logs"
  value       = local.create && var.enable_logging ? aws_cloudwatch_log_group.ecr[0].arn : null
}

################################################################################
# Access Control Information
################################################################################

output "push_principals" {
  description = "Effective principals with push/pull access (repository_access.push_principals + deprecated allowed_principals)."
  value       = local.eff_push_principals
}

output "pull_principals" {
  description = "Effective principals with pull-only access (repository_access.pull_principals + deprecated allowed_pull_principals)."
  value       = local.eff_pull_principals
}

# deprecated output aliases (kept for backward compatibility)
output "allowed_push_principals" {
  description = "DEPRECATED - use push_principals."
  value       = local.eff_push_principals
}

output "allowed_pull_principals" {
  description = "DEPRECATED - use pull_principals."
  value       = local.eff_pull_principals
}
