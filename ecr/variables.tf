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

################################################################################
# Image Scanning Configuration
################################################################################

variable "scan_on_push" {
  description = "Indicates whether images are scanned for vulnerabilities after being pushed to the repository"
  type        = bool
  default     = true
}

variable "scan_on_push_filters" {
  description = "Configuration for enhanced image scanning. When enabled, provides more detailed vulnerability information."
  type = object({
    enabled       = optional(bool, false)
    filter_type   = optional(string, "INCLUDE") # INCLUDE or EXCLUDE
    filter_values = optional(list(string), [])
  })
  default = {}
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
  description = "Lifecycle rules for managing image retention. Allows custom rules for different image tag patterns and counts."
  type = list(object({
    rule_priority   = number
    description     = string
    tag_status      = optional(string, "untagged") # untagged, tagged, any
    tag_prefix_list = optional(list(string), [])
    count_type      = optional(string, "sinceImagePushed") # sinceImagePushed, imageCountMoreThan
    count_unit      = optional(string, "days")             # days, imageCountMoreThan
    count_number    = optional(number)
    action_type     = optional(string, "expire") # expire or copy
  }))
  default = [
    {
      rule_priority = 1
      description   = "Expire untagged images older than 7 days"
      tag_status    = "untagged"
      count_type    = "sinceImagePushed"
      count_unit    = "days"
      count_number  = 7
      action_type   = "expire"
    },
    {
      rule_priority = 2
      description   = "Keep last 100 tagged images"
      tag_status    = "any"
      count_type    = "imageCountMoreThan"
      count_number  = 100
      action_type   = "expire"
    }
  ]
}

variable "untagged_image_retention_days" {
  description = "DEPRECATED: Use lifecycle_rules instead. Number of days to keep untagged images before expiration."
  type        = number
  default     = null
}

variable "max_image_count" {
  description = "DEPRECATED: Use lifecycle_rules instead. Maximum number of tagged images to keep in the repository."
  type        = number
  default     = null
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
        identifiers = [] # Will be auto-populated with current account root
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
