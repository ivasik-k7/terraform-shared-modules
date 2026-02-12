output "key_id" {
  description = "The globally unique identifier for the KMS key"
  value       = aws_kms_key.this.key_id
}

output "key_arn" {
  description = "The Amazon Resource Name (ARN) of the KMS key"
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "The display name of the alias"
  value       = var.create_alias ? aws_kms_alias.this[0].name : null
}

output "alias_arn" {
  description = "The Amazon Resource Name (ARN) of the key alias"
  value       = var.create_alias ? aws_kms_alias.this[0].arn : null
}

output "alias_target_key_arn" {
  description = "ARN of the target key associated with the alias"
  value       = var.create_alias ? aws_kms_alias.this[0].target_key_arn : null
}

# ==============================================================================
# KEY ATTRIBUTES
# ==============================================================================

output "key_usage" {
  description = "The cryptographic usage of the KMS key"
  value       = aws_kms_key.this.key_usage
}

output "customer_master_key_spec" {
  description = "The key spec of the KMS key"
  value       = aws_kms_key.this.customer_master_key_spec
}

output "multi_region" {
  description = "Whether the key is a multi-region key"
  value       = aws_kms_key.this.multi_region
}

output "is_enabled" {
  description = "Whether the key is enabled"
  value       = aws_kms_key.this.is_enabled
}

# ==============================================================================
# ROTATION & SECURITY
# ==============================================================================

output "enable_key_rotation" {
  description = "Whether automatic key rotation is enabled"
  value       = aws_kms_key.this.enable_key_rotation
}

output "rotation_period_in_days" {
  description = "The period in days for automatic key rotation"
  value       = aws_kms_key.this.rotation_period_in_days
}

output "deletion_window_in_days" {
  description = "Duration in days before the key is deleted after destruction"
  value       = aws_kms_key.this.deletion_window_in_days
}

# ==============================================================================
# METADATA
# ==============================================================================

output "description" {
  description = "The description of the KMS key"
  value       = aws_kms_key.this.description
}

output "tags" {
  description = "Tags applied to the KMS key"
  value       = aws_kms_key.this.tags_all
}

# ==============================================================================
# GRANTS
# ==============================================================================

output "grant_ids" {
  description = "Map of grant names to their IDs"
  value = {
    for name, grant in aws_kms_grant.this : name => grant.grant_id
  }
}

output "grant_tokens" {
  description = "Map of grant names to their tokens"
  value = {
    for name, grant in aws_kms_grant.this : name => grant.grant_token
  }
  sensitive = true
}

# ==============================================================================
# CONVENIENT OUTPUTS FOR COMMON USE CASES
# ==============================================================================

output "kms_key_for_encryption" {
  description = "Convenient output for use in encryption_key_arn/kms_key_id attributes"
  value = {
    key_id  = aws_kms_key.this.key_id
    key_arn = aws_kms_key.this.arn
    alias   = var.create_alias ? aws_kms_alias.this[0].name : null
  }
}

output "policy" {
  description = "The IAM policy document for the KMS key"
  value       = aws_kms_key.this.policy
  sensitive   = true
}
