terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "document-processing"
      Environment = "dev"
      ManagedBy   = "Terraform"
      CostCenter  = "development"
    }
  }
}

# ============================================================================
# Data Sources
# ============================================================================

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  name_prefix  = "textract-dev"
  project_name = "doc-processor"
  environment  = "dev"

  base_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# S3 Buckets
# ============================================================================

resource "aws_s3_bucket" "input_bucket" {
  bucket = "${local.name_prefix}-input-docs"
  tags   = merge(local.base_tags, { Name = "${local.name_prefix}-input-docs" })
}

resource "aws_s3_bucket" "output_bucket" {
  bucket = "${local.name_prefix}-textract-results"
  tags   = merge(local.base_tags, { Name = "${local.name_prefix}-textract-results" })
}

resource "aws_iam_role" "textract_role" {
  name = "${local.name_prefix}-textract-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
      }
    ]
  })
  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "textract_s3_access" {
  role       = aws_iam_role.textract_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}


resource "aws_s3_bucket_policy" "input_bucket_policy" {
  bucket = aws_s3_bucket.input_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input_bucket.arn,
          "${aws_s3_bucket.input_bucket.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn"     = "arn:aws:textract:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}

resource "aws_s3_bucket_policy" "output_bucket_policy" {
  bucket = aws_s3_bucket.output_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "textract.amazonaws.com"
        }
        Action = [
          "s3:PutObject"
        ]
        Resource = [
          "${aws_s3_bucket.output_bucket.arn}/*"
        ]
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
            "aws:SourceArn"     = "arn:aws:textract:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
}



module "textract_api_gateway" {
  source = "../../modules/textract-api-gateway"

  project_name = local.project_name
  environment  = local.environment
  tags         = local.base_tags

  textract_role_arn = aws_iam_role.textract_role.arn
  input_bucket_arn  = aws_s3_bucket.input_bucket.arn
  output_bucket_arn = aws_s3_bucket.output_bucket.arn


  textract_features = [] # Only free tier features

  textract_queries = [] # Queries have additional cost

  api_name        = "${local.name_prefix}-api"
  api_description = "Cost-optimized Textract API (Free Tier Friendly)"

  enable_async_operations = false # Async operations have SNS + per-page costs
  enable_sync_operations  = true  # Sync operations have free tier

  enable_api_key = false

  enable_waf = false

  custom_domain = null

  allowed_ips = ["0.0.0.0/0"]

  cors_configuration = {
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "OPTIONS"]
    allow_headers     = ["Content-Type", "Authorization"]
    expose_headers    = []
    max_age_seconds   = 300
    allow_credentials = false
  }

  throttling_configuration = {
    burst_limit = 10
    rate_limit  = 20
  }

  logging_configuration = {
    enabled                 = true
    log_format              = "$context.identity.sourceIp - - [$context.requestTime] \"$context.httpMethod $context.resourcePath $context.protocol\" $context.status $context.responseLength $context.requestId"
    log_group_retention     = 7
    execution_logging_level = "INFO"
    log_full_response_data  = false
  }

  endpoint_configuration = {
    type             = "REGIONAL"
    vpc_endpoint_ids = []
  }
}
