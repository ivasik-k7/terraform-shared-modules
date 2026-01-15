# ============================================================================
# AWS API Gateway Module Outputs
# ============================================================================

# -----------------------------------------------------------------------------
# REST API Outputs
# -----------------------------------------------------------------------------
output "rest_api_id" {
  description = "ID of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].id, null)
}

output "rest_api_arn" {
  description = "ARN of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].arn, null)
}

output "rest_api_root_resource_id" {
  description = "Root resource ID of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].root_resource_id, null)
}

output "rest_api_execution_arn" {
  description = "Execution ARN of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].execution_arn, null)
}

output "rest_api_created_date" {
  description = "Creation date of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].created_date, null)
}

output "rest_api_endpoint_configuration" {
  description = "Endpoint configuration of the REST API"
  value       = try(aws_api_gateway_rest_api.this[0].endpoint_configuration, null)
}

# -----------------------------------------------------------------------------
# REST API Resource Outputs
# -----------------------------------------------------------------------------
output "rest_api_resource_ids" {
  description = "Map of REST API resource IDs"
  value       = { for k, v in aws_api_gateway_resource.this : k => v.id }
}

output "rest_api_resource_paths" {
  description = "Map of REST API resource paths"
  value       = { for k, v in aws_api_gateway_resource.this : k => v.path }
}

# -----------------------------------------------------------------------------
# REST API Method Outputs
# -----------------------------------------------------------------------------
output "rest_api_method_ids" {
  description = "Map of REST API method IDs"
  value       = { for k, v in aws_api_gateway_method.this : k => v.id }
}

# -----------------------------------------------------------------------------
# REST API Authorizer Outputs
# -----------------------------------------------------------------------------
output "rest_api_authorizer_ids" {
  description = "Map of REST API authorizer IDs"
  value       = { for k, v in aws_api_gateway_authorizer.this : k => v.id }
}

output "rest_api_authorizer_arns" {
  description = "Map of REST API authorizer ARNs"
  value       = { for k, v in aws_api_gateway_authorizer.this : k => v.arn }
}

# -----------------------------------------------------------------------------
# REST API Request Validator Outputs
# -----------------------------------------------------------------------------
output "rest_api_request_validator_ids" {
  description = "Map of REST API request validator IDs"
  value       = { for k, v in aws_api_gateway_request_validator.this : k => v.id }
}

# -----------------------------------------------------------------------------
# REST API Model Outputs
# -----------------------------------------------------------------------------
output "rest_api_model_ids" {
  description = "Map of REST API model IDs"
  value       = { for k, v in aws_api_gateway_model.this : k => v.id }
}

# -----------------------------------------------------------------------------
# REST API Deployment Outputs
# -----------------------------------------------------------------------------
output "rest_api_deployment_id" {
  description = "ID of the REST API deployment"
  value       = try(aws_api_gateway_deployment.this[0].id, null)
}

output "rest_api_deployment_invoke_url" {
  description = "Invoke URL of the REST API deployment"
  value       = try(aws_api_gateway_deployment.this[0].invoke_url, null)
}

output "rest_api_deployment_execution_arn" {
  description = "Execution ARN of the REST API deployment"
  value       = try(aws_api_gateway_deployment.this[0].execution_arn, null)
}

# -----------------------------------------------------------------------------
# REST API Stage Outputs
# -----------------------------------------------------------------------------
output "rest_api_stage_ids" {
  description = "Map of REST API stage IDs"
  value       = { for k, v in aws_api_gateway_stage.this : k => v.id }
}

output "rest_api_stage_arns" {
  description = "Map of REST API stage ARNs"
  value       = { for k, v in aws_api_gateway_stage.this : k => v.arn }
}

output "rest_api_stage_invoke_urls" {
  description = "Map of REST API stage invoke URLs"
  value       = { for k, v in aws_api_gateway_stage.this : k => v.invoke_url }
}

output "rest_api_stage_execution_arns" {
  description = "Map of REST API stage execution ARNs"
  value       = { for k, v in aws_api_gateway_stage.this : k => v.execution_arn }
}

# -----------------------------------------------------------------------------
# REST API Usage Plan Outputs
# -----------------------------------------------------------------------------
output "rest_api_usage_plan_ids" {
  description = "Map of REST API usage plan IDs"
  value       = { for k, v in aws_api_gateway_usage_plan.this : k => v.id }
}

