# ============================================================================
# AWS Textract Module - Minimal Cost Usage Example
# ============================================================================
# This example demonstrates how to use the Textract module with minimal costs,
# optimized for development and testing within AWS Free Tier limits.
#
# 💰 COST OPTIMIZATION & FREE TIER RECOMMENDATIONS:
#
# AWS Textract Pricing (as of 2025):
# - First 1,000 pages/month: FREE (DetectDocumentText API)
# - After free tier: $1.50 per 1,000 pages (DetectDocumentText)
# - AnalyzeDocument: $50-65 per 1,000 pages (TABLES, FORMS features)
# 
# Free Tier Eligible Services Used:
# ✓ S3: 5 GB storage, 20,000 GET requests, 2,000 PUT requests (12 months)
# ✓ SNS: 1 million publishes, 100,000 HTTP deliveries, 1,000 email deliveries
# ✓ SQS: 1 million requests per month (always free)
# ✓ CloudWatch: 10 custom metrics, 10 alarms, 5GB log ingestion (always free)
# ✓ KMS: 20,000 free requests per month (always free)
# ✓ Lambda: 1M free requests, 400,000 GB-seconds compute (always free)
#
# 💡 COST OPTIMIZATION TIPS:
# 1. Use DetectDocumentText instead of AnalyzeDocument when possible (30x cheaper)
# 2. Set S3 lifecycle policies to transition old documents to Glacier
# 3. Use INTELLIGENT_TIERING for S3 storage class (included in this example)
# 4. Limit CloudWatch log retention (30 days recommended for dev)
# 5. Use email notifications sparingly (prefer SQS for automation)
# 6. Enable S3 request metrics only when needed (disabled by default)
# 7. Set appropriate alarm thresholds to avoid unnecessary notifications
# 8. Use reserved capacity for production (not applicable for free tier)
# 9. Process documents in batches to minimize API calls
# 10. Clean up failed/completed jobs regularly
#
# 📊 ESTIMATED MONTHLY COSTS (Dev Environment):
# - S3 Storage (10 GB): ~$0.23
# - Textract (100 pages/month): FREE (within 1,000 page limit)
# - SNS/SQS: FREE (within limits)
# - CloudWatch: FREE (basic monitoring)
# - KMS: FREE (within request limits)
# - Lambda: FREE (minimal usage)
# Total: ~$0.25/month for light development usage
#
# ⚠️  COST WARNINGS:
# - AnalyzeDocument with FORMS/TABLES is expensive ($50+ per 1,000 pages)
# - Keep documents under 5MB to avoid S3 multipart upload charges
# - Monitor CloudWatch Logs size - can grow quickly with verbose logging
# - SNS email subscriptions cost $2/month per 100,000 emails beyond free tier
#
# 🎯 THIS EXAMPLE CONFIGURATION:
# - Minimal features enabled for cost savings
# - Free tier optimized settings
# - Basic monitoring without premium features
# - Estimated cost: <$1/month for light usage
# ============================================================================

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

resource "aws_s3_bucket" "input" {
  bucket = "${local.name_prefix}-input-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.base_tags,
    {
      Name    = "${local.name_prefix}-input"
      Purpose = "textract-input"
    }
  )
}

resource "aws_s3_bucket_policy" "textract_access" {
  bucket = aws_s3_bucket.input.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTextractRead"
        Effect = "Allow"
        Principal = {
          AWS = module.textract.textract_role_arn
        }
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket" "output" {
  bucket = "${local.name_prefix}-output-${data.aws_caller_identity.current.account_id}"

  tags = merge(
    local.base_tags,
    {
      Name    = "${local.name_prefix}-output"
      Purpose = "textract-output"
    }
  )
}

