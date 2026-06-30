################################################################################
# General
################################################################################

variable "create" {
  description = "Master switch. When false the module creates nothing (useful for conditional stacks)."
  type        = bool
  default     = true
}

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

  validation {
    condition     = length(var.repository_name) >= 2 && length(var.repository_name) <= 256
    error_message = "Repository name must be between 2 and 256 characters."
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
  description = "Lifecycle policy rules. action_type is always \"expire\" (the only ECR action). tag_status: tagged|untagged|any. count_type: imageCountMoreThan|sinceImagePushed."
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

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : contains(["tagged", "untagged", "any"], r.tag_status)])
    error_message = "lifecycle_rules[*].tag_status must be one of: tagged, untagged, any."
  }

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : contains(["imageCountMoreThan", "sinceImagePushed"], r.count_type)])
    error_message = "lifecycle_rules[*].count_type must be imageCountMoreThan or sinceImagePushed."
  }

  validation {
    condition     = alltrue([for r in var.lifecycle_rules : r.action_type == "expire"])
    error_message = "lifecycle_rules[*].action_type must be \"expire\" (the only action ECR supports)."
  }

  validation {
    condition     = length(distinct([for r in var.lifecycle_rules : r.rule_priority])) == length(var.lifecycle_rules)
    error_message = "lifecycle_rules[*].rule_priority values must be unique."
  }

  # ECR requires a "tagged" rule to scope itself with a prefix or pattern list.
  validation {
    condition     = alltrue([for r in var.lifecycle_rules : r.tag_status != "tagged" || length(r.tag_prefix_list) > 0 || length(r.tag_pattern_list) > 0])
    error_message = "A lifecycle rule with tag_status = \"tagged\" must set tag_prefix_list or tag_pattern_list."
  }
}

################################################################################
# Repository Access Control - ONE knob: repository_access
################################################################################
#
# The whole resource-policy story in a single object:
#
#   repository_access = {
#     enabled         = true                 # attach a resource policy at all
#     account_access  = true                 # secure baseline: own account pull/push,
#                                             #   NO destructive/admin actions
#     pull_principals = ["arn:aws:iam::333:root"]          # cross-account pull-only
#     push_principals = ["arn:aws:iam::222:role/ci"]       # cross-account pull+push
#     statements      = [ { ...raw escape hatch... } ]     # layered on top
#   }
#
# Sensible everywhere: `repository_access = {}` gives the secure baseline only.
# Set account_access=false for full manual control; enabled=false for no policy.

variable "repository_access" {
  description = "Single object that manages the entire repository resource policy: enabled, account_access (secure baseline), pull_principals, push_principals, and a raw statements escape hatch layered on top."
  type = object({
    enabled         = optional(bool, true)
    account_access  = optional(bool, true)
    pull_principals = optional(list(string), [])
    push_principals = optional(list(string), [])
    statements = optional(list(object({
      sid    = string
      effect = optional(string, "Allow")
      principals = optional(object({
        type        = optional(string, "AWS")
        identifiers = list(string)
      }), null)
      actions   = list(string)
      resources = optional(list(string), null)
      conditions = optional(list(object({
        test     = string
        variable = string
        values   = list(string)
      })), [])
    })), [])
  })
  default = {}

  validation {
    condition     = alltrue([for s in var.repository_access.statements : contains(["Allow", "Deny"], s.effect)])
    error_message = "repository_access.statements[*].effect must be \"Allow\" or \"Deny\"."
  }

  validation {
    condition     = alltrue([for s in var.repository_access.statements : length(s.actions) > 0])
    error_message = "repository_access.statements[*].actions must be non-empty."
  }

  validation {
    condition     = alltrue([for s in var.repository_access.statements : alltrue([for a in s.actions : a == "*" || can(regex("^ecr:", a))])])
    error_message = "repository_access.statements[*].actions must be ECR actions (ecr:*) or \"*\"."
  }
}

################################################################################
# DEPRECATED access inputs - still honored (merged into repository_access) for
# backward compatibility. Prefer repository_access; these will be removed in a
# future major version.
################################################################################

variable "create_repository_policy" {
  description = "DEPRECATED - use repository_access.enabled. Still honored: ANDed with repository_access.enabled."
  type        = bool
  default     = true
}

variable "repository_policy_statements" {
  description = "DEPRECATED - use repository_access.statements. Still honored: concatenated onto repository_access.statements."
  type = list(object({
    sid    = string
    effect = optional(string, "Allow")
    principals = optional(object({
      type        = optional(string, "AWS")
      identifiers = list(string)
    }), null)
    actions   = list(string)
    resources = optional(list(string), null)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []

  validation {
    condition     = alltrue([for s in var.repository_policy_statements : contains(["Allow", "Deny"], s.effect)])
    error_message = "repository_policy_statements[*].effect must be \"Allow\" or \"Deny\"."
  }
}

variable "allowed_principals" {
  description = "DEPRECATED - use repository_access.push_principals. Still honored: merged in. Principals with pull/push access."
  type        = list(string)
  default     = []
}

variable "allowed_pull_principals" {
  description = "DEPRECATED - use repository_access.pull_principals. Still honored: merged in. Principals with pull-only access."
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
  description = "Tags applied to the repository and all related resources. This is the canonical tag input; it is merged over common_tags (tags wins on conflicts)."
  type        = map(string)
  default     = {}
}

variable "common_tags" {
  description = "DEPRECATED - use tags. Kept for backward compatibility; merged underneath tags. Will be removed in a future major version."
  type        = map(string)
  default     = {}
}
