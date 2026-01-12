# ============================================================================
# Primary Queue - Identity
# ============================================================================

output "queue_id" {
  description = "The URL of the SQS queue"
  value       = aws_sqs_queue.this.id
}

output "queue_url" {
  description = "The URL of the SQS queue (same as queue_id)"
  value       = aws_sqs_queue.this.url
}

output "queue_arn" {
  description = "The ARN of the SQS queue"
  value       = aws_sqs_queue.this.arn
}

output "queue_name" {
  description = "The name of the SQS queue"
  value       = aws_sqs_queue.this.name
}

# ============================================================================
# Primary Queue - Configuration Details
# ============================================================================

output "visibility_timeout_seconds" {
  description = "The visibility timeout configured for the queue in seconds"
  value       = aws_sqs_queue.this.visibility_timeout_seconds
}

output "message_retention_seconds" {
  description = "The message retention period configured for the queue in seconds"
  value       = aws_sqs_queue.this.message_retention_seconds
}

output "max_message_size" {
  description = "The maximum message size configured for the queue in bytes"
  value       = aws_sqs_queue.this.max_message_size
}

output "delay_seconds" {
  description = "The delivery delay configured for the queue in seconds"
  value       = aws_sqs_queue.this.delay_seconds
}

output "receive_wait_time_seconds" {
  description = "The long polling wait time configured for the queue in seconds"
  value       = aws_sqs_queue.this.receive_wait_time_seconds
}

output "fifo_queue" {
  description = "Whether the queue is a FIFO queue"
  value       = aws_sqs_queue.this.fifo_queue
}

output "content_based_deduplication" {
  description = "Whether content-based deduplication is enabled (FIFO queues only)"
  value       = aws_sqs_queue.this.content_based_deduplication
}

output "deduplication_scope" {
  description = "The scope of deduplication (FIFO queues only)"
  value       = aws_sqs_queue.this.deduplication_scope
}

output "fifo_throughput_limit" {
  description = "The throughput limit for FIFO queues (FIFO queues only)"
  value       = aws_sqs_queue.this.fifo_throughput_limit
}

# ============================================================================
# Primary Queue - Encryption
# ============================================================================

output "kms_master_key_id" {
  description = "The KMS master key ID used for encryption, if any"
  value       = aws_sqs_queue.this.kms_master_key_id
}

output "sqs_managed_sse_enabled" {
  description = "Whether SQS-managed server-side encryption is enabled"
  value       = aws_sqs_queue.this.sqs_managed_sse_enabled
}

output "kms_data_key_reuse_period_seconds" {
  description = "The KMS data key reuse period in seconds"
  value       = aws_sqs_queue.this.kms_data_key_reuse_period_seconds
}

# ============================================================================
# Dead Letter Queue (DLQ)
# ============================================================================

output "dlq_id" {
  description = "The URL of the Dead Letter Queue, if created"
  value       = try(aws_sqs_queue.dlq[0].id, null)
}

output "dlq_url" {
  description = "The URL of the Dead Letter Queue, if created"
  value       = try(aws_sqs_queue.dlq[0].url, null)
}

output "dlq_arn" {
  description = "The ARN of the Dead Letter Queue, if created"
  value       = try(aws_sqs_queue.dlq[0].arn, null)
}

output "dlq_name" {
  description = "The name of the Dead Letter Queue, if created"
  value       = try(aws_sqs_queue.dlq[0].name, null)
}

output "max_receive_count" {
  description = "The maximum number of times a message is delivered before being sent to the DLQ"
  value       = var.create_dlq ? var.max_receive_count : null
}

output "dlq_created" {
  description = "Whether a Dead Letter Queue was created"
  value       = var.create_dlq
}

# ============================================================================
# Queue Policy
# ============================================================================

output "queue_policy_applied" {
  description = "Whether a queue policy was applied"
  value       = var.queue_policy != null
}

# ============================================================================
# Combined Outputs for Integration
# ============================================================================

output "queue_info" {
  description = "Comprehensive queue information for integration with other services"
  value = {
    id        = aws_sqs_queue.this.id
    url       = aws_sqs_queue.this.url
    arn       = aws_sqs_queue.this.arn
    name      = aws_sqs_queue.this.name
    fifo      = aws_sqs_queue.this.fifo_queue
    encrypted = aws_sqs_queue.this.sqs_managed_sse_enabled || aws_sqs_queue.this.kms_master_key_id != null
  }
}

output "dlq_info" {
  description = "Comprehensive DLQ information, if created"
  value = var.create_dlq ? {
    id                = aws_sqs_queue.dlq[0].id
    url               = aws_sqs_queue.dlq[0].url
    arn               = aws_sqs_queue.dlq[0].arn
    name              = aws_sqs_queue.dlq[0].name
    max_receive_count = var.max_receive_count
  } : null
}

# ============================================================================
# Lambda/Application Integration
# ============================================================================

output "queue_endpoint" {
  description = "The endpoint (URL) for message producers to send messages to"
  value       = aws_sqs_queue.this.url
}

output "queue_arn_for_policy" {
  description = "The queue ARN formatted for use in IAM policies"
  value       = aws_sqs_queue.this.arn
}

output "dlq_arn_for_policy" {
  description = "The DLQ ARN formatted for use in IAM policies, if created"
  value       = try(aws_sqs_queue.dlq[0].arn, null)
}

