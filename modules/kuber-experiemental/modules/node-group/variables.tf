# ── Feature toggles ───────────────────────────────────────────────────────────

variable "create_node_group" {
  description = "Master switch. Set to false to disable the node group without removing the module."
  type        = bool
  default     = true
}

variable "create_iam_role" {
  description = <<-EOT
    Create the IAM node role automatically.
    Set to false and provide iam_role_arn to bring your own role (e.g. shared
    across node groups for fewer IAM entities).
  EOT
  type        = bool
  default     = true
}

variable "create_launch_template" {
  description = <<-EOT
    Create a Launch Template for the node group.
    Enables IMDSv2, EBS encryption, custom bootstrap, detailed monitoring, etc.
    When false, all launch_template_* variables are ignored and EKS uses its
    default configuration (backward-compatible path).
  EOT
  type        = bool
  default     = true
}

# ── Cluster identity ──────────────────────────────────────────────────────────

variable "cluster_name" {
  description = "Name of the EKS cluster this node group belongs to."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the node group AMI. Must match or be one minor below the control plane."
  type        = string
}

# ── Node group naming ─────────────────────────────────────────────────────────

variable "node_group_name" {
  description = <<-EOT
    Logical name used as a suffix in the full node group name.
    Full name = <cluster_name>-<node_group_name>.
  EOT
  type        = string
}

variable "node_group_name_prefix" {
  description = <<-EOT
    When set, a random suffix is appended to allow zero-downtime replacement.
    Mutually exclusive with node_group_name (name_prefix is preferred for
    immutable rolling updates). When null, node_group_name is used as-is.
  EOT
  type        = string
  default     = null
}

# ── Networking ────────────────────────────────────────────────────────────────

variable "subnet_ids" {
  description = "Subnets where worker nodes are launched. Typically private subnets."
  type        = list(string)
}

variable "node_security_group_ids" {
  description = "Additional security group IDs to attach to every node."
  type        = list(string)
  default     = []
}

# ── Compute ───────────────────────────────────────────────────────────────────

variable "instance_types" {
  description = <<-EOT
    Ordered list of EC2 instance types. EKS picks from this list when
    launching nodes. Provide multiple types for Spot diversity.
  EOT
  type        = list(string)
  default     = ["m6i.large"]
}

variable "capacity_type" {
  description = "ON_DEMAND or SPOT. SPOT reduces cost 60-80 % for fault-tolerant workloads."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.capacity_type)
    error_message = "capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "ami_type" {
  description = <<-EOT
    EKS-optimised AMI family.
    AL2_x86_64 | AL2_ARM_64 | AL2_x86_64_GPU |
    BOTTLEROCKET_x86_64 | BOTTLEROCKET_ARM_64 |
    WINDOWS_CORE_2022_x86_64 | CUSTOM
  EOT
  type        = string
  default     = "AL2_x86_64"
}

variable "release_version" {
  description = <<-EOT
    AMI release version (e.g. 1.30.0-20240522). Null = latest.
    Pin this in production to prevent unexpected AMI changes on scale-out.
  EOT
  type        = string
  default     = null
}

# ── Scaling ───────────────────────────────────────────────────────────────────

variable "min_size" {
  description = "Minimum number of nodes."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of nodes."
  type        = number
  default     = 5
}

variable "desired_size" {
  description = "Initial desired node count. Ignored after first apply (managed by CA)."
  type        = number
  default     = 2
}

# ── Update config ─────────────────────────────────────────────────────────────

variable "update_config_max_unavailable" {
  description = <<-EOT
    Absolute count of nodes that can be unavailable during a rolling update.
    Mutually exclusive with update_config_max_unavailable_percentage.
    Leave null to use the percentage-based setting.
  EOT
  type        = number
  default     = null
}

variable "update_config_max_unavailable_percentage" {
  description = <<-EOT
    Percentage of nodes that can be unavailable during a rolling update (1–100).
    Used when update_config_max_unavailable is null.
  EOT
  type        = number
  default     = 33
}

variable "force_update_version" {
  description = "Force an update even if the existing nodes are on the target version."
  type        = bool
  default     = false
}

# ── Storage ───────────────────────────────────────────────────────────────────

