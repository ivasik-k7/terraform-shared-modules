
variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "Project name must contain only lowercase letters, numbers, and hyphens"
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod", "test"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test"
  }
}

variable "input_bucket_arn" {
  description = "ARN of the S3 bucket containing documents to process"
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:s3:::[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.input_bucket_arn))
    error_message = "Input bucket ARN must be a valid S3 bucket ARN format"
  }
}

variable "output_bucket_arn" {
  description = "ARN of the S3 bucket for Textract output (optional for sync operations)"
  type        = string
  default     = null

  validation {
    condition     = var.output_bucket_arn == null || can(regex("^arn:[a-z-]+:s3:::[a-z0-9][a-z0-9.-]*[a-z0-9]$", var.output_bucket_arn))
    error_message = "Output bucket ARN must be a valid S3 bucket ARN format or null"
  }
}

variable "input_bucket_prefix" {
  description = "S3 key prefix for input documents (e.g., 'documents/inbox/')"
  type        = string
  default     = ""
}

variable "output_bucket_prefix" {
  description = "S3 key prefix for output results (e.g., 'results/textract/')"
  type        = string
  default     = ""
}

variable "external_id" {
  description = "External ID for assume role policy (security best practice)"
  type        = string
  default     = "textract-external-id"
  sensitive   = true
}

variable "enable_async_processing" {
  description = "Enable asynchronous processing with SNS notifications"
  type        = bool
  default     = true
}

variable "enable_sns_encryption" {
  description = "Enable encryption for SNS topics using KMS"
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of KMS key for encryption (required if encryption is enabled)"
  type        = string
  default     = null
}

variable "sns_subscriber_principals" {
  description = "List of AWS principal ARNs allowed to subscribe to SNS topics"
  type        = list(string)
  default     = []
}

variable "allowed_document_types" {
  description = "List of allowed document file extensions"
  type        = list(string)
  default     = ["pdf", "png", "jpg", "jpeg", "tiff"]
}

variable "max_document_size_mb" {
  description = "Maximum document size in megabytes for processing"
  type        = number
  default     = 10

  validation {
    condition     = var.max_document_size_mb > 0 && var.max_document_size_mb <= 500
    error_message = "Document size must be between 1 and 500 MB"
  }
}

variable "textract_features" {
  description = "List of Textract features to enable (TABLES, FORMS, QUERIES, SIGNATURES, LAYOUT)"
  type        = list(string)
  default     = ["TABLES", "FORMS"]

  validation {
    condition     = alltrue([for f in var.textract_features : contains(["TABLES", "FORMS", "QUERIES", "SIGNATURES", "LAYOUT"], f)])
    error_message = "Invalid Textract feature. Must be one of: TABLES, FORMS, QUERIES, SIGNATURES, LAYOUT"
  }
}

variable "s3_kms_key_arn" {
  description = "ARN of KMS key for S3 encryption (if different from SNS KMS key)"
  type        = string
  default     = null
}

variable "enable_textract_metrics" {
  description = "Enable custom CloudWatch metrics publishing"
  type        = bool
  default     = false
}

variable "notification_email_endpoints" {
  description = "List of email addresses to subscribe to SNS topics for notifications"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for email in var.notification_email_endpoints : can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", email))])
    error_message = "All notification endpoints must be valid email addresses"
  }
}

variable "notification_sqs_endpoints" {
  description = "List of SQS queue ARNs to subscribe to SNS topics"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.notification_sqs_endpoints : can(regex("^arn:[a-z-]+:sqs:[a-z0-9-]+:[0-9]{12}:[a-zA-Z0-9_-]+$", arn))])
    error_message = "All SQS endpoints must be valid SQS queue ARNs"
  }
}

variable "notification_lambda_endpoints" {
  description = "List of Lambda function ARNs to subscribe to SNS topics"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for arn in var.notification_lambda_endpoints : can(regex("^arn:[a-z-]+:lambda:[a-z0-9-]+:[0-9]{12}:function:[a-zA-Z0-9_-]+$", arn))])
    error_message = "All Lambda endpoints must be valid Lambda function ARNs"
  }
}

variable "enable_sns_subscription_filter" {
  description = "Enable SNS subscription filter policy for selective message delivery"
  type        = bool
  default     = false
}

variable "sns_filter_policy" {
  description = "JSON filter policy for SNS subscriptions (applied when enable_sns_subscription_filter is true)"
  type        = string
  default     = null
}

variable "enable_dead_letter_queue" {
  description = "Enable Dead Letter Queue for failed SNS message deliveries"
  type        = bool
  default     = false
}

variable "dlq_max_receive_count" {
  description = "Maximum number of times a message can be received before being sent to DLQ"
  type        = number
  default     = 3

  validation {
    condition     = var.dlq_max_receive_count >= 1 && var.dlq_max_receive_count <= 1000
    error_message = "DLQ max receive count must be between 1 and 1000"
  }
}

variable "enable_cross_account_access" {
  description = "Enable cross-account access to Textract role"
  type        = bool
  default     = false
}

variable "trusted_account_ids" {
  description = "List of AWS account IDs allowed to assume the Textract role"
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.trusted_account_ids : can(regex("^[0-9]{12}$", id))])
    error_message = "All account IDs must be 12-digit numbers"
  }
}

variable "iam_permissions_boundary_arn" {
  description = "ARN of IAM permissions boundary to apply to Textract role"
  type        = string
  default     = null

  validation {
    condition     = var.iam_permissions_boundary_arn == null || can(regex("^arn:[a-z-]+:iam::[0-9]{12}:policy/", var.iam_permissions_boundary_arn))
    error_message = "Permissions boundary must be a valid IAM policy ARN"
  }
}

variable "enable_enhanced_monitoring" {
  description = "Enable enhanced monitoring with additional CloudWatch metrics"
  type        = bool
  default     = false
}

variable "metrics_namespace" {
  description = "Custom CloudWatch metrics namespace"
  type        = string
  default     = "Custom/Textract"
}



variable "sns_message_retention_seconds" {
  description = "SNS message retention period in seconds (60-1209600)"
  type        = number
  default     = 345600 # 4 days

  validation {
    condition     = var.sns_message_retention_seconds >= 60 && var.sns_message_retention_seconds <= 1209600
    error_message = "SNS message retention must be between 60 and 1209600 seconds"
  }
}

variable "enable_sns_content_based_deduplication" {
  description = "Enable content-based deduplication for SNS FIFO topics"
  type        = bool
  default     = false
}

variable "alarm_datapoints_to_alarm" {
  description = "Number of datapoints that must breach threshold to trigger alarm"
  type        = number
  default     = 1

  validation {
    condition     = var.alarm_datapoints_to_alarm >= 1
    error_message = "Datapoints to alarm must be at least 1"
  }
}

variable "enable_cloudwatch_logs" {
  description = "Enable CloudWatch log group for Textract operations"
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period"
  }
}

variable "enable_log_encryption" {
  description = "Enable encryption for CloudWatch logs using KMS"
  type        = bool
  default     = false
}

variable "enable_cloudwatch_alarms" {
  description = "Enable CloudWatch alarms for Textract metrics"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "List of ARNs to notify when alarms trigger"
  type        = list(string)
  default     = []
}

variable "alarm_evaluation_periods" {
  description = "Number of periods to evaluate for alarms"
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period in seconds for alarm evaluation"
  type        = number
  default     = 300
}

variable "error_threshold" {
  description = "Error count threshold for triggering alarm"
  type        = number
  default     = 10
}

variable "throttle_threshold" {
  description = "Throttle count threshold for triggering alarm"
  type        = number
  default     = 5
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