output "rest_api_usage_plan_arns" {
  description = "Map of REST API usage plan ARNs"
  value       = { for k, v in aws_api_gateway_usage_plan.this : k => v.arn }
}

# -----------------------------------------------------------------------------
# REST API Key Outputs
# -----------------------------------------------------------------------------
output "rest_api_key_ids" {
  description = "Map of REST API key IDs"
  value       = { for k, v in aws_api_gateway_api_key.this : k => v.id }
}

output "rest_api_key_values" {
  description = "Map of REST API key values"
  value       = { for k, v in aws_api_gateway_api_key.this : k => v.value }
  sensitive   = true
}

output "rest_api_key_arns" {
  description = "Map of REST API key ARNs"
  value       = { for k, v in aws_api_gateway_api_key.this : k => v.arn }
}

# -----------------------------------------------------------------------------
# REST API Domain Name Outputs
# -----------------------------------------------------------------------------
output "rest_api_domain_name_ids" {
  description = "Map of REST API domain name IDs"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.id }
}

output "rest_api_domain_name_arns" {
  description = "Map of REST API domain name ARNs"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.arn }
}

output "rest_api_domain_name_cloudfront_domain_names" {
  description = "Map of CloudFront domain names for REST API custom domains"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.cloudfront_domain_name }
}

output "rest_api_domain_name_cloudfront_zone_ids" {
  description = "Map of CloudFront zone IDs for REST API custom domains"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.cloudfront_zone_id }
}

output "rest_api_domain_name_regional_domain_names" {
  description = "Map of regional domain names for REST API custom domains"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.regional_domain_name }
}

output "rest_api_domain_name_regional_zone_ids" {
  description = "Map of regional zone IDs for REST API custom domains"
  value       = { for k, v in aws_api_gateway_domain_name.this : k => v.regional_zone_id }
}

# -----------------------------------------------------------------------------
# REST API VPC Link Outputs
# -----------------------------------------------------------------------------
output "rest_api_vpc_link_ids" {
  description = "Map of REST API VPC link IDs"
  value       = { for k, v in aws_api_gateway_vpc_link.this : k => v.id }
}

output "rest_api_vpc_link_arns" {
  description = "Map of REST API VPC link ARNs"
  value       = { for k, v in aws_api_gateway_vpc_link.this : k => v.arn }
}

# -----------------------------------------------------------------------------
# HTTP API Outputs
# -----------------------------------------------------------------------------
output "http_api_id" {
  description = "ID of the HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].id, null)
}

output "http_api_arn" {
  description = "ARN of the HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].arn, null)
}

output "http_api_endpoint" {
  description = "Endpoint of the HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
}

output "http_api_execution_arn" {
  description = "Execution ARN of the HTTP API"
  value       = try(aws_apigatewayv2_api.this[0].execution_arn, null)
}

# -----------------------------------------------------------------------------
# HTTP API Authorizer Outputs
# -----------------------------------------------------------------------------
output "http_api_authorizer_ids" {
  description = "Map of HTTP API authorizer IDs"
  value       = { for k, v in aws_apigatewayv2_authorizer.this : k => v.id }
}

# -----------------------------------------------------------------------------
# HTTP API Integration Outputs
# -----------------------------------------------------------------------------
output "http_api_integration_ids" {
  description = "Map of HTTP API integration IDs"
  value       = { for k, v in aws_apigatewayv2_integration.this : k => v.id }
}

output "http_api_integration_response_selection_expressions" {
  description = "Map of HTTP API integration response selection expressions"
  value       = { for k, v in aws_apigatewayv2_integration.this : k => v.integration_response_selection_expression }
}

# -----------------------------------------------------------------------------
# HTTP API Route Outputs
# -----------------------------------------------------------------------------
output "http_api_route_ids" {
  description = "Map of HTTP API route IDs"
  value       = { for k, v in aws_apigatewayv2_route.this : k => v.id }
}

# -----------------------------------------------------------------------------
# HTTP API Stage Outputs
# -----------------------------------------------------------------------------
output "http_api_stage_ids" {
  description = "Map of HTTP API stage IDs"
  value       = { for k, v in aws_apigatewayv2_stage.this : k => v.id }
}

