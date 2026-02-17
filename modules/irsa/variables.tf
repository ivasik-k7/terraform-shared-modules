# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------
variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_oidc_issuer_url" {
  description = "The URL of the OpenID Connect identity provider for the EKS cluster"
  type        = string
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account"
  type        = string
}

# -----------------------------------------------------------------------------
# OIDC Configuration
# -----------------------------------------------------------------------------
variable "oidc_provider_arn" {
  description = "ARN of the OIDC provider. If not provided, will be constructed from cluster_oidc_issuer_url"
  type        = string
  default     = null
}

variable "oidc_provider_url" {
  description = "URL of the OIDC provider without https://. If not provided, will be extracted from cluster_oidc_issuer_url"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Service Account Configuration
# -----------------------------------------------------------------------------
variable "service_account_namespace" {
  description = "Kubernetes namespace for the service account. Either this or service_account_namespaces must be set"
  type        = string
  default     = null
}

variable "service_account_namespaces" {
  description = "List of Kubernetes namespaces for the service account. Use this for multi-namespace access"
  type        = list(string)
  default     = null
}

variable "create_service_account" {
  description = "Whether to create the Kubernetes service account"
  type        = bool
  default     = false
}

variable "service_account_labels" {
  description = "Additional labels for the service account"
  type        = map(string)
  default     = {}
}

variable "service_account_annotations" {
  description = "Additional annotations for the service account"
  type        = map(string)
  default     = {}
}

variable "service_account_image_pull_secrets" {
  description = "List of image pull secrets to attach to the service account"
  type        = list(string)
  default     = []
}

variable "automount_service_account_token" {
  description = "Whether to automatically mount the service account token"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# IAM Role Configuration
# -----------------------------------------------------------------------------
variable "create_role" {
  description = "Whether to create the IAM role"
  type        = bool
  default     = true
}

variable "existing_role_arn" {
  description = "ARN of an existing IAM role to use instead of creating a new one"
  type        = string
  default     = null
}

variable "role_name" {
  description = "Name of the IAM role. If not provided, will be generated as {cluster_name}-{service_account_name}-irsa"
  type        = string
  default     = null
}

variable "use_name_prefix" {
  description = "Whether to use name_prefix instead of name for IAM resources"
  type        = bool
  default     = false
}

variable "role_path" {
  description = "Path for the IAM role"
  type        = string
  default     = "/"
}

variable "role_description" {
  description = "Description of the IAM role"
  type        = string
  default     = null
}

variable "max_session_duration" {
  description = "Maximum session duration (in seconds) for the IAM role"
  type        = number
  default     = 3600

  validation {
    condition     = var.max_session_duration >= 3600 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 3600 (1 hour) and 43200 (12 hours)."
  }
}

variable "role_permissions_boundary_arn" {
  description = "ARN of the permissions boundary to attach to the IAM role"
  type        = string
  default     = null
}

variable "force_detach_policies" {
  description = "Whether to force detach policies when destroying the IAM role"
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Trust Policy Configuration
# -----------------------------------------------------------------------------
variable "assume_role_condition_test" {
  description = "The condition test to use in the assume role policy. Use 'StringEquals' for stricter validation or 'StringLike' for wildcard support"
  type        = string
  default     = "StringEquals"

  validation {
    condition     = contains(["StringEquals", "StringLike"], var.assume_role_condition_test)
    error_message = "assume_role_condition_test must be either 'StringEquals' or 'StringLike'."
  }
}

variable "additional_assume_role_statements" {
  description = <<-EOT
    Additional statements to add to the assume role policy. Each statement should be a map with:
    - effect: (optional) Effect of the statement, defaults to 'Allow'
    - actions: List of actions
    - principals: List of principal maps with 'type' and 'identifiers'
    - conditions: (optional) List of condition maps with 'test', 'variable', and 'values'
  EOT
  type        = list(any)
  default     = []
}

# -----------------------------------------------------------------------------
# Policy Attachments
# -----------------------------------------------------------------------------
variable "policy_arns" {
  description = "List of IAM policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Custom Inline Policy
# -----------------------------------------------------------------------------
variable "policy_statements" {
  description = <<-EOT
    List of IAM policy statements to create as an inline policy. Each statement should be a map with:
    - sid: (optional) Statement ID
    - effect: (optional) Effect of the statement, defaults to 'Allow'
    - actions: List of actions
    - resources: (optional) List of resources, defaults to ['*']
    - conditions: (optional) List of condition maps with 'test', 'variable', and 'values'
  EOT
  type        = list(any)
  default     = null
}

variable "custom_policy_name" {
  description = "Name for the custom inline policy. If not provided, will be generated"
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Pre-built AWS Managed Policies
# -----------------------------------------------------------------------------
variable "attach_ebs_csi_policy" {
  description = "Whether to attach the AWS managed EBS CSI Driver policy"
  type        = bool
  default     = false
}

variable "attach_efs_csi_policy" {
  description = "Whether to attach the AWS managed EFS CSI Driver policy"
  type        = bool
  default     = false
}

variable "attach_vpc_cni_policy" {
  description = "Whether to attach the AWS managed VPC CNI policy"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Pre-built Custom Policies
# -----------------------------------------------------------------------------
variable "attach_cluster_autoscaler_policy" {
  description = "Whether to attach the Cluster Autoscaler policy"
  type        = bool
  default     = false
}

variable "attach_alb_controller_policy" {
  description = "Whether to attach the AWS Load Balancer Controller policy"
  type        = bool
  default     = false
}

variable "attach_external_dns_policy" {
  description = "Whether to attach the External DNS policy"
  type        = bool
  default     = false
}

variable "external_dns_hosted_zone_arns" {
  description = "List of Route53 hosted zone ARNs that External DNS can manage. If not provided, allows all hosted zones"
  type        = list(string)
  default     = null
}

variable "attach_cert_manager_policy" {
  description = "Whether to attach the Cert Manager policy"
  type        = bool
  default     = false
}

variable "cert_manager_hosted_zone_arns" {
  description = "List of Route53 hosted zone ARNs that Cert Manager can manage. If not provided, allows all hosted zones"
  type        = list(string)
  default     = null
}

variable "attach_external_secrets_policy" {
  description = "Whether to attach the External Secrets Operator policy"
  type        = bool
  default     = false
}

variable "external_secrets_secrets_manager_arns" {
  description = "List of Secrets Manager secret ARNs that External Secrets can access. If not provided, allows all secrets"
  type        = list(string)
  default     = null
}

variable "external_secrets_ssm_parameter_arns" {
  description = "List of SSM Parameter Store ARNs that External Secrets can access. If not provided, allows all parameters"
  type        = list(string)
  default     = null
}

variable "external_secrets_kms_key_arns" {
  description = "List of KMS key ARNs for decrypting secrets in External Secrets"
  type        = list(string)
  default     = null
}

# -----------------------------------------------------------------------------
# Tags
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
