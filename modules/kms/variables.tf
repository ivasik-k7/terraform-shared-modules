# ==============================================================================
# REQUIRED VARIABLES
# ==============================================================================

variable "name" {
  description = "Name of the KMS key (used for alias and tags)"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 256
    error_message = "Name must be between 1 and 256 characters."
  }
}

# ==============================================================================
# KEY CONFIGURATION
# ==============================================================================

variable "description" {
  description = "Description of the KMS key. If not provided, auto-generated from purpose and environment"
  type        = string
  default     = null
}

variable "key_usage" {
  description = "Intended use of the key. Valid values: ENCRYPT_DECRYPT, SIGN_VERIFY, GENERATE_VERIFY_MAC"
  type        = string
  default     = "ENCRYPT_DECRYPT"

  validation {
    condition     = contains(["ENCRYPT_DECRYPT", "SIGN_VERIFY", "GENERATE_VERIFY_MAC"], var.key_usage)
    error_message = "Key usage must be ENCRYPT_DECRYPT, SIGN_VERIFY, or GENERATE_VERIFY_MAC."
  }
}

variable "customer_master_key_spec" {
  description = "Key spec. Valid values depend on key_usage. For ENCRYPT_DECRYPT: SYMMETRIC_DEFAULT, RSA_2048, RSA_3072, RSA_4096, SM2"
  type        = string
  default     = "SYMMETRIC_DEFAULT"

  validation {
    condition = contains([
      "SYMMETRIC_DEFAULT",
      "RSA_2048", "RSA_3072", "RSA_4096",
      "ECC_NIST_P256", "ECC_NIST_P384", "ECC_NIST_P521",
      "ECC_SECG_P256K1",
      "HMAC_224", "HMAC_256", "HMAC_384", "HMAC_512",
      "SM2"
    ], var.customer_master_key_spec)
    error_message = "Invalid customer_master_key_spec. Check AWS documentation for valid values."
  }
}

variable "multi_region" {
  description = "Whether to create a multi-region primary key"
  type        = bool
  default     = false
}

# ==============================================================================
# KEY POLICY
# ==============================================================================

variable "key_policy" {
  description = "Complete custom key policy (JSON). Overrides additional_policy_statements if provided"
  type        = string
  default     = null

  validation {
    condition     = var.key_policy == null || can(jsondecode(var.key_policy))
    error_message = "key_policy must be valid JSON."
  }
}

variable "additional_policy_statements" {
  description = "Additional policy statements to append to the default policy"
  type = list(object({
    Sid       = string
    Effect    = string
    Principal = any
    Action    = any
    Resource  = string
    Condition = optional(any)
  }))
  default = null
}

variable "bypass_policy_lockout_safety_check" {
  description = "Bypass the key policy lockout safety check. Use with caution!"
  type        = bool
  default     = false
}

# ==============================================================================
# ROTATION & DELETION
# ==============================================================================

variable "enable_key_rotation" {
  description = "Enable automatic key rotation (only for symmetric keys)"
  type        = bool
  default     = true
}

variable "rotation_period_in_days" {
  description = "Period in days for automatic key rotation (90-2560). Only applies if enable_key_rotation is true"
  type        = number
  default     = 365

  validation {
    condition     = var.rotation_period_in_days >= 90 && var.rotation_period_in_days <= 2560
    error_message = "Rotation period must be between 90 and 2560 days."
  }
}

variable "deletion_window_in_days" {
  description = "Duration in days (7-30) before KMS key is deleted after destruction"
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "Deletion window must be between 7 and 30 days."
  }
}

variable "is_enabled" {
  description = "Whether the key is enabled"
  type        = bool
  default     = true
}

# ==============================================================================
# ALIAS
# ==============================================================================

variable "create_alias" {
  description = "Whether to create an alias for the KMS key"
  type        = bool
  default     = true
}

variable "alias_name" {
  description = "Alias name for the KMS key. If not provided, uses 'alias/{name}'"
  type        = string
  default     = null

  validation {
    condition = var.alias_name == null || (
      can(regex("^alias/[a-zA-Z0-9/_-]+$", var.alias_name)) &&
      !can(regex("^alias/aws/", var.alias_name))
    )
    error_message = "Alias must start with 'alias/' and cannot start with 'alias/aws/'."
  }
}

# ==============================================================================
# GRANTS
# ==============================================================================

variable "grants" {
  description = "Map of KMS grants to create. Key is grant name, value is grant configuration"
  type = map(object({
    grantee_principal = string
    operations        = list(string)
    constraints = optional(object({
      encryption_context_equals = optional(map(string))
      encryption_context_subset = optional(map(string))
    }))
    retiring_principal    = optional(string)
    grant_creation_tokens = optional(list(string))
    retire_on_delete      = optional(bool, true)
  }))
  default = {}

  validation {
    condition = alltrue([
      for grant in var.grants : alltrue([
        for operation in grant.operations : contains([
          "Decrypt", "Encrypt", "GenerateDataKey", "GenerateDataKeyWithoutPlaintext",
          "ReEncryptFrom", "ReEncryptTo", "Sign", "Verify", "GetPublicKey",
          "CreateGrant", "RetireGrant", "DescribeKey", "GenerateDataKeyPair",
          "GenerateDataKeyPairWithoutPlaintext", "GenerateMac", "VerifyMac"
        ], operation)
      ])
    ])
    error_message = "Invalid KMS grant operation specified."
  }
}

# ==============================================================================
# METADATA & TAGS
# ==============================================================================

variable "purpose" {
  description = "Purpose of the KMS key (e.g., 'database', 'secrets', 's3'). Used in auto-generated description and tags"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (e.g., 'production', 'staging', 'development'). Used in auto-generated description and tags"
  type        = string
  default     = null

  validation {
    condition = var.environment == null || contains([
      "production", "prod", "staging", "stage", "development", "dev", "testing", "test", "qa"
    ], var.environment)
    error_message = "Environment must be one of: production, prod, staging, stage, development, dev, testing, test, qa."
  }
}

variable "tags" {
  description = "Additional tags for the KMS key"
  type        = map(string)
  default     = {}
}
