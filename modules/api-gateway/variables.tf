# ============================================================================
# AWS API Gateway Module Variables
# ============================================================================

# -----------------------------------------------------------------------------
# General Settings
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# REST API Settings
# -----------------------------------------------------------------------------
variable "create_rest_api" {
  description = "Whether to create a REST API"
  type        = bool
  default     = false
}

variable "rest_api_name" {
  description = "Name of the REST API"
  type        = string
  default     = ""
}

variable "rest_api_description" {
  description = "Description of the REST API"
  type        = string
  default     = null
}

variable "api_key_source" {
  description = "Source of the API key for requests (HEADER or AUTHORIZER)"
  type        = string
  default     = "HEADER"
  validation {
    condition     = can(regex("^(HEADER|AUTHORIZER)$", var.api_key_source))
    error_message = "API key source must be HEADER or AUTHORIZER."
  }
}

variable "binary_media_types" {
  description = "List of binary media types supported by the REST API"
  type        = list(string)
  default     = []
}

variable "minimum_compression_size" {
  description = "Minimum response size to compress for the REST API (-1 to disable)"
  type        = number
  default     = -1
}

variable "disable_execute_api_endpoint" {
  description = "Whether to disable the default execute-api endpoint"
  type        = bool
  default     = false
}

variable "endpoint_configuration" {
  description = "Endpoint configuration for the REST API"
  type = object({
    types            = list(string)
    vpc_endpoint_ids = optional(list(string))
  })
  default = null
}

variable "openapi_spec" {
  description = "OpenAPI specification for the REST API"
  type        = string
  default     = null
}

variable "rest_api_policy" {
  description = "IAM policy document for the REST API"
  type        = string
  default     = null
}

