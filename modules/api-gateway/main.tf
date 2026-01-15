# ============================================================================
# AWS API Gateway Terraform Module
# ============================================================================
# Supports REST API, HTTP API, and WebSocket API with comprehensive features
# ============================================================================

# -----------------------------------------------------------------------------
# REST API
# -----------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "this" {
  count = var.create_rest_api ? 1 : 0

  name        = var.rest_api_name
  description = var.rest_api_description

  api_key_source               = var.api_key_source
  binary_media_types           = var.binary_media_types
  minimum_compression_size     = var.minimum_compression_size
  disable_execute_api_endpoint = var.disable_execute_api_endpoint

  dynamic "endpoint_configuration" {
    for_each = var.endpoint_configuration != null ? [var.endpoint_configuration] : []
    content {
      types            = endpoint_configuration.value.types
      vpc_endpoint_ids = lookup(endpoint_configuration.value, "vpc_endpoint_ids", null)
    }
  }

  body = var.openapi_spec

  policy = var.rest_api_policy

  tags = merge(
    var.tags,
    var.rest_api_tags,
    {
      Name = var.rest_api_name
    }
  )
}

# -----------------------------------------------------------------------------
# REST API Resources
# -----------------------------------------------------------------------------
resource "aws_api_gateway_resource" "this" {
  for_each = var.create_rest_api ? var.rest_api_resources : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  parent_id   = lookup(each.value, "parent_id", null) != null ? each.value.parent_id : aws_api_gateway_rest_api.this[0].root_resource_id
  path_part   = each.value.path_part
}

# -----------------------------------------------------------------------------
# REST API Methods
# -----------------------------------------------------------------------------
resource "aws_api_gateway_method" "this" {
  for_each = var.create_rest_api ? var.rest_api_methods : {}

  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  resource_id   = lookup(each.value, "resource_key", null) != null ? aws_api_gateway_resource.this[each.value.resource_key].id : each.value.resource_id
  http_method   = each.value.http_method
  authorization = lookup(each.value, "authorization", "NONE")
  authorizer_id = each.value.authorizer_id != null ? each.value.authorizer_id : (
    each.value.authorization == "COGNITO_USER_POOLS" ? aws_api_gateway_authorizer.this["cognito_auth"].id : null
  )

  api_key_required     = lookup(each.value, "api_key_required", false)
  request_parameters   = lookup(each.value, "request_parameters", null)
  request_validator_id = lookup(each.value, "request_validator_id", null)
  authorization_scopes = lookup(each.value, "authorization_scopes", null)
  request_models       = lookup(each.value, "request_models", null)
  operation_name       = lookup(each.value, "operation_name", null)
}

# -----------------------------------------------------------------------------
# REST API Method Responses
# -----------------------------------------------------------------------------
resource "aws_api_gateway_method_response" "this" {
  for_each = var.create_rest_api ? var.rest_api_method_responses : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = aws_api_gateway_method.this[each.value.method_key].resource_id
  http_method = aws_api_gateway_method.this[each.value.method_key].http_method
  status_code = each.value.status_code

  response_parameters = lookup(each.value, "response_parameters", null)
  response_models     = lookup(each.value, "response_models", null)
}

# -----------------------------------------------------------------------------
# REST API Integrations
# -----------------------------------------------------------------------------
resource "aws_api_gateway_integration" "this" {
  for_each = var.create_rest_api ? var.rest_api_integrations : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = aws_api_gateway_method.this[each.value.method_key].resource_id
  http_method = aws_api_gateway_method.this[each.value.method_key].http_method

  type                    = each.value.type
  integration_http_method = lookup(each.value, "integration_http_method", null)
  uri                     = lookup(each.value, "uri", null)
  connection_type         = lookup(each.value, "connection_type", "INTERNET")
  connection_id           = lookup(each.value, "connection_id", null)
  credentials             = lookup(each.value, "credentials", null)

  request_parameters   = lookup(each.value, "request_parameters", null)
  request_templates    = lookup(each.value, "request_templates", null)
  passthrough_behavior = lookup(each.value, "passthrough_behavior", null)
  cache_key_parameters = lookup(each.value, "cache_key_parameters", null)
  cache_namespace      = lookup(each.value, "cache_namespace", null)
  content_handling     = lookup(each.value, "content_handling", null)
  timeout_milliseconds = lookup(each.value, "timeout_milliseconds", 29000)

  dynamic "tls_config" {
    for_each = lookup(each.value, "tls_config", null) != null ? [each.value.tls_config] : []
    content {
      insecure_skip_verification = lookup(tls_config.value, "insecure_skip_verification", false)
    }
  }
}

