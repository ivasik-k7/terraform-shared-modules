# ============================================================================
# Local Values
# ============================================================================

locals {
  queue_name = var.fifo_queue && !strcontains(var.name, ".fifo") ? "${var.name}.fifo" : var.name

  redrive_policy = var.create_dlq ? jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq[0].arn
    maxReceiveCount     = var.max_receive_count
  }) : var.redrive_policy

  common_tags = merge(
    var.tags,
    {
      Name = local.queue_name
    }
  )

  dlq_tags = merge(
    var.tags,
    {
      Name    = "${local.queue_name}-dlq"
      Purpose = "DeadLetterQueue"
    }
  )
}

# ============================================================================
# SQS Queue - Primary
# ============================================================================

resource "aws_sqs_queue" "this" {
  name                       = local.queue_name
  visibility_timeout_seconds = var.visibility_timeout_seconds
  message_retention_seconds  = var.message_retention_seconds
  max_message_size           = var.max_message_size
  delay_seconds              = var.delay_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds

  # FIFO queue configuration
  fifo_queue                  = var.fifo_queue
  content_based_deduplication = var.fifo_queue ? var.content_based_deduplication : null
  deduplication_scope         = var.fifo_queue && var.content_based_deduplication ? var.deduplication_scope : null
  fifo_throughput_limit       = var.fifo_queue ? var.fifo_throughput_limit : null

  # Encryption configuration
  kms_master_key_id                 = var.kms_master_key_id
  kms_data_key_reuse_period_seconds = var.kms_master_key_id != null ? var.kms_data_key_reuse_period_seconds : null
  sqs_managed_sse_enabled           = var.kms_master_key_id == null ? var.sqs_managed_sse_enabled : null

  # Message routing and policies
  redrive_policy       = local.redrive_policy
  redrive_allow_policy = var.redrive_allow_policy

  tags = local.common_tags

  depends_on = [aws_sqs_queue.dlq]
}

# ============================================================================
# SQS Queue - Dead Letter Queue (Optional)
# ============================================================================

resource "aws_sqs_queue" "dlq" {
  count = var.create_dlq ? 1 : 0

  # Build DLQ name with .fifo suffix for FIFO queues
  name = var.fifo_queue ? "${local.queue_name}-dlq.fifo" : "${local.queue_name}-dlq"

  # FIFO configuration must match primary queue
  fifo_queue                = var.fifo_queue
  message_retention_seconds = var.dlq_message_retention_seconds

  # Use SQS-managed encryption for DLQ (inherits from primary if custom KMS is used)
  sqs_managed_sse_enabled = var.kms_master_key_id == null ? var.sqs_managed_sse_enabled : null
  kms_master_key_id       = var.kms_master_key_id

  tags = local.dlq_tags
}

# ============================================================================
# SQS Queue Policy
# ============================================================================

resource "aws_sqs_queue_policy" "this" {
  count     = var.queue_policy != null ? 1 : 0
  queue_url = aws_sqs_queue.this.url
  policy    = var.queue_policy
}

