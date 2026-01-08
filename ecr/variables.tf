################################################################################
# Repository Configuration
################################################################################

variable "repository_name" {
  description = "The name of the ECR repository"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-_/]*$", var.repository_name))
    error_message = "Repository name must start with lowercase letter or number and contain only lowercase letters, numbers, hyphens, underscores, and forward slashes."
  }
}

variable "image_tag_mutability" {
  description = "The tag mutability setting for images. IMMUTABLE prevents tags from being overwritten, MUTABLE allows overwriting."
  type        = string
  default     = "IMMUTABLE"

  validation {
    condition     = contains(["MUTABLE", "IMMUTABLE"], var.image_tag_mutability)
    error_message = "image_tag_mutability must be either MUTABLE or IMMUTABLE."
  }
}

variable "force_delete" {
  description = "If true, forces the deletion of the repository even if it contains images"
  type        = bool
  default     = false
}

################################################################################
# Image Scanning Configuration
################################################################################

variable "scan_on_push" {
  description = "Indicates whether images are scanned for vulnerabilities after being pushed to the repository"
  type        = bool
  default     = true
}

################################################################################
# Encryption Configuration
################################################################################

variable "encryption_type" {
  description = "The encryption type for the repository. AES256 (AWS-managed) or KMS (customer-managed key)"
  type        = string
  default     = "AES256"

  validation {
    condition     = contains(["AES256", "KMS"], var.encryption_type)
    error_message = "encryption_type must be either AES256 or KMS."
  }
}

variable "kms_key_arn" {
  description = "The ARN of the KMS key to use for encryption. Required when encryption_type is KMS. Ignored for AES256."
  type        = string
  default     = null
}

################################################################################
# Lifecycle Management Configuration
################################################################################

variable "enable_lifecycle_policy" {
  description = "Enable lifecycle policy for automatic image cleanup and retention management"
  type        = bool
  default     = true
}

variable "lifecycle_rules" {
  description = "Lifecycle policy rules"
  type = list(object({
    rule_priority    = number
    description      = string
    tag_status       = string
    tag_prefix_list  = optional(list(string), [])
    tag_pattern_list = optional(list(string), [])
    count_type       = string
    count_number     = number
    count_unit       = optional(string, "days")
    action_type      = string
  }))
  default = []
}

################################################################################
# Repository Access Control Configuration
################################################################################

variable "create_repository_policy" {
  description = "Whether to create and attach a repository policy"
  type        = bool
  default     = true
}

variable "repository_policy_statements" {
  description = "Additional IAM policy statements for the repository policy. Allows fine-grained access control."
  type = list(object({
    sid    = string
    effect = optional(string, "Allow") # Allow or Deny
    principals = optional(object({
      type        = optional(string, "AWS")
      identifiers = list(string)
    }), null)
    actions   = list(string)
    resources = optional(list(string), null) # Defaults to repository ARN
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = [
    {
      sid    = "AllowFullAccessToAccount"
      effect = "Allow"
      principals = {
        type        = "AWS"
        identifiers = []
      }
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:GetRepositoryPolicy",
        "ecr:ListImages",
        "ecr:DeleteRepository",
        "ecr:BatchDeleteImage",
        "ecr:SetRepositoryPolicy",
        "ecr:DeleteRepositoryPolicy"
      ]
    }
  ]
}

variable "allowed_principals" {
  description = "AWS principals (roles, users, accounts) that should have pull/push access to the repository. Format: arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME"
  type        = list(string)
  default     = []
}

variable "allowed_pull_principals" {
  description = "AWS principals (roles, users, accounts) that should have read-only (pull) access to the repository"
  type        = list(string)
  default     = []
}

################################################################################
# Image Configuration
################################################################################

# Note: Image tag mutability is controlled via image_tag_mutability variable above

################################################################################
# Replication Configuration
################################################################################

variable "enable_replication" {
  description = "Enable repository image replication across regions or registries"
  type        = bool
  default     = false
}

variable "replication_rules" {
  description = "Replication rules for pushing images to other registries or regions. Each rule can replicate to multiple destinations."
  type = list(object({
    destinations = list(object({
      region      = string
      registry_id = string
    }))
    repository_filters = optional(list(object({
      filter_type = string # PREFIX_MATCH is the only supported type
      filter      = string # Repository name prefix to match
    })), [])
  }))
  default = []
}

################################################################################
# Logging and Monitoring
################################################################################

variable "enable_logging" {
  description = "Enable CloudWatch logging for ECR actions"
  type        = bool
  default     = false
}

variable "cloudwatch_log_group_name" {
  description = "CloudWatch log group name for ECR logs. Only used if enable_logging is true."
  type        = string
  default     = null
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "cloudwatch_log_retention_days must be a valid CloudWatch retention period."
  }
}

variable "cloudwatch_kms_key_id" {
  description = "The KMS key ID to use for encrypting CloudWatch log data. Only used if enable_logging is true."
  type        = string
  default     = null
}

################################################################################
# Registry Scanning Configuration
################################################################################

variable "enable_registry_scanning" {
  description = "Enable enhanced scanning at the registry level"
  type        = bool
  default     = false
}

variable "registry_scan_type" {
  description = "Scanning type to set for the registry (BASIC or ENHANCED)"
  type        = string
  default     = "ENHANCED"

  validation {
    condition     = contains(["BASIC", "ENHANCED"], var.registry_scan_type)
    error_message = "Registry scan type must be either BASIC or ENHANCED."
  }
}

variable "registry_scanning_rules" {
  description = "Registry scanning rules"
  type = list(object({
    scan_frequency    = string
    repository_filter = string
    filter_type       = string
  }))
  default = []
}

variable "pull_through_cache_rules" {
  description = "Pull through cache rules for upstream registries"
  type = map(object({
    ecr_repository_prefix = string
    upstream_registry_url = string
    credential_arn        = optional(string)
  }))
  default = {}
}

variable "enable_registry_policy" {
  description = "Enable registry-level policy"
  type        = bool
  default     = false
}

variable "registry_policy_json" {
  description = "JSON policy document for registry-level permissions"
  type        = string
  default     = null
}


################################################################################
# Tags and Metadata
################################################################################

variable "tags" {
  description = "A map of tags to apply to the repository and all related resources"
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "Common tags to apply alongside the tags variable for consistent resource identification"
  type        = map(string)
  default     = {}
}
