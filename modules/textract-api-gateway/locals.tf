locals {
  region_codes = {
    "us-east-1"      = "use1"
    "us-east-2"      = "use2"
    "us-west-1"      = "usw1"
    "us-west-2"      = "usw2"
    "eu-west-1"      = "euw1"
    "eu-west-2"      = "euw2"
    "eu-west-3"      = "euw3"
    "eu-central-1"   = "euc1"
    "eu-north-1"     = "eun1"
    "ap-south-1"     = "aps1"
    "ap-northeast-1" = "apne1"
    "ap-northeast-2" = "apne2"
    "ap-northeast-3" = "apne3"
    "ap-southeast-1" = "apse1"
    "ap-southeast-2" = "apse2"
    "ca-central-1"   = "cac1"
    "sa-east-1"      = "sae1"
  }

  region_code = lookup(local.region_codes, data.aws_region.current.name, data.aws_region.current.name)

  account_id_short = substr(data.aws_caller_identity.current.account_id, -4, 4)

  input_bucket_name  = split(":", var.input_bucket_arn)[5]
  output_bucket_name = var.output_bucket_arn != null ? split(":", var.output_bucket_arn)[5] : local.input_bucket_name

  name_prefix       = "${var.project_name}-${var.environment}-${local.region_code}-${local.account_id_short}"
  name_prefix_short = "${var.project_name}-${var.environment}-${local.region_code}"

  api_name = coalesce(var.api_name, "${local.name_prefix_short}-textract-api")

  textract_features_joined = join(",", var.textract_features)

  common_tags = merge(
    var.tags,
    {
      Module      = "textract-api-gateway"
      Service     = "textract"
      Environment = var.environment
      Region      = data.aws_region.current.name
      RegionCode  = local.region_code
      AccountId   = data.aws_caller_identity.current.account_id
      ManagedBy   = "Terraform"
      DeployedAt  = timestamp()
      Project     = var.project_name
    }
  )

  #   endpoint_config = var.endpoint_configuration.vpc_endpoint_ids != [] ? {
  #     type             = "PRIVATE"
  #     vpc_endpoint_ids = var.endpoint_configuration.vpc_endpoint_ids
  #     } : {
  #     type = var.endpoint_configuration.type
  #   }

  api_routes = {
    "POST /analyze" = {
      description     = "Analyze document synchronously"
      operation_name  = "AnalyzeDocument"
      integration_uri = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/AnalyzeDocument"
      enabled         = var.enable_sync_operations
      request_parameters = {
        "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
        "integration.request.header.X-Amz-Target" = "'Textract.AnalyzeDocument'"
      }
      request_templates = {
        "application/json" = jsonencode({
          Document = {
            S3Object = {
              Bucket = local.input_bucket_name
              Name   = "$input.path('$.s3_key')"
            }
          }
          FeatureTypes = var.textract_features
          QueriesConfig = length(var.textract_queries) > 0 ? {
            Queries = var.textract_queries
          } : null
        })
      }
    },

    "POST /detect-text" = {
      description     = "Detect document text synchronously"
      integration_uri = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/DetectDocumentText"
      enabled         = var.enable_sync_operations
      request_parameters = {
        "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
        "integration.request.header.X-Amz-Target" = "'Textract.DetectDocumentText'"
      }
      request_templates = {
        "application/json" = jsonencode({
          Document = {
            S3Object = {
              Bucket = local.input_bucket_name
              Name   = "$input.path('$.s3_key')"
            }
          }
        })
      }
    },

    "POST /async/analyze" = {
      description     = "Start asynchronous document analysis"
      operation_name  = "StartDocumentAnalysis"
      integration_uri = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/StartDocumentAnalysis"
      enabled         = var.enable_async_operations
      request_parameters = {
        "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
        "integration.request.header.X-Amz-Target" = "'Textract.StartDocumentAnalysis'" # ADD THIS
      }
      request_templates = {
        "application/json" = jsonencode({
          DocumentLocation = {
            S3Object = {
              Bucket = local.input_bucket_name
              Name   = "$input.path('$.s3_key')"
            }
          }
          FeatureTypes = var.textract_features
          OutputConfig = {
            S3Bucket = local.output_bucket_name
            S3Prefix = "results/"
          }
          NotificationChannel = var.async_notification_topic_arn != "" ? {
            SNSTopicArn = var.async_notification_topic_arn
            RoleArn     = var.textract_role_arn
          } : null
          QueriesConfig = length(var.textract_queries) > 0 ? {
            Queries = var.textract_queries
          } : null
        })
      }
    },

    "POST /async/detect-text" = {
      description     = "Start asynchronous text detection"
      operation_name  = "StartDocumentTextDetection"
      integration_uri = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/StartDocumentTextDetection"
      enabled         = var.enable_async_operations
      request_parameters = {
        "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
        "integration.request.header.X-Amz-Target" = "'Textract.StartDocumentTextDetection'"
      }
      request_templates = {
        "application/json" = jsonencode({
          DocumentLocation = {
            S3Object = {
              Bucket = local.input_bucket_name
              Name   = "$input.path('$.s3_key')"
            }
          }
          OutputConfig = {
            S3Bucket = local.output_bucket_name
            S3Prefix = "text-detection-results/"
          }
          NotificationChannel = var.async_notification_topic_arn != "" ? {
            SNSTopicArn = var.async_notification_topic_arn
            RoleArn     = var.textract_role_arn
          } : null
        })
      }
    },

    "GET /job/{jobId}" = {
      description     = "Get Textract job result"
      operation_name  = "GetDocumentAnalysis"
      integration_uri = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/GetDocumentAnalysis"
      enabled         = var.enable_async_operations
      request_parameters = {
        "integration.request.header.Content-Type" = "'application/x-amz-json-1.1'"
        "integration.request.header.X-Amz-Target" = "'Textract.GetDocumentAnalysis'"
        "integration.request.path.jobId"          = "method.request.path.jobId"
      }
      request_templates = {
        "application/json" = jsonencode({
          JobId = "$input.params('jobId')"
        })
      }
    },

    "GET /health" = {
      description          = "API health check"
      operation_name       = "HealthCheck"
      integration_uri      = "arn:aws:apigateway:${data.aws_region.current.name}:textract:action/GetDocumentAnalysis"
      enabled              = true
      passthrough_behavior = "WHEN_NO_MATCH"
      request_templates = {
        "application/json" = jsonencode({
          JobId = "dummy"
        })
      }
      integration_responses = [
        {
          status_code = 200
          response_templates = {
            "application/json" = jsonencode({
              status    = "healthy"
              timestamp = "$context.requestTime"
              service   = "textract-api"
            })
          }
        }
      ]
    }
  }

  enabled_routes = { for k, v in local.api_routes : k => v if v.enabled }

  has_custom_domain = var.custom_domain != null && var.custom_domain.domain_name != ""
}