# -----------------------------------------------------------------------------
# REST API Integration Responses
# -----------------------------------------------------------------------------
resource "aws_api_gateway_integration_response" "this" {
  for_each = var.create_rest_api ? var.rest_api_integration_responses : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  resource_id = aws_api_gateway_integration.this[each.value.integration_key].resource_id
  http_method = aws_api_gateway_integration.this[each.value.integration_key].http_method
  status_code = each.value.status_code

  selection_pattern   = lookup(each.value, "selection_pattern", null)
  response_parameters = lookup(each.value, "response_parameters", null)
  response_templates  = lookup(each.value, "response_templates", null)
  content_handling    = lookup(each.value, "content_handling", null)

  depends_on = [aws_api_gateway_integration.this]
}

# -----------------------------------------------------------------------------
# REST API Authorizers
# -----------------------------------------------------------------------------
resource "aws_api_gateway_authorizer" "this" {
  for_each = var.create_rest_api ? var.rest_api_authorizers : {}

  name                   = each.value.name
  rest_api_id            = aws_api_gateway_rest_api.this[0].id
  type                   = each.value.type
  authorizer_uri         = lookup(each.value, "authorizer_uri", null)
  authorizer_credentials = lookup(each.value, "authorizer_credentials", null)

  identity_source                  = lookup(each.value, "identity_source", null)
  identity_validation_expression   = lookup(each.value, "identity_validation_expression", null)
  authorizer_result_ttl_in_seconds = lookup(each.value, "authorizer_result_ttl_in_seconds", 300)

  provider_arns = lookup(each.value, "provider_arns", null)
}

# -----------------------------------------------------------------------------
# REST API Request Validators
# -----------------------------------------------------------------------------
resource "aws_api_gateway_request_validator" "this" {
  for_each = var.create_rest_api ? var.rest_api_request_validators : {}

  name                        = each.value.name
  rest_api_id                 = aws_api_gateway_rest_api.this[0].id
  validate_request_body       = lookup(each.value, "validate_request_body", false)
  validate_request_parameters = lookup(each.value, "validate_request_parameters", false)
}

# -----------------------------------------------------------------------------
# REST API Models
# -----------------------------------------------------------------------------
resource "aws_api_gateway_model" "this" {
  for_each = var.create_rest_api ? var.rest_api_models : {}

  rest_api_id  = aws_api_gateway_rest_api.this[0].id
  name         = each.value.name
  content_type = each.value.content_type
  schema       = each.value.schema
  description  = lookup(each.value, "description", null)
}

# -----------------------------------------------------------------------------
# REST API Deployment
# -----------------------------------------------------------------------------
resource "aws_api_gateway_deployment" "this" {
  count = var.create_rest_api && var.create_rest_api_deployment ? 1 : 0

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  description = var.rest_api_deployment_description

  triggers = var.rest_api_deployment_triggers

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.this,
    aws_api_gateway_integration_response.this,
    aws_api_gateway_method.this,
    aws_api_gateway_method_response.this
  ]
}

