variable "project_name" {
  description = "Name of the project"
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9-]{1,30}$", var.project_name))
    error_message = "Project name must be 2-31 characters, start with letter, contain only letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name (dev, staging, prod, etc.)"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "textract_role_arn" {
  description = "ARN of the IAM role for Textract to access S3 buckets"
  type        = string
}

variable "input_bucket_arn" {
  description = "ARN of the S3 bucket for input documents"
  type        = string
}

variable "output_bucket_arn" {
  description = "ARN of the S3 bucket for Textract output results"
  type        = string
  default     = null
}

variable "textract_features" {
  description = "Textract features to enable (FORMS, TABLES, QUERIES, SIGNATURES, LAYOUT)"
  type        = list(string)
  default     = []
}

variable "textract_queries" {
  description = "List of queries for Textract AnalyzeDocument QUERIES feature"
  type = list(object({
    text  = string
    alias = string
    pages = list(string)
  }))
  default = []
}

# API Gateway Configuration

variable "api_name" {
  description = "Name of the Textract API Gateway"
  type        = string
  default     = ""
}

variable "api_description" {
  description = "Description of the Textract API Gateway"
  type        = string
  default     = "Textract Document Processing API"
}

variable "enable_async_operations" {
  description = "Enable asynchronous Textract operations (StartDocumentAnalysis, StartDocumentTextDetection)"
  type        = bool
  default     = true
}

variable "enable_sync_operations" {
  description = "Enable synchronous Textract operations (AnalyzeDocument, DetectDocumentText)"
  type        = bool
  default     = true
}

variable "async_notification_topic_arn" {
  description = "ARN of SNS topic for async operation notifications (optional)"
  type        = string
  default     = ""
}

variable "endpoint_configuration" {
  description = "API Gateway endpoint configuration"
  type = object({
    type             = string
    vpc_endpoint_ids = list(string)
  })
  default = {
    type             = "REGIONAL"
    vpc_endpoint_ids = []
  }
}

variable "enable_api_key" {
  description = "Enable API key authentication"
  type        = bool
  default     = true
}

variable "api_key_name" {
  description = "Name for the API key (if enabled)"
  type        = string
  default     = ""
}

variable "enable_cognito_authorizer" {
  description = "Enable Cognito user pool authorizer"
  type        = bool
  default     = false
}

variable "cognito_user_pool_arn" {
  description = "ARN of Cognito User Pool for authorization"
  type        = string
  default     = ""
}

variable "cognito_user_pool_client_ids" {
  description = "List of Cognito User Pool Client IDs"
  type        = list(string)
  default     = []
}

variable "allowed_ips" {
  description = "List of allowed IPs for resource policy (CIDR format)"
  type        = list(string)
  default     = []
}

variable "enable_waf" {
  description = "Enable WAF Web ACL"
  type        = bool
  default     = true
}

variable "waf_arn" {
  description = "ARN of WAF Web ACL to associate (if not provided, creates basic WAF)"
  type        = string
  default     = ""
}

variable "cors_configuration" {
  description = "CORS configuration for the API"
  type = object({
    allow_origins     = list(string)
    allow_methods     = list(string)
    allow_headers     = list(string)
    expose_headers    = list(string)
    max_age_seconds   = number
    allow_credentials = bool
  })
  default = {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization", "X-Api-Key"]
    expose_headers    = ["x-amzn-RequestId", "x-amzn-ErrorType"]
    max_age_seconds   = 3600
    allow_credentials = false
  }
}

variable "throttling_configuration" {
  description = "API throttling configuration"
  type = object({
    burst_limit = number
    rate_limit  = number
  })
  default = {
    burst_limit = 100
    rate_limit  = 200
  }
}

variable "logging_configuration" {
  description = "Logging configuration for API Gateway"
  type = object({
    enabled                 = bool
    log_format              = string
    log_group_retention     = number
    execution_logging_level = string
    log_full_response_data  = bool
  })
  default = {
    enabled                 = true
    log_format              = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.routeKey $context.protocol\" $context.status $context.responseLength $context.requestId $context.integrationErrorMessage"
    log_group_retention     = 30
    execution_logging_level = "INFO"
    log_full_response_data  = false
  }
}

variable "custom_domain" {
  description = "Custom domain configuration"
  type = object({
    domain_name       = string
    certificate_arn   = string
    hosted_zone_id    = string
    create_dns_record = bool
    security_policy   = string
  })
  default = null
}

variable "usage_plans" {
  description = "Map of usage plans for API keys"
  type = map(object({
    description  = string
    burst_limit  = number
    rate_limit   = number
    quota_limit  = number
    quota_period = string
  }))
  default = {
    default = {
      description  = "Default usage plan"
      burst_limit  = 100
      rate_limit   = 200
      quota_limit  = 10000
      quota_period = "MONTH"
    }
  }
}

variable "enable_lambda_integration" {
  description = "Enable Lambda integration for preprocessing/postprocessing"
  type        = bool
  default     = false
}

variable "preprocess_lambda_arn" {
  description = "ARN of Lambda function for preprocessing documents"
  type        = string
  default     = ""
}

variable "postprocess_lambda_arn" {
  description = "ARN of Lambda function for postprocessing Textract results"
  type        = string
  default     = ""
}
