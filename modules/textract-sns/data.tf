data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_iam_policy_document" "textract_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["textract.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.external_id]
    }
  }
}

data "aws_iam_policy_document" "textract_permissions" {
  statement {
    sid    = "S3ReadAccess"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetObjectVersion"
    ]

    resources = compact([
      local.s3_resources.input_bucket,
      local.s3_resources.input_objects
    ])
  }

  dynamic "statement" {
    for_each = var.output_bucket_arn != null ? [1] : []

    content {
      sid    = "S3WriteAccess"
      effect = "Allow"

      actions = [
        "s3:PutObject",
        "s3:PutObjectAcl",
        "s3:PutObjectVersionAcl"
      ]
      resources = compact([
        local.s3_resources.output_bucket,
        local.s3_resources.output_objects
      ])
    }
  }

  dynamic "statement" {
    for_each = var.enable_async_processing ? [1] : []

    content {
      sid    = "SNSPublishAccess"
      effect = "Allow"

      actions = [
        "sns:Publish"
      ]

      resources = [
        aws_sns_topic.textract_completion[0].arn,
        aws_sns_topic.textract_failure[0].arn
      ]
    }
  }

  dynamic "statement" {
    for_each = var.enable_async_processing && var.enable_sns_encryption ? [1] : []

    content {
      sid    = "KMSAccess"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey"
      ]

      resources = compact([
        var.kms_key_arn,
        var.s3_kms_key_arn
      ])
    }
  }

  dynamic "statement" {
    for_each = var.enable_textract_metrics ? [1] : []

    content {
      sid    = "CloudWatchMetrics"
      effect = "Allow"

      actions = [
        "cloudwatch:PutMetricData"
      ]

      resources = ["*"]

      condition {
        test     = "StringEquals"
        variable = "cloudwatch:namespace"
        values   = ["AWS/Textract", "Custom/Textract"]
      }
    }
  }
}