output "http_api_stage_arns" {
  description = "Map of HTTP API stage ARNs"
  value       = { for k, v in aws_apigatewayv2_stage.this : k => v.arn }
}

output "http_api_stage_invoke_urls" {
  description = "Map of HTTP API stage invoke URLs"
  value       = { for k, v in aws_apigatewayv2_stage.this : k => v.invoke_url }
}

output "http_api_stage_execution_arns" {
  description = "Map of HTTP API stage execution ARNs"
  value       = { for k, v in aws_apigatewayv2_stage.this : k => v.execution_arn }
}

# -----------------------------------------------------------------------------
# HTTP API Domain Name Outputs
# -----------------------------------------------------------------------------
output "http_api_domain_name_ids" {
  description = "Map of HTTP API domain name IDs"
  value       = { for k, v in aws_apigatewayv2_domain_name.this : k => v.id }
}

output "http_api_domain_name_arns" {
  description = "Map of HTTP API domain name ARNs"
  value       = { for k, v in aws_apigatewayv2_domain_name.this : k => v.arn }
}

output "http_api_domain_name_targets" {
  description = "Map of HTTP API domain name target domain names"
  value       = { for k, v in aws_apigatewayv2_domain_name.this : k => v.domain_name_configuration[0].target_domain_name }
}

output "http_api_domain_name_hosted_zone_ids" {
  description = "Map of HTTP API domain name hosted zone IDs"
  value       = { for k, v in aws_apigatewayv2_domain_name.this : k => v.domain_name_configuration[0].hosted_zone_id }
}

# -----------------------------------------------------------------------------
# HTTP API Mapping Outputs
# -----------------------------------------------------------------------------
output "http_api_mapping_ids" {
  description = "Map of HTTP API mapping IDs"
  value       = { for k, v in aws_apigatewayv2_api_mapping.this : k => v.id }
}

# -----------------------------------------------------------------------------
# HTTP API VPC Link Outputs
# -----------------------------------------------------------------------------
output "http_api_vpc_link_ids" {
  description = "Map of HTTP API VPC link IDs"
  value       = { for k, v in aws_apigatewayv2_vpc_link.this : k => v.id }
}

output "http_api_vpc_link_arns" {
  description = "Map of HTTP API VPC link ARNs"
  value       = { for k, v in aws_apigatewayv2_vpc_link.this : k => v.arn }
}

# -----------------------------------------------------------------------------
# Summary Outputs
# -----------------------------------------------------------------------------
output "rest_api_summary" {
  description = "Summary of REST API resources"
  value = var.create_rest_api ? {
    api_id               = try(aws_api_gateway_rest_api.this[0].id, null)
    api_name             = var.rest_api_name
    endpoint_type        = try(var.endpoint_configuration.types, ["EDGE"])
    resources_count      = length(aws_api_gateway_resource.this)
    methods_count        = length(aws_api_gateway_method.this)
    authorizers_count    = length(aws_api_gateway_authorizer.this)
    stages_count         = length(aws_api_gateway_stage.this)
    usage_plans_count    = length(aws_api_gateway_usage_plan.this)
    api_keys_count       = length(aws_api_gateway_api_key.this)
    custom_domains_count = length(aws_api_gateway_domain_name.this)
    vpc_links_count      = length(aws_api_gateway_vpc_link.this)
  } : null
}

output "http_api_summary" {
  description = "Summary of HTTP API resources"
  value = var.create_http_api ? {
    api_id               = try(aws_apigatewayv2_api.this[0].id, null)
    api_name             = var.http_api_name
    protocol_type        = var.http_api_protocol_type
    api_endpoint         = try(aws_apigatewayv2_api.this[0].api_endpoint, null)
    authorizers_count    = length(aws_apigatewayv2_authorizer.this)
    integrations_count   = length(aws_apigatewayv2_integration.this)
    routes_count         = length(aws_apigatewayv2_route.this)
    stages_count         = length(aws_apigatewayv2_stage.this)
    custom_domains_count = length(aws_apigatewayv2_domain_name.this)
    vpc_links_count      = length(aws_apigatewayv2_vpc_link.this)
  } : null
}
