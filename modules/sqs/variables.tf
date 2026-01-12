# ============================================================================
# Queue Identity
# ============================================================================

variable "name" {
  description = "The name of the SQS queue. For FIFO queues, '.fifo' suffix is automatically added if not present"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 80
    error_message = "Queue name must be between 1 and 80 characters."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Queue Type Configuration
# ============================================================================

variable "fifo_queue" {
  description = "Whether to create a FIFO (First-In-First-Out) queue instead of standard queue"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO queues. Requires fifo_queue = true"
  type        = bool
  default     = false
}

variable "deduplication_scope" {
  description = "Scope of deduplication in FIFO queues. Valid values: 'messageGroup' or 'queue'. Requires fifo_queue = true and content_based_deduplication = true"
  type        = string
  default     = "queue"

  validation {
    condition     = contains(["messageGroup", "queue"], var.deduplication_scope)
    error_message = "Deduplication scope must be either 'messageGroup' or 'queue'."
  }
}

variable "fifo_throughput_limit" {
  description = "Throughput limit for FIFO queues. Valid values: 'perQueue' (300 msg/s) or 'perMessageGroupId' (3000 msg/s). Requires fifo_queue = true"
  type        = string
  default     = "perQueue"

  validation {
    condition     = contains(["perQueue", "perMessageGroupId"], var.fifo_throughput_limit)
    error_message = "FIFO throughput limit must be either 'perQueue' or 'perMessageGroupId'."
  }
}

# ============================================================================
# Message Handling Configuration
# ============================================================================

variable "visibility_timeout_seconds" {
  description = "The visibility timeout for the queue in seconds (0-43200). Default is 30. After this time, a message becomes visible again if not deleted"
  type        = number
  default     = 30

  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "Visibility timeout must be between 0 and 43200 seconds (12 hours)."
  }
}

variable "message_retention_seconds" {
  description = "The message retention period in seconds (60-1209600). Default is 345600 (4 days). Minimum 60 seconds, maximum 14 days"
  type        = number
  default     = 345600

  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "Message retention must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "max_message_size" {
  description = "The maximum message size in bytes (1024-262144). Default is 262144 (256 KB). Minimum 1 KB, maximum 256 KB"
  type        = number
  default     = 262144

  validation {
    condition     = var.max_message_size >= 1024 && var.max_message_size <= 262144
    error_message = "Maximum message size must be between 1024 bytes (1 KB) and 262144 bytes (256 KB)."
  }
}

variable "delay_seconds" {
  description = "The time in seconds for which the message is delayed (0-900). Default is 0. Messages are not visible to consumers during this period"
  type        = number
  default     = 0

  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "Delay seconds must be between 0 and 900 seconds (15 minutes)."
  }
}

variable "receive_wait_time_seconds" {
  description = "The time in seconds for long polling (0-20). Default is 0. Enables long polling for more efficient message retrieval"
  type        = number
  default     = 0

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "Receive wait time must be between 0 and 20 seconds."
  }
}

# ============================================================================
# Encryption Configuration
# ============================================================================

variable "sqs_managed_sse_enabled" {
  description = "Enable server-side encryption (SSE) using SQS-managed keys. Ignored if kms_master_key_id is specified. Default is true"
  type        = bool
  default     = true
}

variable "kms_master_key_id" {
  description = "The ID of an AWS-managed CMK, customer-managed CMK, or KMS key alias for encryption. If specified, takes precedence over sqs_managed_sse_enabled"
  type        = string
  default     = null
}

variable "kms_data_key_reuse_period_seconds" {
  description = "The length of time in seconds for which Amazon SQS can reuse a data key to encrypt messages (60-86400). Default is 300. Only applies when using custom KMS keys"
  type        = number
  default     = 300

  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "KMS data key reuse period must be between 60 and 86400 seconds (1 minute to 24 hours)."
  }
}

# ============================================================================
# Dead Letter Queue (DLQ) Configuration
# ============================================================================

variable "create_dlq" {
  description = "Whether to create an associated Dead Letter Queue for handling failed messages"
  type        = bool
  default     = false
}

variable "max_receive_count" {
  description = "The number of times a message is received before being sent to the Dead Letter Queue (1-1440). Default is 5"
  type        = number
  default     = 5

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 1440
    error_message = "Maximum receive count must be between 1 and 1440."
  }
}

variable "dlq_message_retention_seconds" {
  description = "The message retention period for the DLQ in seconds (60-1209600). Default is 1209600 (14 days). Allows longer retention of failed messages"
  type        = number
  default     = 1209600

  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "DLQ message retention must be between 60 seconds (1 minute) and 1209600 seconds (14 days)."
  }
}

variable "redrive_policy" {
  description = "The JSON redrive policy for the queue. Automatically created if create_dlq is true. Can be overridden for advanced use cases"
  type        = string
  default     = null
}

variable "redrive_allow_policy" {
  description = "The JSON policy that allows other queues to send messages to this queue as a DLQ. Only needed if this queue serves as a DLQ for other queues"
  type        = string
  default     = null
}

# ============================================================================
# Access Control and Policy
# ============================================================================

variable "queue_policy" {
  description = "The JSON IAM policy document for the queue. Controls who can perform what actions on the queue"
  type        = string
  default     = null

  validation {
    condition     = var.queue_policy == null || can(jsondecode(var.queue_policy))
    error_message = "Queue policy must be valid JSON if provided."
  }
}