resource "aws_s3_bucket_lifecycle_configuration" "input" {
  bucket = aws_s3_bucket.input.id

  rule {
    id     = "cleanup-old-documents"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = 365
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "output" {
  bucket = aws_s3_bucket.output.id

  rule {
    id     = "cleanup-old-results"
    status = "Enabled"

    expiration {
      days = 90
    }
  }
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket = aws_s3_bucket.input.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket = aws_s3_bucket.output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ============================================================================
# Lambda Function - Auto-trigger Textract Jobs
# ============================================================================

data "archive_file" "lambda_trigger" {
  type        = "zip"
  output_path = "${path.module}/lambda_trigger.zip"

  source {
    content  = <<-EOF
import json
import boto3
import os
import datetime
from urllib.parse import unquote_plus

textract = boto3.client('textract')

def handler(event, context):
    print(f"Received event: {json.dumps(event)}")
    
    role_arn = os.environ['TEXTRACT_ROLE_ARN']
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    output_bucket = os.environ['OUTPUT_BUCKET']
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        print(f"Processing: s3://{bucket}/{key}")
        
        try:
            # Start Textract Job
            response = textract.start_document_text_detection(
                DocumentLocation={
                    'S3Object': {'Bucket': bucket, 'Name': key}
                },
                NotificationChannel={
                    'SNSTopicArn': sns_topic_arn,
                    'RoleArn': role_arn
                },
                JobTag=f"auto-{key.split('/')[-1]}"
            )
            
            job_id = response['JobId']
            print(f"Started Textract job: {job_id}")
            
            # Metadata
            metadata = {
                'JobId': job_id,
                'SourceBucket': bucket,
                'SourceKey': key,
                'LambdaRequestId': context.aws_request_id,  # FIX 1: Correct Attribute
                'StartedAt': datetime.datetime.utcnow().isoformat(), # FIX 2: Correct Timestamp
                'Status': 'IN_PROGRESS'
            }
            
            s3 = boto3.client('s3')
            s3.put_object(
                Bucket=output_bucket,
                Key=f"jobs/{job_id}/metadata.json",
                Body=json.dumps(metadata, indent=2),
                ContentType='application/json'
            )
            
        except Exception as e:
            print(f"Error: {str(e)}")
            raise
    
    return {'statusCode': 200, 'body': 'Done'}
EOF
    filename = "index.py"
  }
}


resource "aws_iam_role" "lambda_trigger" {
  name = "${local.name_prefix}-lambda-trigger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = merge(
    local.base_tags,
    {
      Name = "${local.name_prefix}-lambda-trigger-role"
    }
  )
}

resource "aws_iam_role_policy" "lambda_trigger" {
  name = "${local.name_prefix}-lambda-trigger-policy"
  role = aws_iam_role.lambda_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:StartDocumentTextDetection",
          "textract:StartDocumentAnalysis",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.input.arn,
          "${aws_s3_bucket.input.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.output.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = module.textract.textract_role_arn
        Condition = {
          StringLike = {
            "iam:PassedToService" : "textract.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_trigger_basic" {
  role       = aws_iam_role.lambda_trigger.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "textract_trigger" {
  filename         = data.archive_file.lambda_trigger.output_path
  function_name    = "${local.name_prefix}-textract-trigger"
  role             = aws_iam_role.lambda_trigger.arn
  handler          = "index.handler"
  source_code_hash = data.archive_file.lambda_trigger.output_base64sha256
  runtime          = "python3.11"
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      TEXTRACT_ROLE_ARN = module.textract.textract_role_arn
      SNS_TOPIC_ARN     = module.textract.sns_topic_completion_arn
      OUTPUT_BUCKET     = aws_s3_bucket.output.id
    }
  }

  tags = merge(
    local.base_tags,
    {
      Name    = "${local.name_prefix}-textract-trigger"
      Purpose = "auto-start-textract-jobs"
    }
  )

  depends_on = [
    aws_iam_role_policy.lambda_trigger,
    aws_iam_role_policy_attachment.lambda_trigger_basic
  ]
}

resource "aws_s3_bucket_notification" "textract_trigger" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.textract_trigger.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ""
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.textract_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn
}

# ============================================================================
# Textract Module
# ============================================================================

module "textract" {
  source = "../../modules/textract-sns"

  project_name = local.project_name
  environment  = local.environment

  input_bucket_arn  = aws_s3_bucket.input.arn
  output_bucket_arn = aws_s3_bucket.output.arn

  allowed_document_types = ["pdf", "png", "jpg"]
  max_document_size_mb   = 5

  textract_features = []

  enable_async_processing = true

  enable_sns_encryption = false
  kms_key_arn           = null
  s3_kms_key_arn        = null

  external_id = "textract-dev"

  notification_email_endpoints = [
    "kovtun.ivan@proton.me",
  ]                                  # Email costs after 1,000/month
  notification_sqs_endpoints    = [] # SQS is always free (1M requests)
  notification_lambda_endpoints = [] # Lambda is free (1M requests)

  enable_sns_subscription_filter         = false
  sns_message_retention_seconds          = 345600
  enable_sns_content_based_deduplication = false

  enable_dead_letter_queue = false

  enable_cloudwatch_logs = true
  log_retention_days     = 7
  enable_log_encryption  = false

  enable_cloudwatch_alarms  = true
  alarm_actions             = []
  alarm_evaluation_periods  = 2
  alarm_period              = 300
  error_threshold           = 50
  throttle_threshold        = 10
  alarm_datapoints_to_alarm = 2

  enable_textract_metrics    = false
  enable_enhanced_monitoring = false
  metrics_namespace          = "Custom/Textract"

  iam_permissions_boundary_arn = null

  enable_cross_account_access = false
  trusted_account_ids         = []

  tags = local.base_tags
}

# ============================================================================
# Outputs
# ============================================================================

output "textract_role_arn" {
  description = "ARN of the Textract IAM role"
  value       = module.textract.textract_role_arn
}

output "sns_topic_completion_arn" {
  description = "ARN of the SNS topic for job completion"
  value       = module.textract.sns_topic_completion_arn
}

output "sns_topic_failure_arn" {
  description = "ARN of the SNS topic for job failures"
  value       = module.textract.sns_topic_failure_arn
}

output "input_bucket_name" {
  description = "Name of the input S3 bucket"
  value       = aws_s3_bucket.input.id
}

output "output_bucket_name" {
  description = "Name of the output S3 bucket"
  value       = aws_s3_bucket.output.id
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function that triggers Textract jobs"
  value       = aws_lambda_function.textract_trigger.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function that triggers Textract jobs"
  value       = aws_lambda_function.textract_trigger.function_name
}

output "deployment_summary" {
  description = "Summary of the deployment configuration"
  value = {
    estimated_monthly_cost = "~$0.25 USD (within free tier for <1000 pages/month)"
    free_tier_eligible     = true
    textract_api_used      = "DetectDocumentText (cheapest)"
    features_enabled       = length(module.textract.module_config.textract_features) > 0 ? module.textract.module_config.textract_features : ["TEXT_DETECTION_ONLY"]
    storage_lifecycle      = "30d Standard -> 90d Glacier -> 365d Delete"
    monitoring_level       = "Basic (CloudWatch Logs only)"
    encryption_level       = "AWS Managed (no KMS costs)"
    auto_trigger_enabled   = true
    upload_prefix          = "documents/"
  }
}



output "usage_instructions" {
  description = "Instructions for using the auto-trigger feature"
  value       = <<-EOT
  
  🚀 AUTO-TRIGGER SETUP COMPLETE!
  
  To process documents automatically:
  
  1. Upload a PDF to the input bucket with 'documents/' prefix:
     aws s3 cp your-file.pdf s3://${aws_s3_bucket.input.id}/documents/your-file.pdf
  
  2. Lambda will automatically:
     - Detect the upload
     - Start a Textract job
     - Send you an email when complete
  
  3. Check job metadata:
     aws s3 ls s3://${aws_s3_bucket.output.id}/jobs/
  
  4. View Lambda logs:
     aws logs tail /aws/lambda/${aws_lambda_function.textract_trigger.function_name} --follow
  
  Supported file types: PDF, PNG, JPG, JPEG, TIFF
  Max file size: 500MB
  
  EOT
}