variable "disk_size" {
  description = <<-EOT
    Root EBS volume size in GiB.
    When create_launch_template = true this is set on the Launch Template and
    the EKS node group disk_size attribute is left unset (they are mutually
    exclusive). When create_launch_template = false it is passed directly.
  EOT
  type        = number
  default     = 50
}

variable "disk_type" {
  description = "EBS volume type: gp3 (recommended), gp2, io1, io2."
  type        = string
  default     = "gp3"
}

variable "disk_iops" {
  description = "Provisioned IOPS for io1/io2/gp3. Null = AWS default (3000 for gp3)."
  type        = number
  default     = null
}

variable "disk_throughput" {
  description = "Throughput in MiB/s for gp3 volumes (125–1000). Null = AWS default (125)."
  type        = number
  default     = null
}

variable "disk_encrypted" {
  description = "Encrypt the root EBS volume."
  type        = bool
  default     = true
}

variable "disk_kms_key_id" {
  description = "KMS key ID/ARN for EBS encryption. Null = AWS-managed key (alias/aws/ebs)."
  type        = string
  default     = null
}

# ── Launch Template extras ────────────────────────────────────────────────────

variable "imdsv2_hop_limit" {
  description = <<-EOT
    IMDSv2 HTTP PUT response hop limit.
    1 = containers cannot reach IMDS (most secure, breaks anything that
        reads EC2 metadata from within a pod).
    2 = containers can reach IMDS (needed for pod-level AWS SDK calls that
        don't use IRSA). Recommended: 1 when IRSA is used everywhere.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.imdsv2_hop_limit >= 1 && var.imdsv2_hop_limit <= 64
    error_message = "imdsv2_hop_limit must be between 1 and 64."
  }
}

variable "enable_detailed_monitoring" {
  description = <<-EOT
    Enable 1-minute CloudWatch detailed monitoring on every instance.
    Costs ~$3.50 /instance/month but is required for sub-5-minute autoscaling
    reaction times with EC2 metrics. FinOps note: disable in dev to save cost.
  EOT
  type        = bool
  default     = false
}

variable "bootstrap_extra_args" {
  description = <<-EOT
    Extra arguments appended to the EKS bootstrap.sh script.
    Only applies to AL2-based AMI types (not Bottlerocket/Windows).
    Example: "--kubelet-extra-args '--max-pods=110 --node-labels=role=worker'"
  EOT
  type        = string
  default     = ""
}

variable "pre_bootstrap_user_data" {
  description = <<-EOT
    Shell script fragment executed BEFORE the EKS bootstrap on AL2 nodes.
    Useful for mounting extra EBS volumes, setting sysctl params, etc.
  EOT
  type        = string
  default     = ""
}

variable "post_bootstrap_user_data" {
  description = <<-EOT
    Shell script fragment executed AFTER the EKS bootstrap on AL2 nodes.
    Useful for registering with monitoring agents, custom labelling, etc.
  EOT
  type        = string
  default     = ""
}

variable "placement_group_strategy" {
  description = <<-EOT
    EC2 placement group strategy: cluster | partition | spread | null.
    cluster  – low-latency networking (HPC); single AZ, single-point-of-failure risk.
    spread   – max fault isolation; at most 7 instances per AZ per group.
    partition– rack-level isolation for HDFS-style workloads.
    null     – no placement group (default).
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.placement_group_strategy == null || contains(["cluster", "partition", "spread"], var.placement_group_strategy)
    error_message = "placement_group_strategy must be cluster, partition, spread, or null."
  }
}

variable "launch_template_tags" {
  description = "Extra tags applied only to the Launch Template resource itself."
  type        = map(string)
  default     = {}
}

# ── Remote access (SSH) ───────────────────────────────────────────────────────

variable "remote_access_ec2_ssh_key" {
  description = <<-EOT
    Name of an EC2 key pair for SSH access to nodes.
    Requires create_launch_template = false (remote_access block is mutually
    exclusive with launch templates). Leave null to disable SSH access.
  EOT
  type        = string
  default     = null
}

variable "remote_access_source_security_group_ids" {
  description = "Security group IDs allowed to SSH to the nodes."
  type        = list(string)
  default     = []
}

