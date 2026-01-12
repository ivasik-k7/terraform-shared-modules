# ============================================================================
# Topic Identity
# ============================================================================

variable "name" {
  description = "The name of the SNS topic. For FIFO topics, '.fifo' suffix is automatically added if not present"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 256
    error_message = "Topic name must be between 1 and 256 characters."
  }
}

variable "display_name" {
  description = "The display name for the SNS topic (used in SMS messages)"
  type        = string
  default     = null

  validation {
    condition     = var.display_name == null || length(var.display_name) <= 100
    error_message = "Display name must be 100 characters or less."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Topic Type Configuration
# ============================================================================

variable "fifo_topic" {
  description = "Whether to create a FIFO (First-In-First-Out) topic instead of standard topic"
  type        = bool
  default     = false
}

variable "content_based_deduplication" {
  description = "Enables content-based deduplication for FIFO topics. Requires fifo_topic = true"
  type        = bool
  default     = false
}

# ============================================================================
# Message Delivery Configuration
# ============================================================================

variable "delivery_policy" {
  description = "The JSON delivery policy for the topic. Controls retry behavior and delivery throttling"
  type        = string
  default     = null

  validation {
    condition     = var.delivery_policy == null || can(jsondecode(var.delivery_policy))
    error_message = "Delivery policy must be valid JSON if provided."
  }
}

variable "http_success_feedback_role_arn" {
  description = "IAM role ARN for successful HTTP/HTTPS delivery feedback"
  type        = string
  default     = null
}

variable "http_success_feedback_sample_rate" {
  description = "Sample rate percentage (0-100) for successful HTTP/HTTPS delivery feedback"
  type        = number
  default     = null

  validation {
    condition     = var.http_success_feedback_sample_rate == null || (var.http_success_feedback_sample_rate >= 0 && var.http_success_feedback_sample_rate <= 100)
    error_message = "HTTP success feedback sample rate must be between 0 and 100."
  }
}

variable "http_failure_feedback_role_arn" {
  description = "IAM role ARN for failed HTTP/HTTPS delivery feedback"
  type        = string
  default     = null
}

variable "lambda_success_feedback_role_arn" {
  description = "IAM role ARN for successful Lambda delivery feedback"
  type        = string
  default     = null
}

variable "lambda_success_feedback_sample_rate" {
  description = "Sample rate percentage (0-100) for successful Lambda delivery feedback"
  type        = number
  default     = null

  validation {
    condition     = var.lambda_success_feedback_sample_rate == null || (var.lambda_success_feedback_sample_rate >= 0 && var.lambda_success_feedback_sample_rate <= 100)
    error_message = "Lambda success feedback sample rate must be between 0 and 100."
  }
}

variable "lambda_failure_feedback_role_arn" {
  description = "IAM role ARN for failed Lambda delivery feedback"
  type        = string
  default     = null
}

variable "sqs_success_feedback_role_arn" {
  description = "IAM role ARN for successful SQS delivery feedback"
  type        = string
  default     = null
}

variable "sqs_success_feedback_sample_rate" {
  description = "Sample rate percentage (0-100) for successful SQS delivery feedback"
  type        = number
  default     = null

  validation {
    condition     = var.sqs_success_feedback_sample_rate == null || (var.sqs_success_feedback_sample_rate >= 0 && var.sqs_success_feedback_sample_rate <= 100)
    error_message = "SQS success feedback sample rate must be between 0 and 100."
  }
}

variable "sqs_failure_feedback_role_arn" {
  description = "IAM role ARN for failed SQS delivery feedback"
  type        = string
  default     = null
}

variable "firehose_success_feedback_role_arn" {
  description = "IAM role ARN for successful Firehose delivery feedback"
  type        = string
  default     = null
}

variable "firehose_success_feedback_sample_rate" {
  description = "Sample rate percentage (0-100) for successful Firehose delivery feedback"
  type        = number
  default     = null

  validation {
    condition     = var.firehose_success_feedback_sample_rate == null || (var.firehose_success_feedback_sample_rate >= 0 && var.firehose_success_feedback_sample_rate <= 100)
    error_message = "Firehose success feedback sample rate must be between 0 and 100."
  }
}

variable "firehose_failure_feedback_role_arn" {
  description = "IAM role ARN for failed Firehose delivery feedback"
  type        = string
  default     = null
}

variable "application_success_feedback_role_arn" {
  description = "IAM role ARN for successful mobile push delivery feedback"
  type        = string
  default     = null
}

variable "application_success_feedback_sample_rate" {
  description = "Sample rate percentage (0-100) for successful mobile push delivery feedback"
  type        = number
  default     = null

  validation {
    condition     = var.application_success_feedback_sample_rate == null || (var.application_success_feedback_sample_rate >= 0 && var.application_success_feedback_sample_rate <= 100)
    error_message = "Application success feedback sample rate must be between 0 and 100."
  }
}

variable "application_failure_feedback_role_arn" {
  description = "IAM role ARN for failed mobile push delivery feedback"
  type        = string
  default     = null
}

# ============================================================================
# Encryption Configuration
# ============================================================================

variable "kms_master_key_id" {
  description = "The ID of an AWS-managed CMK, customer-managed CMK, or KMS key alias for encryption"
  type        = string
  default     = null
}

# ============================================================================
# Access Control and Policy
# ============================================================================

variable "topic_policy" {
  description = "The JSON IAM policy document for the topic. Controls who can perform what actions on the topic"
  type        = string
  default     = null

  validation {
    condition     = var.topic_policy == null || can(jsondecode(var.topic_policy))
    error_message = "Topic policy must be valid JSON if provided."
  }
}

# ============================================================================
# Subscription Configuration
# ============================================================================

variable "subscriptions" {
  description = "List of subscription configurations for the topic"
  type = list(object({
    protocol               = string
    endpoint               = string
    endpoint_auto_confirms = optional(bool, false)
    raw_message_delivery   = optional(bool, false)
    filter_policy          = optional(string)
    filter_policy_scope    = optional(string, "MessageAttributes")
    delivery_policy        = optional(string)
    redrive_policy         = optional(string)
    subscription_role_arn  = optional(string)
  }))
  default = []

  validation {
    condition = alltrue([
      for sub in var.subscriptions : contains([
        "sqs", "sms", "email", "email-json", "http", "https", 
        "application", "lambda", "firehose"
      ], sub.protocol)
    ])
    error_message = "Protocol must be one of: sqs, sms, email, email-json, http, https, application, lambda, firehose."
  }

  validation {
    condition = alltrue([
      for sub in var.subscriptions : 
      sub.filter_policy_scope == null || contains(["MessageAttributes", "MessageBody"], sub.filter_policy_scope)
    ])
    error_message = "Filter policy scope must be either 'MessageAttributes' or 'MessageBody'."
  }

  validation {
    condition = alltrue([
      for sub in var.subscriptions : 
      sub.filter_policy == null || can(jsondecode(sub.filter_policy))
    ])
    error_message = "Filter policy must be valid JSON if provided."
  }

  validation {
    condition = alltrue([
      for sub in var.subscriptions : 
      sub.delivery_policy == null || can(jsondecode(sub.delivery_policy))
    ])
    error_message = "Delivery policy must be valid JSON if provided."
  }

  validation {
    condition = alltrue([
      for sub in var.subscriptions : 
      sub.redrive_policy == null || can(jsondecode(sub.redrive_policy))
    ])
    error_message = "Redrive policy must be valid JSON if provided."
  }
}

# ============================================================================
# Message Templates Configuration
# ============================================================================

variable "message_templates" {
  description = "Message templates for different message types"
  type = map(object({
    subject = string
    message = string
    default_message = optional(string)
  }))
  default = {}
}

# ============================================================================
# Data Protection Configuration
# ============================================================================

variable "signature_version" {
  description = "The signature version corresponds to the hashing algorithm used while creating the signature of the notifications, subscription confirmations, or unsubscribe confirmation messages sent by Amazon SNS"
  type        = number
  default     = null

  validation {
    condition     = var.signature_version == null || contains([1, 2], var.signature_version)
    error_message = "Signature version must be either 1 or 2."
  }
}

variable "tracing_config" {
  description = "Tracing mode of an Amazon SNS topic. Valid values: PassThrough, Active"
  type        = string
  default     = null

  validation {
    condition     = var.tracing_config == null || contains(["PassThrough", "Active"], var.tracing_config)
    error_message = "Tracing config must be either 'PassThrough' or 'Active'."
  }
}