# -----------------------------------------------------------------------------
# REST API Stage
# -----------------------------------------------------------------------------
resource "aws_api_gateway_stage" "this" {
  for_each = var.create_rest_api && var.create_rest_api_deployment ? var.rest_api_stages : {}

  deployment_id = aws_api_gateway_deployment.this[0].id
  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  stage_name    = each.value.stage_name
  description   = lookup(each.value, "description", null)

  cache_cluster_enabled = lookup(each.value, "cache_cluster_enabled", false)
  cache_cluster_size    = lookup(each.value, "cache_cluster_size", null)
  client_certificate_id = lookup(each.value, "client_certificate_id", null)
  documentation_version = lookup(each.value, "documentation_version", null)
  variables             = lookup(each.value, "variables", null)
  xray_tracing_enabled  = lookup(each.value, "xray_tracing_enabled", false)

  dynamic "access_log_settings" {
    for_each = lookup(each.value, "access_log_settings", null) != null ? [each.value.access_log_settings] : []
    content {
      destination_arn = access_log_settings.value.destination_arn
      format          = access_log_settings.value.format
    }
  }

  dynamic "canary_settings" {
    for_each = lookup(each.value, "canary_settings", null) != null ? [each.value.canary_settings] : []
    content {
      deployment_id            = canary_settings.value.deployment_id
      percent_traffic          = canary_settings.value.percent_traffic
      stage_variable_overrides = lookup(canary_settings.value, "stage_variable_overrides", null)
      use_stage_cache          = lookup(canary_settings.value, "use_stage_cache", false)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.stage_name
    }
  )
}

# -----------------------------------------------------------------------------
# REST API Method Settings
# -----------------------------------------------------------------------------
resource "aws_api_gateway_method_settings" "this" {
  for_each = var.create_rest_api ? var.rest_api_method_settings : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id
  stage_name  = aws_api_gateway_stage.this[each.value.stage_key].stage_name
  method_path = each.value.method_path

  settings {
    metrics_enabled                            = lookup(each.value.settings, "metrics_enabled", false)
    logging_level                              = lookup(each.value.settings, "logging_level", "OFF")
    data_trace_enabled                         = lookup(each.value.settings, "data_trace_enabled", false)
    throttling_burst_limit                     = lookup(each.value.settings, "throttling_burst_limit", -1)
    throttling_rate_limit                      = lookup(each.value.settings, "throttling_rate_limit", -1)
    caching_enabled                            = lookup(each.value.settings, "caching_enabled", false)
    cache_ttl_in_seconds                       = lookup(each.value.settings, "cache_ttl_in_seconds", 300)
    cache_data_encrypted                       = lookup(each.value.settings, "cache_data_encrypted", false)
    require_authorization_for_cache_control    = lookup(each.value.settings, "require_authorization_for_cache_control", false)
    unauthorized_cache_control_header_strategy = lookup(each.value.settings, "unauthorized_cache_control_header_strategy", "SUCCEED_WITH_RESPONSE_HEADER")
  }
}

# -----------------------------------------------------------------------------
# REST API Gateway Responses
# -----------------------------------------------------------------------------
resource "aws_api_gateway_gateway_response" "this" {
  for_each = var.create_rest_api ? var.rest_api_gateway_responses : {}

  rest_api_id   = aws_api_gateway_rest_api.this[0].id
  response_type = each.value.response_type
  status_code   = lookup(each.value, "status_code", null)

  response_parameters = lookup(each.value, "response_parameters", null)
  response_templates  = lookup(each.value, "response_templates", null)
}

# -----------------------------------------------------------------------------
# REST API Documentation
# -----------------------------------------------------------------------------
resource "aws_api_gateway_documentation_part" "this" {
  for_each = var.create_rest_api ? var.rest_api_documentation_parts : {}

  rest_api_id = aws_api_gateway_rest_api.this[0].id

  location {
    type        = each.value.location.type
    method      = lookup(each.value.location, "method", null)
    path        = lookup(each.value.location, "path", null)
    name        = lookup(each.value.location, "name", null)
    status_code = lookup(each.value.location, "status_code", null)
  }

  properties = each.value.properties
}