variable "rest_api_tags" {
  description = "Additional tags for the REST API"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# REST API Resources
# -----------------------------------------------------------------------------
variable "rest_api_resources" {
  description = "Map of REST API resources to create"
  type = map(object({
    path_part = string
    parent_id = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Methods
# -----------------------------------------------------------------------------
variable "rest_api_methods" {
  description = "Map of REST API methods to create"
  type = map(object({
    resource_id          = optional(string)
    resource_key         = optional(string)
    http_method          = string
    authorization        = optional(string)
    authorizer_id        = optional(string)
    api_key_required     = optional(bool)
    request_parameters   = optional(map(bool))
    request_validator_id = optional(string)
    authorization_scopes = optional(list(string))
    request_models       = optional(map(string))
    operation_name       = optional(string)
  }))
  default = {}
}

variable "rest_api_method_responses" {
  description = "Map of REST API method responses"
  type = map(object({
    method_key          = string
    status_code         = string
    response_parameters = optional(map(bool))
    response_models     = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Integrations
# -----------------------------------------------------------------------------
variable "rest_api_integrations" {
  description = "Map of REST API integrations"
  type = map(object({
    method_key              = string
    type                    = string
    integration_http_method = optional(string)
    uri                     = optional(string)
    connection_type         = optional(string)
    connection_id           = optional(string)
    credentials             = optional(string)
    request_parameters      = optional(map(string))
    request_templates       = optional(map(string))
    passthrough_behavior    = optional(string)
    cache_key_parameters    = optional(list(string))
    cache_namespace         = optional(string)
    content_handling        = optional(string)
    timeout_milliseconds    = optional(number)
    tls_config = optional(object({
      insecure_skip_verification = optional(bool)
    }))
  }))
  default = {}
}

variable "rest_api_integration_responses" {
  description = "Map of REST API integration responses"
  type = map(object({
    integration_key     = string
    status_code         = string
    selection_pattern   = optional(string)
    response_parameters = optional(map(string))
    response_templates  = optional(map(string))
    content_handling    = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Authorizers
# -----------------------------------------------------------------------------
variable "rest_api_authorizers" {
  description = "Map of REST API authorizers"
  type = map(object({
    name                             = string
    type                             = string
    authorizer_uri                   = optional(string)
    authorizer_credentials           = optional(string)
    identity_source                  = optional(string)
    identity_validation_expression   = optional(string)
    authorizer_result_ttl_in_seconds = optional(number)
    provider_arns                    = optional(list(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Request Validators
# -----------------------------------------------------------------------------
variable "rest_api_request_validators" {
  description = "Map of REST API request validators"
  type = map(object({
    name                        = string
    validate_request_body       = optional(bool)
    validate_request_parameters = optional(bool)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Models
# -----------------------------------------------------------------------------
variable "rest_api_models" {
  description = "Map of REST API models"
  type = map(object({
    name         = string
    content_type = string
    schema       = string
    description  = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Deployment
# -----------------------------------------------------------------------------
variable "create_rest_api_deployment" {
  description = "Whether to create a deployment for the REST API"
  type        = bool
  default     = true
}

variable "rest_api_deployment_description" {
  description = "Description of the REST API deployment"
  type        = string
  default     = null
}

variable "rest_api_deployment_triggers" {
  description = "Map of triggers to redeploy the REST API"
  type        = map(string)
  default     = null
}

# -----------------------------------------------------------------------------
# REST API Stages
# -----------------------------------------------------------------------------
variable "rest_api_stages" {
  description = "Map of REST API stages"
  type = map(object({
    stage_name            = string
    description           = optional(string)
    cache_cluster_enabled = optional(bool)
    cache_cluster_size    = optional(string)
    client_certificate_id = optional(string)
    documentation_version = optional(string)
    variables             = optional(map(string))
    xray_tracing_enabled  = optional(bool)
    access_log_settings = optional(object({
      destination_arn = string
      format          = string
    }))
    canary_settings = optional(object({
      percent_traffic          = number
      stage_variable_overrides = optional(map(string))
      use_stage_cache          = optional(bool)
    }))
    tags = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Method Settings
# -----------------------------------------------------------------------------
variable "rest_api_method_settings" {
  description = "Map of REST API method settings"
  type = map(object({
    stage_key   = string
    method_path = string
    settings = object({
      metrics_enabled                            = optional(bool)
      logging_level                              = optional(string)
      data_trace_enabled                         = optional(bool)
      throttling_burst_limit                     = optional(number)
      throttling_rate_limit                      = optional(number)
      caching_enabled                            = optional(bool)
      cache_ttl_in_seconds                       = optional(number)
      cache_data_encrypted                       = optional(bool)
      require_authorization_for_cache_control    = optional(bool)
      unauthorized_cache_control_header_strategy = optional(string)
    })
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Gateway Responses
# -----------------------------------------------------------------------------
variable "rest_api_gateway_responses" {
  description = "Map of REST API gateway responses"
  type = map(object({
    response_type       = string
    status_code         = optional(string)
    response_parameters = optional(map(string))
    response_templates  = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Documentation
# -----------------------------------------------------------------------------
variable "rest_api_documentation_parts" {
  description = "Map of REST API documentation parts"
  type = map(object({
    location = object({
      type        = string
      method      = optional(string)
      path        = optional(string)
      name        = optional(string)
      status_code = optional(string)
    })
    properties = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Usage Plans
# -----------------------------------------------------------------------------
variable "rest_api_usage_plans" {
  description = "Map of REST API usage plans"
  type = map(object({
    name        = string
    description = optional(string)
    api_stages = optional(list(object({
      stage = string
      throttle = optional(map(object({
        burst_limit = optional(number)
        rate_limit  = optional(number)
      })))
    })))
    quota_settings = optional(object({
      limit  = number
      offset = optional(number)
      period = string
    }))
    throttle_settings = optional(object({
      burst_limit = optional(number)
      rate_limit  = optional(number)
    }))
    tags = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Keys
# -----------------------------------------------------------------------------
variable "rest_api_keys" {
  description = "Map of REST API keys"
  type = map(object({
    name        = string
    description = optional(string)
    enabled     = optional(bool)
    value       = optional(string)
    tags        = optional(map(string))
  }))
  default = {}
}

variable "rest_api_usage_plan_keys" {
  description = "Map of REST API usage plan key associations"
  type = map(object({
    api_key_key    = string
    usage_plan_key = string
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API Domain Names
# -----------------------------------------------------------------------------
variable "rest_api_domain_names" {
  description = "Map of REST API custom domain names"
  type = map(object({
    domain_name              = string
    certificate_arn          = optional(string)
    certificate_name         = optional(string)
    certificate_body         = optional(string)
    certificate_chain        = optional(string)
    certificate_private_key  = optional(string)
    regional_certificate_arn = optional(string)
    security_policy          = optional(string)
    endpoint_configuration = optional(object({
      types = list(string)
    }))
    mutual_tls_authentication = optional(object({
      truststore_uri     = string
      truststore_version = optional(string)
    }))
    tags = optional(map(string))
  }))
  default = {}
}

variable "rest_api_base_path_mappings" {
  description = "Map of REST API base path mappings"
  type = map(object({
    stage_key  = string
    domain_key = string
    base_path  = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# REST API VPC Links
# -----------------------------------------------------------------------------
variable "rest_api_vpc_links" {
  description = "Map of REST API VPC links"
  type = map(object({
    name        = string
    description = optional(string)
    target_arns = list(string)
    tags        = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API Settings
# -----------------------------------------------------------------------------
variable "create_http_api" {
  description = "Whether to create an HTTP API"
  type        = bool
  default     = false
}

variable "http_api_name" {
  description = "Name of the HTTP API"
  type        = string
  default     = ""
}

variable "http_api_description" {
  description = "Description of the HTTP API"
  type        = string
  default     = null
}

variable "http_api_protocol_type" {
  description = "Protocol type (HTTP or WEBSOCKET)"
  type        = string
  default     = "HTTP"
  validation {
    condition     = can(regex("^(HTTP|WEBSOCKET)$", var.http_api_protocol_type))
    error_message = "Protocol type must be HTTP or WEBSOCKET."
  }
}

variable "http_api_version" {
  description = "Version identifier for the HTTP API"
  type        = string
  default     = null
}

variable "http_api_body" {
  description = "OpenAPI specification for the HTTP API"
  type        = string
  default     = null
}

variable "api_key_selection_expression" {
  description = "API key selection expression"
  type        = string
  default     = "$request.header.x-api-key"
}

variable "route_selection_expression" {
  description = "Route selection expression"
  type        = string
  default     = "$request.method $request.path"
}

variable "http_disable_execute_api_endpoint" {
  description = "Whether to disable the default execute-api endpoint for HTTP API"
  type        = bool
  default     = false
}

variable "http_api_cors_configuration" {
  description = "CORS configuration for the HTTP API"
  type = object({
    allow_credentials = optional(bool)
    allow_headers     = optional(list(string))
    allow_methods     = optional(list(string))
    allow_origins     = optional(list(string))
    expose_headers    = optional(list(string))
    max_age           = optional(number)
  })
  default = null
}

variable "http_api_tags" {
  description = "Additional tags for the HTTP API"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# HTTP API Authorizers
# -----------------------------------------------------------------------------
variable "http_api_authorizers" {
  description = "Map of HTTP API authorizers"
  type = map(object({
    authorizer_type                   = string
    name                              = string
    authorizer_uri                    = optional(string)
    authorizer_payload_format_version = optional(string)
    authorizer_result_ttl_in_seconds  = optional(number)
    authorizer_credentials_arn        = optional(string)
    identity_sources                  = optional(list(string))
    enable_simple_responses           = optional(bool)
    jwt_configuration = optional(object({
      audience = optional(list(string))
      issuer   = optional(string)
    }))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API Integrations
# -----------------------------------------------------------------------------
variable "http_api_integrations" {
  description = "Map of HTTP API integrations"
  type = map(object({
    integration_type              = string
    integration_uri               = optional(string)
    integration_method            = optional(string)
    connection_type               = optional(string)
    connection_id                 = optional(string)
    credentials_arn               = optional(string)
    description                   = optional(string)
    integration_subtype           = optional(string)
    passthrough_behavior          = optional(string)
    payload_format_version        = optional(string)
    request_parameters            = optional(map(string))
    request_templates             = optional(map(string))
    template_selection_expression = optional(string)
    timeout_milliseconds          = optional(number)
    response_parameters = optional(list(object({
      status_code = string
      mappings    = map(string)
    })))
    tls_config = optional(object({
      server_name_to_verify = optional(string)
    }))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API Routes
# -----------------------------------------------------------------------------
variable "http_api_routes" {
  description = "Map of HTTP API routes"
  type = map(object({
    route_key                  = string
    integration_key            = optional(string)
    target                     = optional(string)
    authorization_type         = optional(string)
    authorizer_key             = optional(string)
    authorizer_id              = optional(string)
    api_key_required           = optional(bool)
    authorization_scopes       = optional(list(string))
    model_selection_expression = optional(string)
    operation_name             = optional(string)
    request_models             = optional(map(string))
    request_parameters = optional(map(object({
      required = bool
    })))
    route_response_selection_expression = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API Stages
# -----------------------------------------------------------------------------
variable "http_api_stages" {
  description = "Map of HTTP API stages"
  type = map(object({
    name                  = string
    description           = optional(string)
    auto_deploy           = optional(bool)
    deployment_id         = optional(string)
    stage_variables       = optional(map(string))
    client_certificate_id = optional(string)
    access_log_settings = optional(object({
      destination_arn = string
      format          = string
    }))
    default_route_settings = optional(object({
      data_trace_enabled       = optional(bool)
      detailed_metrics_enabled = optional(bool)
      logging_level            = optional(string)
      throttling_burst_limit   = optional(number)
      throttling_rate_limit    = optional(number)
    }))
    route_settings = optional(list(object({
      route_key                = string
      data_trace_enabled       = optional(bool)
      detailed_metrics_enabled = optional(bool)
      logging_level            = optional(string)
      throttling_burst_limit   = optional(number)
      throttling_rate_limit    = optional(number)
    })))
    tags = optional(map(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API Domain Names
# -----------------------------------------------------------------------------
variable "http_api_domain_names" {
  description = "Map of HTTP API custom domain names"
  type = map(object({
    domain_name     = string
    certificate_arn = string
    endpoint_type   = optional(string)
    security_policy = optional(string)
    mutual_tls_authentication = optional(object({
      truststore_uri     = string
      truststore_version = optional(string)
    }))
    tags = optional(map(string))
  }))
  default = {}
}

variable "http_api_mappings" {
  description = "Map of HTTP API domain mappings"
  type = map(object({
    domain_key      = string
    stage_key       = string
    api_mapping_key = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# HTTP API VPC Links
# -----------------------------------------------------------------------------
variable "http_api_vpc_links" {
  description = "Map of HTTP API VPC links"
  type = map(object({
    name               = string
    security_group_ids = list(string)
    subnet_ids         = list(string)
    tags               = optional(map(string))
  }))
  default = {}
}
