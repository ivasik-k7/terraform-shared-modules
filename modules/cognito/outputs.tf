# -----------------------------------------------------------------------------
# User Pool Outputs
# -----------------------------------------------------------------------------
output "user_pool_id" {
  description = "ID of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].id, null)
}

output "user_pool_arn" {
  description = "ARN of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].arn, null)
}

output "user_pool_endpoint" {
  description = "Endpoint of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].endpoint, null)
}

output "user_pool_domain" {
  description = "Domain of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].domain, null)
}

output "user_pool_creation_date" {
  description = "Creation date of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].creation_date, null)
}

output "user_pool_last_modified_date" {
  description = "Last modified date of the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].last_modified_date, null)
}

output "user_pool_estimated_number_of_users" {
  description = "Estimated number of users in the Cognito User Pool"
  value       = try(aws_cognito_user_pool.this[0].estimated_number_of_users, null)
}

# -----------------------------------------------------------------------------
# User Pool Client Outputs
# -----------------------------------------------------------------------------
output "user_pool_client_ids" {
  description = "Map of user pool client IDs"
  value       = { for k, v in aws_cognito_user_pool_client.this : k => v.id }
}

output "user_pool_client_secrets" {
  description = "Map of user pool client secrets"
  value       = { for k, v in aws_cognito_user_pool_client.this : k => v.client_secret }
  sensitive   = true
}

output "user_pool_client_names" {
  description = "Map of user pool client names"
  value       = { for k, v in aws_cognito_user_pool_client.this : k => v.name }
}

# -----------------------------------------------------------------------------
# User Pool Domain Outputs
# -----------------------------------------------------------------------------
output "user_pool_domain_names" {
  description = "Map of user pool domain names"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.domain }
}

output "user_pool_domain_aws_account_ids" {
  description = "Map of AWS account IDs for user pool domains"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.aws_account_id }
}

output "user_pool_domain_cloudfront_distributions" {
  description = "Map of CloudFront distribution ARNs for user pool domains"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.cloudfront_distribution }
}

output "user_pool_domain_cloudfront_distribution_arns" {
  description = "Map of CloudFront distribution ARNs for user pool domains"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.cloudfront_distribution_arn }
}

output "user_pool_domain_s3_buckets" {
  description = "Map of S3 bucket names for user pool domains"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.s3_bucket }
}

output "user_pool_domain_versions" {
  description = "Map of versions for user pool domains"
  value       = { for k, v in aws_cognito_user_pool_domain.this : k => v.version }
}

# -----------------------------------------------------------------------------
# Resource Server Outputs
# -----------------------------------------------------------------------------
output "resource_server_identifiers" {
  description = "Map of resource server identifiers"
  value       = { for k, v in aws_cognito_resource_server.this : k => v.identifier }
}

output "resource_server_scope_identifiers" {
  description = "Map of resource server scope identifiers"
  value       = { for k, v in aws_cognito_resource_server.this : k => v.scope_identifiers }
}

# -----------------------------------------------------------------------------
# Identity Provider Outputs
# -----------------------------------------------------------------------------
output "identity_provider_names" {
  description = "Map of identity provider names"
  value       = { for k, v in aws_cognito_identity_provider.this : k => v.provider_name }
}

output "identity_provider_types" {
  description = "Map of identity provider types"
  value       = { for k, v in aws_cognito_identity_provider.this : k => v.provider_type }
}

# -----------------------------------------------------------------------------
# Identity Pool Outputs
# -----------------------------------------------------------------------------
output "identity_pool_id" {
  description = "ID of the Cognito Identity Pool"
  value       = try(aws_cognito_identity_pool.this[0].id, null)
}

output "identity_pool_arn" {
  description = "ARN of the Cognito Identity Pool"
  value       = try(aws_cognito_identity_pool.this[0].arn, null)
}

output "identity_pool_name" {
  description = "Name of the Cognito Identity Pool"
  value       = try(aws_cognito_identity_pool.this[0].identity_pool_name, null)
}

# -----------------------------------------------------------------------------
# User Group Outputs
# -----------------------------------------------------------------------------
output "user_group_names" {
  description = "Map of user group names"
  value       = { for k, v in aws_cognito_user_group.this : k => v.name }
}

output "user_group_role_arns" {
  description = "Map of user group role ARNs"
  value       = { for k, v in aws_cognito_user_group.this : k => v.role_arn }
}

output "user_group_precedences" {
  description = "Map of user group precedences"
  value       = { for k, v in aws_cognito_user_group.this : k => v.precedence }
}

# -----------------------------------------------------------------------------
# Summary Outputs
# -----------------------------------------------------------------------------
output "user_pool_summary" {
  description = "Summary of Cognito User Pool resources"
  value = var.create_user_pool ? {
    user_pool_id             = try(aws_cognito_user_pool.this[0].id, null)
    user_pool_name           = var.user_pool_name
    user_pool_arn            = try(aws_cognito_user_pool.this[0].arn, null)
    clients_count            = length(aws_cognito_user_pool_client.this)
    domains_count            = length(aws_cognito_user_pool_domain.this)
    resource_servers_count   = length(aws_cognito_resource_server.this)
    identity_providers_count = length(aws_cognito_identity_provider.this)
    user_groups_count        = length(aws_cognito_user_group.this)
    mfa_configuration        = var.mfa_configuration
    deletion_protection      = var.deletion_protection
  } : null
}

output "identity_pool_summary" {
  description = "Summary of Cognito Identity Pool resources"
  value = var.create_identity_pool ? {
    identity_pool_id                 = try(aws_cognito_identity_pool.this[0].id, null)
    identity_pool_name               = var.identity_pool_name
    identity_pool_arn                = try(aws_cognito_identity_pool.this[0].arn, null)
    allow_unauthenticated_identities = var.allow_unauthenticated_identities
    allow_classic_flow               = var.allow_classic_flow
  } : null
}

# -----------------------------------------------------------------------------
# Integration Outputs
# -----------------------------------------------------------------------------
output "user_pool_endpoint_url" {
  description = "Full endpoint URL for the user pool"
  value       = try("https://cognito-idp.${data.aws_region.current.name}.amazonaws.com/${aws_cognito_user_pool.this[0].id}", null)
}

output "hosted_ui_url" {
  description = "Hosted UI URL for the user pool (if domain is configured)"
  value = length(aws_cognito_user_pool_domain.this) > 0 ? {
    for k, v in aws_cognito_user_pool_domain.this :
    k => "https://${v.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
  } : null
}

# -----------------------------------------------------------------------------
# Data Source for Region
# -----------------------------------------------------------------------------
data "aws_region" "current" {}