# -----------------------------------------------------------------------------
# REST API Usage Plans
# -----------------------------------------------------------------------------
resource "aws_api_gateway_usage_plan" "this" {
  for_each = var.create_rest_api ? var.rest_api_usage_plans : {}

  name        = each.value.name
  description = lookup(each.value, "description", null)

  dynamic "api_stages" {
    for_each = lookup(each.value, "api_stages", [])
    content {
      api_id = aws_api_gateway_rest_api.this[0].id
      stage  = api_stages.value.stage
      #   throttle = lookup(api_stages.value, "throttle", null)
    }
  }

  dynamic "quota_settings" {
    for_each = lookup(each.value, "quota_settings", null) != null ? [each.value.quota_settings] : []
    content {
      limit  = quota_settings.value.limit
      offset = lookup(quota_settings.value, "offset", 0)
      period = quota_settings.value.period
    }
  }

  dynamic "throttle_settings" {
    for_each = lookup(each.value, "throttle_settings", null) != null ? [each.value.throttle_settings] : []
    content {
      burst_limit = lookup(throttle_settings.value, "burst_limit", null)
      rate_limit  = lookup(throttle_settings.value, "rate_limit", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# REST API Keys
# -----------------------------------------------------------------------------
resource "aws_api_gateway_api_key" "this" {
  for_each = var.create_rest_api ? var.rest_api_keys : {}

  name        = each.value.name
  description = lookup(each.value, "description", null)
  enabled     = lookup(each.value, "enabled", true)
  value       = lookup(each.value, "value", null)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# REST API Usage Plan Keys
# -----------------------------------------------------------------------------
resource "aws_api_gateway_usage_plan_key" "this" {
  for_each = var.create_rest_api ? var.rest_api_usage_plan_keys : {}

  key_id        = aws_api_gateway_api_key.this[each.value.api_key_key].id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.this[each.value.usage_plan_key].id
}

# -----------------------------------------------------------------------------
# REST API Domain Name
# -----------------------------------------------------------------------------
resource "aws_api_gateway_domain_name" "this" {
  for_each = var.create_rest_api ? var.rest_api_domain_names : {}

  domain_name              = each.value.domain_name
  certificate_arn          = lookup(each.value, "certificate_arn", null)
  certificate_name         = lookup(each.value, "certificate_name", null)
  certificate_body         = lookup(each.value, "certificate_body", null)
  certificate_chain        = lookup(each.value, "certificate_chain", null)
  certificate_private_key  = lookup(each.value, "certificate_private_key", null)
  regional_certificate_arn = lookup(each.value, "regional_certificate_arn", null)
  security_policy          = lookup(each.value, "security_policy", "TLS_1_2")

  dynamic "endpoint_configuration" {
    for_each = lookup(each.value, "endpoint_configuration", null) != null ? [each.value.endpoint_configuration] : []
    content {
      types = endpoint_configuration.value.types
    }
  }

  dynamic "mutual_tls_authentication" {
    for_each = lookup(each.value, "mutual_tls_authentication", null) != null ? [each.value.mutual_tls_authentication] : []
    content {
      truststore_uri     = mutual_tls_authentication.value.truststore_uri
      truststore_version = lookup(mutual_tls_authentication.value, "truststore_version", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# REST API Base Path Mapping
# -----------------------------------------------------------------------------
resource "aws_api_gateway_base_path_mapping" "this" {
  for_each = var.create_rest_api ? var.rest_api_base_path_mappings : {}

  api_id      = aws_api_gateway_rest_api.this[0].id
  stage_name  = aws_api_gateway_stage.this[each.value.stage_key].stage_name
  domain_name = aws_api_gateway_domain_name.this[each.value.domain_key].domain_name
  base_path   = lookup(each.value, "base_path", null)
}

# -----------------------------------------------------------------------------
# REST API VPC Link
# -----------------------------------------------------------------------------
resource "aws_api_gateway_vpc_link" "this" {
  for_each = var.rest_api_vpc_links

  name        = each.value.name
  description = lookup(each.value, "description", null)
  target_arns = each.value.target_arns

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# HTTP API (v2)
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "this" {
  count = var.create_http_api ? 1 : 0

  name          = var.http_api_name
  description   = var.http_api_description
  protocol_type = var.http_api_protocol_type
  version       = var.http_api_version
  body          = var.http_api_body

  api_key_selection_expression = var.api_key_selection_expression
  route_selection_expression   = var.route_selection_expression
  disable_execute_api_endpoint = var.http_disable_execute_api_endpoint

  dynamic "cors_configuration" {
    for_each = var.http_api_cors_configuration != null ? [var.http_api_cors_configuration] : []
    content {
      allow_credentials = lookup(cors_configuration.value, "allow_credentials", false)
      allow_headers     = lookup(cors_configuration.value, "allow_headers", null)
      allow_methods     = lookup(cors_configuration.value, "allow_methods", null)
      allow_origins     = lookup(cors_configuration.value, "allow_origins", null)
      expose_headers    = lookup(cors_configuration.value, "expose_headers", null)
      max_age           = lookup(cors_configuration.value, "max_age", null)
    }
  }

  tags = merge(
    var.tags,
    var.http_api_tags,
    {
      Name = var.http_api_name
    }
  )
}

# -----------------------------------------------------------------------------
# HTTP API Authorizers
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_authorizer" "this" {
  for_each = var.create_http_api ? var.http_api_authorizers : {}

  api_id          = aws_apigatewayv2_api.this[0].id
  authorizer_type = each.value.authorizer_type
  name            = each.value.name

  authorizer_uri                    = lookup(each.value, "authorizer_uri", null)
  authorizer_payload_format_version = lookup(each.value, "authorizer_payload_format_version", null)
  authorizer_result_ttl_in_seconds  = lookup(each.value, "authorizer_result_ttl_in_seconds", 300)
  authorizer_credentials_arn        = lookup(each.value, "authorizer_credentials_arn", null)
  identity_sources                  = lookup(each.value, "identity_sources", null)
  enable_simple_responses           = lookup(each.value, "enable_simple_responses", false)

  dynamic "jwt_configuration" {
    for_each = lookup(each.value, "jwt_configuration", null) != null ? [each.value.jwt_configuration] : []
    content {
      audience = lookup(jwt_configuration.value, "audience", null)
      issuer   = lookup(jwt_configuration.value, "issuer", null)
    }
  }
}

# -----------------------------------------------------------------------------
# HTTP API Integrations
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_integration" "this" {
  for_each = var.create_http_api ? var.http_api_integrations : {}

  api_id           = aws_apigatewayv2_api.this[0].id
  integration_type = each.value.integration_type

  integration_uri               = lookup(each.value, "integration_uri", null)
  integration_method            = lookup(each.value, "integration_method", null)
  connection_type               = lookup(each.value, "connection_type", "INTERNET")
  connection_id                 = lookup(each.value, "connection_id", null)
  credentials_arn               = lookup(each.value, "credentials_arn", null)
  description                   = lookup(each.value, "description", null)
  integration_subtype           = lookup(each.value, "integration_subtype", null)
  passthrough_behavior          = lookup(each.value, "passthrough_behavior", null)
  payload_format_version        = lookup(each.value, "payload_format_version", "2.0")
  request_parameters            = lookup(each.value, "request_parameters", null)
  request_templates             = lookup(each.value, "request_templates", null)
  template_selection_expression = lookup(each.value, "template_selection_expression", null)
  timeout_milliseconds          = lookup(each.value, "timeout_milliseconds", 30000)

  dynamic "response_parameters" {
    for_each = coalesce(lookup(each.value, "response_parameters", []), [])

    content {
      status_code = response_parameters.value.status_code
      mappings    = response_parameters.value.mappings
    }
  }

  dynamic "tls_config" {
    for_each = lookup(each.value, "tls_config", null) != null ? [each.value.tls_config] : []
    content {
      server_name_to_verify = lookup(tls_config.value, "server_name_to_verify", null)
    }
  }
}

# -----------------------------------------------------------------------------
# HTTP API Routes
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_route" "this" {
  for_each = var.create_http_api ? var.http_api_routes : {}

  api_id    = aws_apigatewayv2_api.this[0].id
  route_key = each.value.route_key

  target                     = lookup(each.value, "integration_key", null) != null ? "integrations/${aws_apigatewayv2_integration.this[each.value.integration_key].id}" : lookup(each.value, "target", null)
  authorization_type         = lookup(each.value, "authorization_type", "NONE")
  authorizer_id              = lookup(each.value, "authorizer_key", null) != null ? aws_apigatewayv2_authorizer.this[each.value.authorizer_key].id : lookup(each.value, "authorizer_id", null)
  api_key_required           = lookup(each.value, "api_key_required", false)
  authorization_scopes       = lookup(each.value, "authorization_scopes", null)
  model_selection_expression = lookup(each.value, "model_selection_expression", null)
  operation_name             = lookup(each.value, "operation_name", null)
  request_models             = lookup(each.value, "request_models", null)
  #   request_parameters                  = lookup(each.value, "request_parameters", null)
  route_response_selection_expression = lookup(each.value, "route_response_selection_expression", null)
}

# -----------------------------------------------------------------------------
# HTTP API Stage
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_stage" "this" {
  for_each = var.create_http_api ? var.http_api_stages : {}

  api_id      = aws_apigatewayv2_api.this[0].id
  name        = each.value.name
  description = lookup(each.value, "description", null)
  auto_deploy = lookup(each.value, "auto_deploy", true)

  deployment_id         = lookup(each.value, "deployment_id", null)
  stage_variables       = lookup(each.value, "stage_variables", null)
  client_certificate_id = lookup(each.value, "client_certificate_id", null)

  dynamic "access_log_settings" {
    for_each = lookup(each.value, "access_log_settings", null) != null ? [each.value.access_log_settings] : []
    content {
      destination_arn = access_log_settings.value.destination_arn
      format          = access_log_settings.value.format
    }
  }

  dynamic "default_route_settings" {
    for_each = lookup(each.value, "default_route_settings", null) != null ? [each.value.default_route_settings] : []
    content {
      data_trace_enabled       = lookup(default_route_settings.value, "data_trace_enabled", false)
      detailed_metrics_enabled = lookup(default_route_settings.value, "detailed_metrics_enabled", false)
      logging_level            = lookup(default_route_settings.value, "logging_level", null)
      throttling_burst_limit   = lookup(default_route_settings.value, "throttling_burst_limit", null)
      throttling_rate_limit    = lookup(default_route_settings.value, "throttling_rate_limit", null)
    }
  }

  dynamic "route_settings" {
    for_each = try(each.value.route_settings, []) != null ? each.value.route_settings : []
    content {
      route_key                = route_settings.value.route_key
      data_trace_enabled       = lookup(route_settings.value, "data_trace_enabled", false)
      detailed_metrics_enabled = lookup(route_settings.value, "detailed_metrics_enabled", false)
      logging_level            = lookup(route_settings.value, "logging_level", null)
      throttling_burst_limit   = lookup(route_settings.value, "throttling_burst_limit", null)
      throttling_rate_limit    = lookup(route_settings.value, "throttling_rate_limit", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# HTTP API Domain Name
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_domain_name" "this" {
  for_each = var.create_http_api ? var.http_api_domain_names : {}

  domain_name = each.value.domain_name

  domain_name_configuration {
    certificate_arn = each.value.certificate_arn
    endpoint_type   = lookup(each.value, "endpoint_type", "REGIONAL")
    security_policy = lookup(each.value, "security_policy", "TLS_1_2")
  }

  dynamic "mutual_tls_authentication" {
    for_each = lookup(each.value, "mutual_tls_authentication", null) != null ? [each.value.mutual_tls_authentication] : []
    content {
      truststore_uri     = mutual_tls_authentication.value.truststore_uri
      truststore_version = lookup(mutual_tls_authentication.value, "truststore_version", null)
    }
  }

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}

# -----------------------------------------------------------------------------
# HTTP API Mapping
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_api_mapping" "this" {
  for_each = var.create_http_api ? var.http_api_mappings : {}

  api_id          = aws_apigatewayv2_api.this[0].id
  domain_name     = aws_apigatewayv2_domain_name.this[each.value.domain_key].id
  stage           = aws_apigatewayv2_stage.this[each.value.stage_key].id
  api_mapping_key = lookup(each.value, "api_mapping_key", null)
}

# -----------------------------------------------------------------------------
# HTTP API VPC Link
# -----------------------------------------------------------------------------
resource "aws_apigatewayv2_vpc_link" "this" {
  for_each = var.http_api_vpc_links

  name               = each.value.name
  security_group_ids = each.value.security_group_ids
  subnet_ids         = each.value.subnet_ids

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {})
  )
}
