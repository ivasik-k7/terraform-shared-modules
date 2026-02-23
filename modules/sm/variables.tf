variable "name_prefix" {
  description = "Path prefix for all secrets. Recommended format: \"<org>/<team>\". Results in: <name_prefix>/<environment>/<secret_key>. Set to \"\" to disable."
  type        = string
  default     = ""

  validation {
    condition     = !endswith(var.name_prefix, "/")
    error_message = "name_prefix must not end with a trailing slash."
  }

  validation {
    condition     = length(var.name_prefix) <= 200
    error_message = "name_prefix must be 200 characters or fewer (AWS secret name cap is 512 total)."
  }
}

variable "environment" {
  description = "Deployment environment injected into the secret path and default tags (e.g. dev, staging, prod)."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9_-]*$", var.environment))
    error_message = "environment must be lowercase alphanumeric, hyphens, or underscores only."
  }
}

variable "secrets" {
  description = <<-EOT
    Map of secrets to create. The map key is the final path segment.
    Full path: <name_prefix>/<environment>/<key> (empty segments are omitted).

    Value modes (mutually exclusive):
      secret_string    — raw string
      secret_key_value — map(string) serialized to JSON automatically
      secret_binary    — base64-encoded binary
      (omit all three)  — creates a placeholder; inject value out-of-band

    See README for full schema and examples.
  EOT

  type = map(object({
    description = optional(string, "Managed by Terraform")

    secret_string    = optional(string, null)
    secret_key_value = optional(map(string), null)
    secret_binary    = optional(string, null)

    kms_key_id = optional(string, null)

    recovery_window_in_days = optional(number, null)
    ignore_secret_changes   = optional(bool, false)

    rotation = optional(object({
      lambda_arn               = string
      automatically_after_days = optional(number, 30)
      rotate_immediately       = optional(bool, true)
    }), null)

    replica_regions = optional(list(object({
      region     = string
      kms_key_id = optional(string, null)
    })), [])

    policy = optional(object({
      reader_arns           = optional(list(string), [])
      manager_arns          = optional(list(string), [])
      additional_statements = optional(list(any), [])
    }), null)

    tags = optional(map(string), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.secrets :
      length(compact([
        v.secret_string != null ? "set" : null,
        v.secret_key_value != null ? "set" : null,
        v.secret_binary != null ? "set" : null,
      ])) <= 1
    ])
    error_message = "Each secret may specify at most one of: secret_string, secret_key_value, or secret_binary."
  }

  validation {
    condition = alltrue([
      for k, v in var.secrets :
      v.recovery_window_in_days == null ||
      v.recovery_window_in_days == 0 ||
      (v.recovery_window_in_days >= 7 && v.recovery_window_in_days <= 30)
    ])
    error_message = "recovery_window_in_days must be 0 (force-delete) or between 7 and 30."
  }
}

variable "default_kms_key_id" {
  description = "Default KMS key ARN applied to all secrets that do not specify their own kms_key_id. Null uses the AWS-managed key (aws/secretsmanager)."
  type        = string
  default     = null
}

variable "default_recovery_window_in_days" {
  description = "Default recovery window for secrets that do not specify their own. Use 0 only in non-production environments."
  type        = number
  default     = 30

  validation {
    condition     = var.default_recovery_window_in_days == 0 || (var.default_recovery_window_in_days >= 7 && var.default_recovery_window_in_days <= 30)
    error_message = "default_recovery_window_in_days must be 0 or between 7 and 30."
  }
}

variable "default_tags" {
  description = "Tags merged into all secrets. Per-secret tags take precedence on key conflicts."
  type        = map(string)
  default     = {}
}

variable "reader_arns" {
  description = "IAM principal ARNs granted GetSecretValue + DescribeSecret on every secret in this module invocation."
  type        = list(string)
  default     = []
}

variable "manager_arns" {
  description = "IAM principal ARNs granted full secrets management on every secret in this module invocation."
  type        = list(string)
  default     = []
}