# ── K8s metadata ─────────────────────────────────────────────────────────────

variable "labels" {
  description = "Kubernetes node labels applied to every node in this group."
  type        = map(string)
  default     = {}
}

variable "taints" {
  description = "Kubernetes node taints applied to every node in this group."
  type = list(object({
    key    = string
    value  = optional(string)
    effect = string # NO_SCHEDULE | NO_EXECUTE | PREFER_NO_SCHEDULE
  }))
  default = []
}

# ── IAM – bring your own ──────────────────────────────────────────────────────

variable "iam_role_arn" {
  description = "ARN of an existing node IAM role. Used when create_iam_role = false."
  type        = string
  default     = null
}

variable "iam_role_name" {
  description = <<-EOT
    Override the auto-generated node IAM role name.
    Useful to keep names short when cluster_name is long.
  EOT
  type        = string
  default     = null
}

variable "iam_role_additional_policies" {
  description = <<-EOT
    Map of extra managed policy ARNs to attach to the node role.
    Key = logical name (appears in plan), value = policy ARN.
    Example: { cloudwatch_agent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
  EOT
  type        = map(string)
  default     = {}
}

# ── FinOps – Warm Pool ────────────────────────────────────────────────────────

variable "enable_warm_pool" {
  description = <<-EOT
    Enable an EC2 Auto Scaling Warm Pool for this node group.
    Warm pools pre-initialise instances so they can join the cluster in seconds
    instead of minutes – eliminating scale-out latency spikes.
    FinOps: instances in the warm pool incur stopped-instance EBS cost only
    (no compute) when pool_state = "Stopped". Use "Running" for instant-on at
    higher cost. See warm_pool_* variables for full configuration.
  EOT
  type        = bool
  default     = false
}

variable "warm_pool_state" {
  description = <<-EOT
    State of warm-pool instances while waiting:
    Stopped – cheapest; ~5-10 s extra start time.
    Running – costlier; sub-second join (near-zero latency).
    Hibernated – balance; requires hibernation-compatible AMI.
  EOT
  type        = string
  default     = "Stopped"

  validation {
    condition     = contains(["Stopped", "Running", "Hibernated"], var.warm_pool_state)
    error_message = "warm_pool_state must be Stopped, Running, or Hibernated."
  }
}

variable "warm_pool_min_size" {
  description = "Minimum number of instances to keep in the warm pool at all times."
  type        = number
  default     = 0
}

variable "warm_pool_max_prepared_capacity" {
  description = <<-EOT
    Maximum total prepared capacity (warm + running).
    Null = warm pool grows up to the ASG max_size.
  EOT
  type        = number
  default     = null
}

variable "warm_pool_instance_reuse_policy" {
  description = <<-EOT
    Whether scale-in events return instances to the warm pool (true) or
    terminate them (false). Return-to-pool is cheaper for spiky workloads.
  EOT
  type        = bool
  default     = true
}

# ── FinOps – Scheduled scaling ────────────────────────────────────────────────

variable "scheduled_scaling_actions" {
  description = <<-EOT
    Map of scheduled Auto Scaling actions for cost-optimised scale-down.
    Key = action name, value = configuration.

    Example – scale to zero on weeknights and back up on weekday mornings:
    {
      scale-down-night = {
        recurrence   = "0 20 * * MON-FRI"  # 20:00 UTC
        min_size     = 0
        max_size     = 0
        desired_size = 0
      }
      scale-up-morning = {
        recurrence   = "0 6 * * MON-FRI"   # 06:00 UTC
        min_size     = 1
        max_size     = 5
        desired_size = 2
      }
    }

    FinOps: scheduling dev/staging clusters to zero outside business hours
    typically saves 60-65 % on EC2 node costs with zero manual effort.
  EOT
  type = map(object({
    recurrence   = string # cron expression (UTC)
    min_size     = optional(number)
    max_size     = optional(number)
    desired_size = optional(number)
    start_time   = optional(string) # ISO 8601; null = immediately
    end_time     = optional(string) # ISO 8601; null = no end
    time_zone    = optional(string, "UTC")
  }))
  default = {}
}

# ── Tagging ───────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}
