resource "aws_sns_topic" "textract_completion" {
  count = var.enable_async_processing ? 1 : 0

  name              = local.sns_topics.completion
  display_name      = local.resource_names.sns_completion_display
  kms_master_key_id = var.enable_sns_encryption ? var.kms_key_arn : null

  fifo_topic                  = var.enable_sns_content_based_deduplication
  content_based_deduplication = var.enable_sns_content_based_deduplication

  tags = merge(
    local.common_tags,
    {
      Name             = local.sns_topics.completion
      Type             = "completion"
      Purpose          = "Textract asynchronous job completion notifications"
      NotificationType = "success"
    }
  )
}

resource "aws_sns_topic" "textract_failure" {
  count = var.enable_async_processing ? 1 : 0

  name              = local.sns_topics.failure
  display_name      = local.resource_names.sns_failure_display
  kms_master_key_id = var.enable_sns_encryption ? var.kms_key_arn : null

  fifo_topic                  = var.enable_sns_content_based_deduplication
  content_based_deduplication = var.enable_sns_content_based_deduplication

  tags = merge(
    local.common_tags,
    {
      Name             = local.sns_topics.failure
      Type             = "failure"
      Purpose          = "Textract asynchronous job failure notifications"
      NotificationType = "error"
    }
  )
}


# ============================================================================
# Dead Letter Queue for SNS
# ============================================================================

resource "aws_sqs_queue" "sns_dlq" {
  count = var.enable_async_processing && var.enable_dead_letter_queue ? 1 : 0

  name                      = "${local.name_prefix}-textract-sns-dlq"
  message_retention_seconds = var.sns_message_retention_seconds
  kms_master_key_id         = var.enable_sns_encryption ? var.kms_key_arn : null

  tags = merge(
    local.common_tags,
    {
      Name    = "${local.name_prefix}-textract-sns-dlq"
      Purpose = "Dead letter queue for failed SNS deliveries"
    }
  )
}

# ============================================================================
# SNS Subscriptions - Email
# ============================================================================

resource "aws_sns_topic_subscription" "email_completion" {
  count = var.enable_async_processing ? length(var.notification_email_endpoints) : 0

  topic_arn = aws_sns_topic.textract_completion[0].arn
  protocol  = "email"
  endpoint  = var.notification_email_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

resource "aws_sns_topic_subscription" "email_failure" {
  count = var.enable_async_processing ? length(var.notification_email_endpoints) : 0

  topic_arn = aws_sns_topic.textract_failure[0].arn
  protocol  = "email"
  endpoint  = var.notification_email_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

# ============================================================================
# SNS Subscriptions - SQS
# ============================================================================

resource "aws_sns_topic_subscription" "sqs_completion" {
  count = var.enable_async_processing ? length(var.notification_sqs_endpoints) : 0

  topic_arn = aws_sns_topic.textract_completion[0].arn
  protocol  = "sqs"
  endpoint  = var.notification_sqs_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

resource "aws_sns_topic_subscription" "sqs_failure" {
  count = var.enable_async_processing ? length(var.notification_sqs_endpoints) : 0

  topic_arn = aws_sns_topic.textract_failure[0].arn
  protocol  = "sqs"
  endpoint  = var.notification_sqs_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

# ============================================================================
# SNS Subscriptions - Lambda
# ============================================================================

resource "aws_sns_topic_subscription" "lambda_completion" {
  count = var.enable_async_processing ? length(var.notification_lambda_endpoints) : 0

  topic_arn = aws_sns_topic.textract_completion[0].arn
  protocol  = "lambda"
  endpoint  = var.notification_lambda_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

resource "aws_sns_topic_subscription" "lambda_failure" {
  count = var.enable_async_processing ? length(var.notification_lambda_endpoints) : 0

  topic_arn = aws_sns_topic.textract_failure[0].arn
  protocol  = "lambda"
  endpoint  = var.notification_lambda_endpoints[count.index]

  filter_policy = var.enable_sns_subscription_filter ? var.sns_filter_policy : null

  redrive_policy = var.enable_dead_letter_queue ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.sns_dlq[0].arn
  }) : null
}

# ============================================================================
# SNS Topic Policies
# ============================================================================

data "aws_iam_policy_document" "sns_topic_policy_completion" {
  count = var.enable_async_processing ? 1 : 0

  statement {
    sid    = "AllowTextractPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["textract.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.textract_completion[0].arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  dynamic "statement" {
    for_each = length(var.sns_subscriber_principals) > 0 ? [1] : []

    content {
      sid    = "AllowSubscription"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.sns_subscriber_principals
      }

      actions = [
        "SNS:Subscribe",
        "SNS:Receive"
      ]

      resources = [
        aws_sns_topic.textract_completion[0].arn
      ]
    }
  }
}

data "aws_iam_policy_document" "sns_topic_policy_failure" {
  count = var.enable_async_processing ? 1 : 0

  statement {
    sid    = "AllowTextractPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["textract.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.textract_failure[0].arn
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  dynamic "statement" {
    for_each = length(var.sns_subscriber_principals) > 0 ? [1] : []

    content {
      sid    = "AllowSubscription"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.sns_subscriber_principals
      }

      actions = [
        "SNS:Subscribe",
        "SNS:Receive"
      ]

      resources = [
        aws_sns_topic.textract_failure[0].arn
      ]
    }
  }
}

resource "aws_sns_topic_policy" "textract_completion" {
  count = var.enable_async_processing ? 1 : 0

  arn    = aws_sns_topic.textract_completion[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy_completion[0].json
}

resource "aws_sns_topic_policy" "textract_failure" {
  count = var.enable_async_processing ? 1 : 0

  arn    = aws_sns_topic.textract_failure[0].arn
  policy = data.aws_iam_policy_document.sns_topic_policy_failure[0].json
}
