# IAM Role for API Gateway to invoke Textract
resource "aws_iam_role" "api_gateway_textract" {
  name = "${local.name_prefix}-api-gateway-textract-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  tags = local.common_tags
}

# IAM Policy for API Gateway to invoke Textract
resource "aws_iam_role_policy" "api_gateway_textract_policy" {
  name = "${local.name_prefix}-api-gateway-textract-policy"
  role = aws_iam_role.api_gateway_textract.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "textract:AnalyzeDocument",
          "textract:DetectDocumentText",
          "textract:StartDocumentAnalysis",
          "textract:StartDocumentTextDetection",
          "textract:GetDocumentAnalysis",
          "textract:GetDocumentTextDetection"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = [
          "${var.input_bucket_arn}/*",
          var.output_bucket_arn != null ? "${var.output_bucket_arn}/*" : "${var.input_bucket_arn}/*"
        ]
      }
    ]
  })
}

# CloudWatch Logs Role for API Gateway
resource "aws_iam_role" "cloudwatch_logs" {
  count = var.logging_configuration.enabled ? 1 : 0

  name = "${local.name_prefix}-api-gateway-cloudwatch-logs"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "apigateway.amazonaws.com"
        }
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "cloudwatch_logs" {
  count = var.logging_configuration.enabled ? 1 : 0

  role       = aws_iam_role.cloudwatch_logs[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

# KMS Key for CloudWatch Logs Encryption (Optional)
resource "aws_kms_key" "logs_key" {
  count = var.logging_configuration.enabled ? 1 : 0

  description             = "KMS key for API Gateway CloudWatch Logs encryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Effect = "Allow"
        Principal = {
          Service = "logs.${data.aws_region.current.name}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt*",
          "kms:Decrypt*",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*",
          "kms:Describe*"
        ]
        Resource = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"
          }
        }
      }
    ]
  })
  tags = local.common_tags
}

resource "aws_kms_alias" "logs_key_alias" {
  count = var.logging_configuration.enabled ? 1 : 0

  name          = "alias/${local.name_prefix}-api-gateway-logs-key"
  target_key_id = aws_kms_key.logs_key[0].key_id
}
