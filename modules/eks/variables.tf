variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "cluster_version" {
  description = "Kubernetes version to use for the EKS cluster"
  type        = string
  default     = "1.28"
}

variable "vpc_id" {
  description = "VPC ID where the cluster will be deployed"
  type        = string
}

variable "subnet_ids" {
  description = "List of subnet IDs for the EKS cluster"
  type        = list(string)
}

variable "control_plane_subnet_ids" {
  description = "List of subnet IDs for the EKS control plane (if different from worker nodes)"
  type        = list(string)
  default     = []
}

variable "cluster_endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = false
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "List of CIDR blocks that can access the public API server endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_security_group_additional_rules" {
  description = "Additional security group rules for the cluster security group"
  type        = any
  default     = {}
}

variable "node_security_group_additional_rules" {
  description = "Additional security group rules for node security group"
  type        = any
  default     = {}
}

variable "cluster_enabled_log_types" {
  description = "List of control plane logging types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "cloudwatch_log_group_retention_in_days" {
  description = "Number of days to retain log events"
  type        = number
  default     = 90
}

variable "cloudwatch_log_group_kms_key_id" {
  description = "KMS key ID to encrypt CloudWatch logs"
  type        = string
  default     = null
}

variable "cluster_encryption_config" {
  description = "Configuration block with encryption configuration for the cluster"
  type = list(object({
    provider_key_arn = string
    resources        = list(string)
  }))
  default = []
}

variable "enable_irsa" {
  description = "Enable IAM Roles for Service Accounts"
  type        = bool
  default     = true
}

variable "cluster_addons" {
  description = "Map of cluster addon configurations"
  type = map(object({
    version                  = string
    resolve_conflicts        = optional(string, "OVERWRITE")
    service_account_role_arn = optional(string)
    configuration_values     = optional(string)
  }))
  default = {
    vpc-cni = {
      version           = "v1.15.1-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      version           = "v1.10.1-eksbuild.2"
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      version           = "v1.28.1-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
  }
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    desired_size    = number
    min_size        = number
    max_size        = number
    instance_types  = list(string)
    capacity_type   = optional(string, "ON_DEMAND")
    disk_size       = optional(number, 50)
    disk_type       = optional(string, "gp3")
    disk_iops       = optional(number)
    disk_throughput = optional(number)
    ami_type        = optional(string, "AL2_x86_64")
    labels          = optional(map(string), {})
    taints = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
    tags                       = optional(map(string), {})
    subnet_ids                 = optional(list(string))
    use_custom_launch_template = optional(bool, false)
    block_device_mappings      = optional(any)
    metadata_options = optional(object({
      http_endpoint               = string
      http_tokens                 = string
      http_put_response_hop_limit = number
      instance_metadata_tags      = string
    }))
    update_config = optional(object({
      max_unavailable_percentage = optional(number)
      max_unavailable            = optional(number)
    }))
  }))
  default = {}
}

variable "self_managed_node_groups" {
  description = "Map of self-managed node group configurations"
  type        = any
  default     = {}
}

variable "fargate_profiles" {
  description = "Map of Fargate profile configurations"
  type = map(object({
    selectors = list(object({
      namespace = string
      labels    = optional(map(string), {})
    }))
    subnet_ids = optional(list(string))
    tags       = optional(map(string), {})
  }))
  default = {}
}

variable "manage_aws_auth_configmap" {
  description = "Determines whether to manage the aws-auth configmap"
  type        = bool
  default     = true
}

variable "aws_auth_roles" {
  description = "List of role maps to add to the aws-auth configmap"
  type = list(object({
    rolearn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "aws_auth_users" {
  description = "List of user maps to add to the aws-auth configmap"
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))
  default = []
}

variable "aws_auth_accounts" {
  description = "List of account maps to add to the aws-auth configmap"
  type        = list(string)
  default     = []
}

variable "enable_cluster_autoscaler" {
  description = "Enable Cluster Autoscaler IAM role"
  type        = bool
  default     = true
}

variable "enable_ebs_csi_driver" {
  description = "Enable EBS CSI Driver"
  type        = bool
  default     = true
}

variable "enable_efs_csi_driver" {
  description = "Enable EFS CSI Driver"
  type        = bool
  default     = false
}

variable "enable_aws_load_balancer_controller" {
  description = "Enable AWS Load Balancer Controller IAM role"
  type        = bool
  default     = true
}

variable "enable_external_dns" {
  description = "Enable External DNS IAM role"
  type        = bool
  default     = false
}

variable "enable_cert_manager" {
  description = "Enable Cert Manager IAM role"
  type        = bool
  default     = false
}

variable "external_dns_route53_zone_arns" {
  description = "Route53 zone ARNs for External DNS"
  type        = list(string)
  default     = []
}

variable "cert_manager_route53_zone_arns" {
  description = "Route53 zone ARNs for Cert Manager"
  type        = list(string)
  default     = []
}

variable "cluster_security_group_id" {
  description = "Existing security group ID for the cluster (if not creating new one)"
  type        = string
  default     = ""
}

variable "create_cluster_security_group" {
  description = "Whether to create a security group for the cluster"
  type        = bool
  default     = true
}

variable "create_node_security_group" {
  description = "Whether to create a security group for the nodes"
  type        = bool
  default     = true
}

variable "enable_cluster_encryption" {
  description = "Enable encryption of Kubernetes secrets"
  type        = bool
  default     = true
}

variable "kms_key_administrators" {
  description = "List of IAM ARNs for KMS key administrators"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_tags" {
  description = "Additional tags for the cluster"
  type        = map(string)
  default     = {}
}

variable "node_security_group_tags" {
  description = "Additional tags for node security group"
  type        = map(string)
  default     = {}
}

variable "cluster_timeouts" {
  description = "Timeout configuration for cluster operations"
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  default = {}
}

variable "enable_pod_identity" {
  description = "Enable EKS Pod Identity"
  type        = bool
  default     = false
}

variable "authentication_mode" {
  description = "Authentication mode for the cluster (API, API_AND_CONFIG_MAP, or CONFIG_MAP)"
  type        = string
  default     = "API_AND_CONFIG_MAP"
  validation {
    condition     = contains(["API", "API_AND_CONFIG_MAP", "CONFIG_MAP"], var.authentication_mode)
    error_message = "Authentication mode must be API, API_AND_CONFIG_MAP, or CONFIG_MAP."
  }
}

variable "access_entries" {
  description = "Map of access entries to add to the cluster"
  type = map(object({
    kubernetes_groups = optional(list(string))
    principal_arn     = string
    type              = optional(string, "STANDARD")
    policy_associations = optional(map(object({
      policy_arn = string
      access_scope = object({
        type       = string
        namespaces = optional(list(string))
      })
    })), {})
  }))
  default = {}
}
