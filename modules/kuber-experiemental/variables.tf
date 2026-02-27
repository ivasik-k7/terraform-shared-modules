variable "cluster_name" {
  description = "Name of the EKS cluster. Used as a prefix for all related resources."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.30"
}

variable "environment" {
  description = "Environment label (dev / staging / prod). Propagated as a tag and FinOps label."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Additional tags merged onto every resource created by this module."
  type        = map(string)
  default     = {}
}


# ── Networking ────────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "ID of the VPC where the cluster will live."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for worker nodes and (by default) control-plane ENIs. Typically private subnets."
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "Subnets used exclusively for control-plane cross-account ENIs. Defaults to subnet_ids."
  type        = list(string)
  default     = []
}

# ── API endpoint access ───────────────────────────────────────────────────────

variable "cluster_endpoint_public_access" {
  description = "Enable public access to the Kubernetes API server endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_private_access" {
  description = "Enable private (VPC-internal) access to the Kubernetes API server endpoint."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Restrict to corporate egress IPs in production."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ── Logging ───────────────────────────────────────────────────────────────────

variable "cluster_enabled_log_types" {
  description = "Control-plane log types to ship to CloudWatch."
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention period (days) for CloudWatch control-plane logs."
  type        = number
  default     = 90
}

# ── Encryption ────────────────────────────────────────────────────────────────

variable "create_kms_key" {
  description = "Create a dedicated KMS key for Kubernetes secrets encryption."
  type        = bool
  default     = true
}

variable "kms_key_arn" {
  description = "ARN of an existing KMS key. Used when create_kms_key = false."
  type        = string
  default     = null
}

variable "kms_key_deletion_window_in_days" {
  description = "KMS key deletion window (days)."
  type        = number
  default     = 30
}

# ── Node groups ───────────────────────────────────────────────────────────────

variable "node_groups" {
  description = <<-EOT
    Map of managed node group definitions. Key = logical name.
    All fields are optional and carry defaults that match the original API,
    keeping existing callers fully backward-compatible.
  EOT
  type = map(object({
    # Compute
    instance_types  = optional(list(string), ["m6i.large"])
    capacity_type   = optional(string, "ON_DEMAND")
    ami_type        = optional(string, "AL2_x86_64")
    release_version = optional(string, null)

    # Scaling
    min_size     = optional(number, 1)
    max_size     = optional(number, 5)
    desired_size = optional(number, 2)

    # Networking
    subnet_ids = optional(list(string), [])

    # Launch Template
    create_launch_template = optional(bool, true)
    disk_size              = optional(number, 50)
    disk_type              = optional(string, "gp3")
    disk_iops              = optional(number, null)
    disk_throughput        = optional(number, null)
    disk_encrypted         = optional(bool, true)
    disk_kms_key_id        = optional(string, null)
    imdsv2_hop_limit       = optional(number, 2)

    # Bootstrap hooks
    bootstrap_extra_args     = optional(string, "")
    pre_bootstrap_user_data  = optional(string, "")
    post_bootstrap_user_data = optional(string, "")

    # Monitoring
    enable_detailed_monitoring = optional(bool, false)

    # Kubernetes metadata
    labels = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = optional(string)
      effect = string
    })), [])

    # FinOps – Warm Pool
    enable_warm_pool                = optional(bool, false)
    warm_pool_state                 = optional(string, "Stopped")
    warm_pool_min_size              = optional(number, 0)
    warm_pool_max_prepared_capacity = optional(number, null)
    warm_pool_instance_reuse_policy = optional(bool, true)

    # FinOps – Scheduled scaling
    scheduled_scaling_actions = optional(map(object({
      recurrence   = string
      min_size     = optional(number)
      max_size     = optional(number)
      desired_size = optional(number)
      start_time   = optional(string)
      end_time     = optional(string)
      time_zone    = optional(string, "UTC")
    })), {})

    # Extra tags
    tags = optional(map(string), {})
  }))
  default = {
    default = {}
  }
}

# ── EKS add-ons ───────────────────────────────────────────────────────────────

variable "cluster_addons" {
  description = "Map of EKS managed add-ons. Key = addon name."
  type = map(object({
    addon_version               = optional(string, null)
    resolve_conflicts_on_create = optional(string, "OVERWRITE")
    resolve_conflicts_on_update = optional(string, "OVERWRITE")
    service_account_role_arn    = optional(string, null)
    configuration_values        = optional(string, null)
    preserve                    = optional(bool, false)
  }))
  default = {
    coredns            = {}
    kube-proxy         = {}
    vpc-cni            = {}
    aws-ebs-csi-driver = {}
  }
}

# ── IRSA – built-in toggles ───────────────────────────────────────────────────

variable "enable_irsa_aws_load_balancer_controller" {
  type    = bool
  default = true
}

variable "enable_irsa_cluster_autoscaler" {
  type    = bool
  default = true
}

variable "enable_irsa_external_dns" {
  type    = bool
  default = false
}

variable "enable_irsa_ebs_csi_driver" {
  type    = bool
  default = true
}

variable "enable_irsa_external_secrets" {
  type    = bool
  default = false
}

# ── IRSA – custom roles ───────────────────────────────────────────────────────

variable "irsa_roles" {
  description = "Arbitrary IRSA roles to create. Key = logical name used in outputs."
  type = map(object({
    namespace       = string
    service_account = string
    policy_arns     = optional(list(string), [])
    inline_policies = optional(map(string), {})
  }))
  default = {}
}

# ── Authentication mode ───────────────────────────────────────────────────────

variable "auth_mode" {
  description = <<-EOT
    Cluster authentication mode.
    CONFIG_MAP          – legacy aws-auth ConfigMap only (default; always works)
    API                 – EKS Access Entries only (recommended for new clusters ≥ 1.23)
    API_AND_CONFIG_MAP  – both; use during migration from CONFIG_MAP → API
  EOT
  type        = string
  default     = "CONFIG_MAP"

  validation {
    condition     = contains(["CONFIG_MAP", "API", "API_AND_CONFIG_MAP"], var.auth_mode)
    error_message = "auth_mode must be CONFIG_MAP, API, or API_AND_CONFIG_MAP."
  }
}

# ── aws-auth ConfigMap entries ────────────────────────────────────────────────

variable "aws_auth_roles" {
  description = "IAM roles to add to the aws-auth ConfigMap (used when auth_mode includes CONFIG_MAP)."
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "aws_auth_users" {
  description = "IAM users to add to the aws-auth ConfigMap."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

# ── EKS Access Entries ────────────────────────────────────────────────────────

variable "access_entries" {
  description = <<-EOT
    IAM principals to register as EKS Access Entries (used when auth_mode includes API).
    For GitLab CI/CD runners use type = "STANDARD" and supply an access_policy_arn.
  EOT
  type = list(object({
    principal_arn           = string
    type                    = optional(string, "STANDARD") # STANDARD | EC2_LINUX | EC2_WINDOWS | FARGATE_LINUX
    kubernetes_groups       = optional(list(string), [])
    access_policy_arn       = optional(string, null)      # e.g. arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy
    access_scope_type       = optional(string, "cluster") # cluster | namespace
    access_scope_namespaces = optional(list(string), [])
  }))
  default = []
}
