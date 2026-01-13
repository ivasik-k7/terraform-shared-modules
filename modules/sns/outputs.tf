# ============================================================================
# Topic - Identity
# ============================================================================

output "topic_id" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.this.id
}

output "topic_arn" {
  description = "The ARN of the SNS topic"
  value       = aws_sns_topic.this.arn
}

output "topic_name" {
  description = "The name of the SNS topic"
  value       = aws_sns_topic.this.name
}

output "topic_display_name" {
  description = "The display name of the SNS topic"
  value       = aws_sns_topic.this.display_name
}

output "topic_owner" {
  description = "The AWS Account ID of the SNS topic owner"
  value       = aws_sns_topic.this.owner
}

# ============================================================================
# Topic - Configuration Details
# ============================================================================

output "fifo_topic" {
  description = "Whether the topic is a FIFO topic"
  value       = aws_sns_topic.this.fifo_topic
}

output "content_based_deduplication" {
  description = "Whether content-based deduplication is enabled (FIFO topics only)"
  value       = aws_sns_topic.this.content_based_deduplication
}

output "delivery_policy" {
  description = "The delivery policy configured for the topic"
  value       = aws_sns_topic.this.delivery_policy
}

output "signature_version" {
  description = "The signature version configured for the topic"
  value       = aws_sns_topic.this.signature_version
}

output "tracing_config" {
  description = "The tracing configuration for the topic"
  value       = aws_sns_topic.this.tracing_config
}

# ============================================================================
# Topic - Encryption
# ============================================================================

output "kms_master_key_id" {
  description = "The KMS master key ID used for encryption, if any"
  value       = aws_sns_topic.this.kms_master_key_id
}

# ============================================================================
# Topic - Delivery Status Logging
# ============================================================================

output "http_success_feedback_role_arn" {
  description = "The IAM role ARN for HTTP success feedback"
  value       = aws_sns_topic.this.http_success_feedback_role_arn
}

output "http_success_feedback_sample_rate" {
  description = "The sample rate for HTTP success feedback"
  value       = aws_sns_topic.this.http_success_feedback_sample_rate
}

output "http_failure_feedback_role_arn" {
  description = "The IAM role ARN for HTTP failure feedback"
  value       = aws_sns_topic.this.http_failure_feedback_role_arn
}

output "lambda_success_feedback_role_arn" {
  description = "The IAM role ARN for Lambda success feedback"
  value       = aws_sns_topic.this.lambda_success_feedback_role_arn
}

output "lambda_success_feedback_sample_rate" {
  description = "The sample rate for Lambda success feedback"
  value       = aws_sns_topic.this.lambda_success_feedback_sample_rate
}

output "lambda_failure_feedback_role_arn" {
  description = "The IAM role ARN for Lambda failure feedback"
  value       = aws_sns_topic.this.lambda_failure_feedback_role_arn
}

output "sqs_success_feedback_role_arn" {
  description = "The IAM role ARN for SQS success feedback"
  value       = aws_sns_topic.this.sqs_success_feedback_role_arn
}

output "sqs_success_feedback_sample_rate" {
  description = "The sample rate for SQS success feedback"
  value       = aws_sns_topic.this.sqs_success_feedback_sample_rate
}

output "sqs_failure_feedback_role_arn" {
  description = "The IAM role ARN for SQS failure feedback"
  value       = aws_sns_topic.this.sqs_failure_feedback_role_arn
}

output "firehose_success_feedback_role_arn" {
  description = "The IAM role ARN for Firehose success feedback"
  value       = aws_sns_topic.this.firehose_success_feedback_role_arn
}

output "firehose_success_feedback_sample_rate" {
  description = "The sample rate for Firehose success feedback"
  value       = aws_sns_topic.this.firehose_success_feedback_sample_rate
}

output "firehose_failure_feedback_role_arn" {
  description = "The IAM role ARN for Firehose failure feedback"
  value       = aws_sns_topic.this.firehose_failure_feedback_role_arn
}

output "application_success_feedback_role_arn" {
  description = "The IAM role ARN for application success feedback"
  value       = aws_sns_topic.this.application_success_feedback_role_arn
}

output "application_success_feedback_sample_rate" {
  description = "The sample rate for application success feedback"
  value       = aws_sns_topic.this.application_success_feedback_sample_rate
}

output "application_failure_feedback_role_arn" {
  description = "The IAM role ARN for application failure feedback"
  value       = aws_sns_topic.this.application_failure_feedback_role_arn
}

# ============================================================================
# Topic Policy
# ============================================================================

output "topic_policy_applied" {
  description = "Whether a topic policy was applied"
  value       = var.topic_policy != null
}

# ============================================================================
# Subscriptions
# ============================================================================

output "subscription_arns" {
  description = "List of ARNs of the topic subscriptions"
  value       = aws_sns_topic_subscription.this[*].arn
}

output "subscription_count" {
  description = "Number of subscriptions created for the topic"
  value       = length(aws_sns_topic_subscription.this)
}

output "subscriptions" {
  description = "List of subscription details"
  value = [
    for i, sub in aws_sns_topic_subscription.this : {
      arn                            = sub.arn
      protocol                       = sub.protocol
      endpoint                       = sub.endpoint
      confirmation_was_authenticated = sub.confirmation_was_authenticated
      owner_id                       = sub.owner_id
      pending_confirmation           = sub.pending_confirmation
    }
  ]
}

# ============================================================================
# Combined Outputs for Integration
# ============================================================================

output "topic_info" {
  description = "Comprehensive topic information for integration with other services"
  value = {
    id           = aws_sns_topic.this.id
    arn          = aws_sns_topic.this.arn
    name         = aws_sns_topic.this.name
    display_name = aws_sns_topic.this.display_name
    fifo         = aws_sns_topic.this.fifo_topic
    encrypted    = aws_sns_topic.this.kms_master_key_id != null
    owner        = aws_sns_topic.this.owner
  }
}

# ============================================================================
# Lambda/Application Integration
# ============================================================================

output "topic_arn_for_policy" {
  description = "The topic ARN formatted for use in IAM policies"
  value       = aws_sns_topic.this.arn
}

output "topic_endpoint" {
  description = "The topic ARN for message publishers to send messages to"
  value       = aws_sns_topic.this.arn
}