# ============================================================================
# Local Values
# ============================================================================

locals {
  topic_name = var.fifo_topic && !strcontains(var.name, ".fifo") ? "${var.name}.fifo" : var.name

  common_tags = merge(
    var.tags,
    {
      Name = local.topic_name
    }
  )
}

# ============================================================================
# SNS Topic
# ============================================================================

resource "aws_sns_topic" "this" {
  name         = local.topic_name
  display_name = var.display_name

  # FIFO topic configuration
  fifo_topic                  = var.fifo_topic
  content_based_deduplication = var.fifo_topic ? var.content_based_deduplication : null

  # Message delivery configuration
  delivery_policy = var.delivery_policy

  # Encryption configuration
  kms_master_key_id = var.kms_master_key_id

  # Delivery status logging - HTTP/HTTPS
  http_success_feedback_role_arn    = var.http_success_feedback_role_arn
  http_success_feedback_sample_rate = var.http_success_feedback_sample_rate
  http_failure_feedback_role_arn    = var.http_failure_feedback_role_arn

  # Delivery status logging - Lambda
  lambda_success_feedback_role_arn    = var.lambda_success_feedback_role_arn
  lambda_success_feedback_sample_rate = var.lambda_success_feedback_sample_rate
  lambda_failure_feedback_role_arn    = var.lambda_failure_feedback_role_arn

  # Delivery status logging - SQS
  sqs_success_feedback_role_arn    = var.sqs_success_feedback_role_arn
  sqs_success_feedback_sample_rate = var.sqs_success_feedback_sample_rate
  sqs_failure_feedback_role_arn    = var.sqs_failure_feedback_role_arn

  # Delivery status logging - Firehose
  firehose_success_feedback_role_arn    = var.firehose_success_feedback_role_arn
  firehose_success_feedback_sample_rate = var.firehose_success_feedback_sample_rate
  firehose_failure_feedback_role_arn    = var.firehose_failure_feedback_role_arn

  # Delivery status logging - Application (Mobile Push)
  application_success_feedback_role_arn    = var.application_success_feedback_role_arn
  application_success_feedback_sample_rate = var.application_success_feedback_sample_rate
  application_failure_feedback_role_arn    = var.application_failure_feedback_role_arn

  # Data protection and tracing
  signature_version = var.signature_version
  tracing_config    = var.tracing_config

  tags = local.common_tags
}

# ============================================================================
# SNS Topic Policy
# ============================================================================

resource "aws_sns_topic_policy" "this" {
  count  = var.topic_policy != null ? 1 : 0
  arn    = aws_sns_topic.this.arn
  policy = var.topic_policy
}

# ============================================================================
# SNS Topic Subscriptions
# ============================================================================

# ============================================================================
# Message Templates (Optional)
# ============================================================================

resource "aws_sns_topic_subscription" "this" {
  count = length(var.subscriptions)

  topic_arn              = aws_sns_topic.this.arn
  protocol               = var.subscriptions[count.index].protocol
  endpoint               = var.subscriptions[count.index].endpoint
  endpoint_auto_confirms = var.subscriptions[count.index].endpoint_auto_confirms
  raw_message_delivery   = var.subscriptions[count.index].raw_message_delivery
  filter_policy          = var.subscriptions[count.index].filter_policy
  filter_policy_scope    = var.subscriptions[count.index].filter_policy != null ? var.subscriptions[count.index].filter_policy_scope : null
  delivery_policy        = var.subscriptions[count.index].delivery_policy
  redrive_policy         = var.subscriptions[count.index].redrive_policy
  subscription_role_arn  = var.subscriptions[count.index].subscription_role_arn
}
