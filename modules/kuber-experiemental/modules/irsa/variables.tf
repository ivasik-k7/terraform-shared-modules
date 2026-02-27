# ─────────────────────────────────────────────────────────────────────────────
# IRSA Module Variables
# All new variables carry defaults that reproduce the original behaviour,
# keeping the module 100 % backward-compatible.
# ─────────────────────────────────────────────────────────────────────────────

# ── Identity ─────────────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the EKS cluster. Used in the default role description."
  type        = string
}

variable "oidc_provider_arn" {
  description = "Full ARN of the IAM OIDC provider attached to the cluster."
  type        = string
}

variable "oidc_provider_url" {
  description = "Issuer URL of the OIDC provider (with or without https://)."
  type        = string
}

# ── Role creation toggle ──────────────────────────────────────────────────────

variable "create_role" {
  description = <<-EOT
    Whether to create the IAM role.
    Set to false when the role is managed externally and you only want the
    module outputs to reference it (role_arn must be provided in that case).
  EOT
  type        = bool
  default     = true
}

variable "role_arn" {
  description = <<-EOT
    ARN of an existing IAM role to use when create_role = false.
    Ignored when create_role = true.
  EOT
  type        = string
  default     = null
}

# ── Role naming & path ────────────────────────────────────────────────────────

variable "role_name" {
  description = <<-EOT
    Explicit name for the IAM role.
    Mutually exclusive with role_name_prefix; role_name takes precedence.
  EOT
  type        = string
  default     = null
}

variable "role_name_prefix" {
  description = <<-EOT
    Creates a unique name beginning with this prefix.
    Used when role_name is null. AWS appends a random suffix.
  EOT
  type        = string
  default     = null
}

variable "role_path" {
  description = "IAM path for the role. Useful for SCPs and permission boundaries."
  type        = string
  default     = "/"
}

variable "role_description" {
  description = <<-EOT
    Human-readable description attached to the role.
    Defaults to a generated string identifying cluster, namespace, and SA.
  EOT
  type        = string
  default     = null
}

variable "role_permissions_boundary_arn" {
  description = "ARN of an IAM policy to set as the permissions boundary on the role."
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum CLI/API session duration in seconds (900–43200)."
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 900 and 43200 seconds."
  }
}

variable "force_detach_policies" {
  description = "Force-detach all policies when the role is destroyed."
  type        = bool
  default     = true
}

# ── Trust policy – ServiceAccount subjects ───────────────────────────────────

variable "namespace" {
  description = <<-EOT
    Kubernetes namespace for the primary ServiceAccount.
    Kept for backward compatibility. For multi-SA trust use service_accounts.
  EOT
  type        = string
  default     = null
}

variable "service_account" {
  description = <<-EOT
    Kubernetes ServiceAccount name for the primary subject.
    Kept for backward compatibility. For multi-SA trust use service_accounts.
  EOT
  type        = string
  default     = null
}

variable "service_accounts" {
  description = <<-EOT
    List of Kubernetes {namespace, service_account} pairs trusted by this role.
    Merged with namespace/service_account for backward compatibility.
    Supports wildcard "*" in either field when use_wildcard_subject = true.
  EOT
  type = list(object({
    namespace       = string
    service_account = string
  }))
  default = []
}

variable "use_wildcard_subject" {
  description = <<-EOT
    When true, the OIDC :sub condition uses StringLike instead of StringEquals,
    enabling wildcard matching (e.g. namespace="*" or service_account="*").
    Keep false for least-privilege single-SA bindings.
  EOT
  type        = bool
  default     = false
}

# ── Trust policy – additional statements ─────────────────────────────────────

variable "additional_trust_statements" {
  description = <<-EOT
    Raw IAM policy statement objects appended to the trust policy.
    Allows cross-account AssumeRole or CI/CD runner trust alongside IRSA.
    Each element must be a valid aws_iam_policy_document statement block
    expressed as a JSON string.
  EOT
  type        = list(string)
  default     = []
}

# ── Policies ──────────────────────────────────────────────────────────────────

variable "policy_arns" {
  description = "List of managed IAM policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}

variable "inline_policies" {
  description = "Map of inline policy name → JSON policy document to embed in the role."
  type        = map(string)
  default     = {}
}

# ── FinOps / tagging ──────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to the IAM role for cost allocation and governance."
  type        = map(string)
  default     = {}
}
