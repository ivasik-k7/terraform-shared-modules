# API Gateway Outputs
output "api_id" {
  description = "The ID of the REST API"
  value       = aws_api_gateway_rest_api.textract_api.id
}

output "api_root_resource_id" {
  description = "The resource ID of the REST API's root"
  value       = aws_api_gateway_rest_api.textract_api.root_resource_id
}

output "api_endpoint" {
  description = "The endpoint URL of the REST API"
  value       = "https://${aws_api_gateway_rest_api.textract_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}"
}

output "stage_invoke_url" {
  description = "The URL to invoke the API pointing to the stage"
  value       = "https://${aws_api_gateway_rest_api.textract_api.id}.execute-api.${data.aws_region.current.name}.amazonaws.com/${var.environment}"
}

output "execution_arn" {
  description = "The execution ARN of the REST API"
  value       = "arn:aws:execute-api:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:${aws_api_gateway_rest_api.textract_api.id}/*"
}

# Custom Domain Outputs
output "custom_domain_endpoint" {
  description = "The endpoint URL of the custom domain"
  value       = local.has_custom_domain ? "https://${aws_api_gateway_domain_name.custom_domain[0].domain_name}" : null
}

output "custom_domain_id" {
  description = "The ID of the custom domain"
  value       = local.has_custom_domain ? aws_api_gateway_domain_name.custom_domain[0].id : null
}

output "custom_domain_arn" {
  description = "The ARN of the custom domain"
  value       = local.has_custom_domain ? aws_api_gateway_domain_name.custom_domain[0].arn : null
}

output "custom_domain_regional_domain_name" {
  description = "The regional domain name"
  value       = local.has_custom_domain ? aws_api_gateway_domain_name.custom_domain[0].regional_domain_name : null
}

output "custom_domain_regional_zone_id" {
  description = "The regional zone ID"
  value       = local.has_custom_domain ? aws_api_gateway_domain_name.custom_domain[0].regional_zone_id : null
}

# Logging Outputs
output "cloudwatch_log_group_name" {
  description = "The name of the CloudWatch Log Group"
  value       = var.logging_configuration.enabled ? aws_cloudwatch_log_group.api_logs[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "The ARN of the CloudWatch Log Group"
  value       = var.logging_configuration.enabled ? aws_cloudwatch_log_group.api_logs[0].arn : null
}

# IAM Outputs
output "api_gateway_role_arn" {
  description = "The ARN of the IAM role for API Gateway to invoke Textract"
  value       = aws_iam_role.api_gateway_textract.arn
}

output "cloudwatch_logs_role_arn" {
  description = "The ARN of the IAM role for CloudWatch Logs"
  value       = var.logging_configuration.enabled ? aws_iam_role.cloudwatch_logs[0].arn : null
}

# Resource Outputs
output "stage_id" {
  description = "The ID of the stage"
  value       = aws_api_gateway_stage.stage.id
}

output "deployment_id" {
  description = "The ID of the deployment"
  value       = aws_api_gateway_deployment.deployment.id
}

output "resource_ids" {
  description = "Map of resource paths to their IDs"
  value = {
    for key, resource in aws_api_gateway_resource.api_resources :
    resource.path_part => resource.id
  }
}

output "method_ids" {
  description = "Map of method paths to their IDs"
  value = {
    for key, method in aws_api_gateway_method.api_methods :
    key => method.id
  }
}

# Configuration Outputs
output "textract_features" {
  description = "Configured Textract features"
  value       = var.textract_features
}

output "input_bucket_name" {
  description = "Input bucket name"
  value       = local.input_bucket_name
}

output "output_bucket_name" {
  description = "Output bucket name"
  value       = local.output_bucket_name
}

# output "endpoint_type" {
#   description = "API endpoint type"
#   value       = local.endpoint_config.type
# }

output "cors_configuration" {
  description = "CORS configuration"
  value       = var.cors_configuration
}

output "throttling_configuration" {
  description = "Throttling configuration"
  value       = var.throttling_configuration
}

output "common_tags" {
  description = "Common tags applied to all resources"
  value       = local.common_tags
}

output "name_prefix" {
  description = "Generated name prefix for resources"
  value       = local.name_prefix
}

output "name_prefix_short" {
  description = "Generated short name prefix for resources"
  value       = local.name_prefix_short
}

# Usage Outputs
output "api_endpoints" {
  description = "All available API endpoints"
  value = {
    for route_key, route in local.enabled_routes :
    route_key => "${aws_api_gateway_stage.stage.invoke_url}${split(" ", route_key)[1]}"
  }
}

output "health_check_endpoint" {
  description = "Health check endpoint URL"
  value       = "${aws_api_gateway_stage.stage.invoke_url}/health"
}

output "async_operations_enabled" {
  description = "Whether async operations are enabled"
  value       = var.enable_async_operations
}

output "sync_operations_enabled" {
  description = "Whether sync operations are enabled"
  value       = var.enable_sync_operations
}
