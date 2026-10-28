# Every variable: description, type, nullable = false, a default unless it
# must be supplied, and a validation for anything that reaches an API.

variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Log group name, for example /app/orders. Changing it replaces the group, and with it every log line in it."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9._/#-]{1,512}$", var.name)) && !startswith(var.name, "aws/")
    error_message = "name must be 1-512 of letters, digits . _ - / #, and not start with aws/ (reserved for AWS services)."
  }
}

variable "tags" {
  description = "Tags for every resource. The module adds ManagedBy and Module last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "retention_days" {
  description = "Days to keep log events. 0 keeps them forever: the cost that grows without bound ($0.03 per GB-month in most regions)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retention_days)
    error_message = "retention_days must be 0 or a retention period CloudWatch Logs accepts."
  }
}

variable "log_group_class" {
  description = "STANDARD, or INFREQUENT_ACCESS: a lower ingestion price (storage is the same), but no metric filters, subscription filters, Live Tail, anomaly detection or GetLogEvents/FilterLogEvents - read it with Logs Insights. Fixed at creation: changing it replaces the group."
  type        = string
  default     = "STANDARD"
  nullable    = false

  validation {
    condition     = contains(["STANDARD", "INFREQUENT_ACCESS"], var.log_group_class)
    error_message = "log_group_class must be STANDARD or INFREQUENT_ACCESS."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key for the log group. Empty: CloudWatch Logs' own encryption. output.kms_key_policy_requirements says what the key policy must allow - read it in the first plan, before the apply."
  type        = string
  default     = ""
  nullable    = false

  validation {
    # Empty is the "unset" convention; a ternary, not ||, because the floor
    # evaluates both operands.
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "skip_destroy" {
  description = "Keep the log group (and its logs) when the module is destroyed or the group is replaced. Logs kept for an audit must survive the teardown that ends the system they recorded."
  type        = bool
  default     = false
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Names of advisory checks whose warning is intended here (README, \"Advisory checks\"). An acknowledged check stays silent and is listed in output.governance."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.acknowledged_checks : contains(["log_retention_is_bounded", "logs_use_a_customer_key"], c)])
    error_message = "acknowledged_checks names a check that does not exist. README \"Advisory checks\" lists them."
  }
}
