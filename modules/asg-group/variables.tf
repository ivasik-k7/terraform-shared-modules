# ============================================================================
# GENERAL
# ============================================================================

variable "create" {
  description = "Master switch. When false the module creates nothing."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for the launch template, ASG, IAM role, and security group."
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be 1-64 characters (it prefixes the LT/ASG/SG/IAM resources)."
  }
}

variable "tags" {
  description = "Tags applied to every resource (launch template, IAM, SG) and propagated to instances."
  type        = map(string)
  default     = {}
}

variable "autoscaling_group_tags" {
  description = "Extra tags set on the ASG only (propagated to instances). Use for fleet markers like { AmazonECSManaged = \"\" } or { \"k8s.io/cluster-autoscaler/enabled\" = \"true\" }."
  type        = map(string)
  default     = {}
}

# ============================================================================
# PLACEMENT
# ============================================================================

variable "subnet_ids" {
  description = "Subnet IDs the ASG launches into (vpc_zone_identifier)."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID for the managed security group. Required when create_security_group is true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
  }
}

variable "availability_zones" {
  description = "AZs for the ASG. Usually leave null and let subnet_ids decide placement. Mutually exclusive with subnet_ids."
  type        = list(string)
  default     = null

  validation {
    condition     = var.availability_zones == null || length(var.subnet_ids) == 0
    error_message = "Set either subnet_ids (recommended) or availability_zones, not both."
  }
}

# ============================================================================
# IMAGE / INSTANCE
# ============================================================================

variable "ami" {
  description = "AMI ID. When null, resolved from ami_ssm_parameter. One of the two is required."
  type        = string
  default     = null

  validation {
    condition     = var.ami == null || can(regex("^ami-[0-9a-f]+$", var.ami))
    error_message = "ami must be a valid AMI id (ami-...)."
  }
}

variable "ami_ssm_parameter" {
  description = "SSM parameter that resolves to an AMI ID (e.g. the Amazon Linux 2023 or ECS-optimized recommended image). Used when ami is null."
  type        = string
  default     = null
}

variable "instance_type" {
  description = "Instance type (single-type ASG, or the first override when spot/instance_types is set)."
  type        = string
  default     = "t3.medium"
}

variable "instance_types" {
  description = "Optional list of instance types for a mixed-instances policy. Empty falls back to [instance_type]."
  type        = list(string)
  default     = []
}

variable "instance_weights" {
  description = "Optional per-instance-type weighted_capacity for the mixed-instances policy, e.g. { \"m6i.2xlarge\" = 4, \"m6i.large\" = 1 }. Types not listed get no weight."
  type        = map(number)
  default     = {}
}

variable "key_name" {
  description = "EC2 key pair to attach. Prefer SSM Session Manager over SSH keys."
  type        = string
  default     = null
}

variable "user_data" {
  description = "Plain-text user data (the module base64-encodes it). Conflicts with user_data_base64. Sensitive."
  type        = string
  default     = null
  sensitive   = true
}

variable "user_data_base64" {
  description = "Pre-encoded user data for binary payloads. Conflicts with user_data. Sensitive."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.user_data == null || var.user_data_base64 == null
    error_message = "Set only one of user_data or user_data_base64."
  }
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed (1-minute) EC2 CloudWatch monitoring on the instances (extra cost). Distinct from the create_cloudwatch_alarms / alarm_* inputs."
  type        = bool
  default     = false
}

variable "ebs_optimized" {
  description = "EBS-optimized. Null = instance-type default."
  type        = bool
  default     = null
}

variable "metadata_hop_limit" {
  description = "IMDS hop limit. 2 lets containerized workloads reach instance metadata through the host."
  type        = number
  default     = 1

  validation {
    condition     = var.metadata_hop_limit >= 1 && var.metadata_hop_limit <= 64
    error_message = "metadata_hop_limit must be between 1 and 64."
  }
}

variable "metadata_tags_enabled" {
  description = "Expose instance tags via IMDS (instance_metadata_tags)."
  type        = bool
  default     = false
}

# ============================================================================
# PLACEMENT / TENANCY (advanced)
# ============================================================================

variable "placement_group" {
  description = "Placement group name for the instances."
  type        = string
  default     = null
}

variable "tenancy" {
  description = "Instance tenancy: 'default', 'dedicated', or 'host'."
  type        = string
  default     = null

  validation {
    condition     = var.tenancy == null || contains(["default", "dedicated", "host"], var.tenancy)
    error_message = "tenancy must be 'default', 'dedicated', or 'host'."
  }
}

variable "cpu_options" {
  description = "CPU options: core_count, threads_per_core (1 disables hyperthreading)."
  type = object({
    core_count       = optional(number)
    threads_per_core = optional(number)
  })
  default = null
}

# ============================================================================
# STORAGE
# ============================================================================

variable "root_volume_size" {
  description = "Root volume size (GiB)."
  type        = number
  default     = 30
}

variable "root_volume_type" {
  description = "Root volume type."
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_type must be one of gp2, gp3, io1, io2."
  }
}

variable "root_volume_iops" {
  description = "Root volume IOPS (io1/io2/gp3)."
  type        = number
  default     = null

  validation {
    condition     = var.root_volume_iops == null || contains(["gp3", "io1", "io2"], var.root_volume_type)
    error_message = "root_volume_iops is only valid for gp3, io1, or io2 volumes."
  }
}

variable "root_volume_throughput" {
  description = "Root volume throughput in MiB/s (gp3)."
  type        = number
  default     = null

  validation {
    condition     = var.root_volume_throughput == null || var.root_volume_type == "gp3"
    error_message = "root_volume_throughput is only valid for gp3 volumes."
  }
}

variable "root_volume_encrypted" {
  description = "Encrypt the root volume."
  type        = bool
  default     = true
}

variable "root_volume_device_name" {
  description = "Root device name. /dev/xvda for Amazon Linux, /dev/sda1 for Ubuntu/others."
  type        = string
  default     = "/dev/xvda"
}

variable "kms_key_id" {
  description = "KMS key ARN for root volume encryption (defaults to the AWS-managed EBS key)."
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null || var.root_volume_encrypted
    error_message = "kms_key_id requires root_volume_encrypted = true."
  }
}

variable "ebs_block_devices" {
  description = "Additional EBS block devices baked into the launch template. Encrypted by default."
  type = list(object({
    device_name           = string
    volume_size           = optional(number, 8)
    volume_type           = optional(string, "gp3")
    iops                  = optional(number)
    throughput            = optional(number)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string)
    snapshot_id           = optional(string)
    delete_on_termination = optional(bool, true)
  }))
  default = []

  validation {
    condition     = !contains([for d in var.ebs_block_devices : d.device_name], var.root_volume_device_name)
    error_message = "An ebs_block_devices device_name collides with root_volume_device_name; use a different device (e.g. /dev/sdf)."
  }

  validation {
    condition     = alltrue([for d in var.ebs_block_devices : d.iops == null || contains(["gp3", "io1", "io2"], d.volume_type)])
    error_message = "ebs_block_devices[*].iops is only valid for gp3, io1, or io2 volumes."
  }

  validation {
    condition     = alltrue([for d in var.ebs_block_devices : d.throughput == null || d.volume_type == "gp3"])
    error_message = "ebs_block_devices[*].throughput is only valid for gp3 volumes."
  }
}

# ============================================================================
# IAM
# ============================================================================

variable "create_instance_profile" {
  description = "Create an IAM role + instance profile for the instances. Ignored when instance_profile_name is set."
  type        = bool
  default     = false
}

variable "instance_profile_name" {
  description = "Name of an existing instance profile to use. Overrides create_instance_profile."
  type        = string
  default     = null
}

variable "iam_role_policies" {
  description = "Managed policy ARNs to attach to the created role, keyed by a stable name (e.g. ssm, ecs, cloudwatch)."
  type        = map(string)
  default     = {}
}

variable "iam_role_inline_policy" {
  description = "Optional inline IAM policy JSON for the created role."
  type        = string
  default     = null
}

variable "iam_permissions_boundary" {
  description = "Permissions boundary ARN for the created role."
  type        = string
  default     = null
}

# ============================================================================
# NETWORKING
# ============================================================================

variable "associate_public_ip_address" {
  description = "Assign a public IP to instances. Null (default) leaves it to the subnet's map_public_ip_on_launch. Set true/false to force it via a network interface on the launch template."
  type        = bool
  default     = null
}

# ============================================================================
# SECURITY GROUP (optional, managed here)
# ============================================================================

variable "create_security_group" {
  description = "Create a dedicated security group for the instances."
  type        = bool
  default     = false
}

variable "security_group_ids" {
  description = "Additional security group IDs to attach (alongside the created one, if any)."
  type        = list(string)
  default     = []
}

variable "security_group_name" {
  description = "Name prefix for the managed security group. Defaults to name."
  type        = string
  default     = null
}

variable "security_group_ingress_rules" {
  description = "Ingress rules for the managed SG (keyed map). Empty by default (no inbound)."
  type = map(object({
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
    prefix_list_id               = optional(string)
    description                  = optional(string)
  }))
  default = {}
}

variable "security_group_egress_rules" {
  description = "Egress rules for the managed SG (keyed map). Defaults to allow-all."
  type = map(object({
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "-1")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
    prefix_list_id               = optional(string)
    description                  = optional(string)
  }))
  default = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  }
}

# ============================================================================
# CAPACITY & HEALTH
# ============================================================================

variable "min_size" {
  description = "Minimum ASG size."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum ASG size."
  type        = number
  default     = 3

  validation {
    condition     = var.max_size >= var.min_size
    error_message = "max_size must be >= min_size."
  }
}

variable "desired_capacity" {
  description = "Initial desired capacity. NOTE: changes are ignored after create (ignore_changes) so an autoscaler / ECS capacity provider / scheduled action owns the live count. For a static fleet with no scaler, manage size via min_size/max_size or scheduled_actions - editing desired_capacity later is a no-op."
  type        = number
  default     = null

  validation {
    condition     = var.desired_capacity == null || (var.desired_capacity >= var.min_size && var.desired_capacity <= var.max_size)
    error_message = "desired_capacity must be between min_size and max_size."
  }
}

variable "protect_from_scale_in" {
  description = "Protect instances from ASG scale-in. Required true for an ECS capacity provider with managed_termination_protection = ENABLED; useful generally for stateful/drain-first fleets."
  type        = bool
  default     = false
}

variable "capacity_rebalance" {
  description = "Enable Capacity Rebalancing (proactively replace Spot at elevated interruption risk). Forced on when spot is set."
  type        = bool
  default     = false
}

variable "health_check_type" {
  description = "ASG health check type: 'EC2' or 'ELB'. Use 'ELB' when behind a load balancer so unhealthy targets are replaced."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  description = "Seconds to wait before health checks start after launch."
  type        = number
  default     = 300
}

variable "wait_for_capacity_timeout" {
  description = "How long Terraform waits for min_size (and wait_for_elb_capacity) to report healthy. Set \"0\" to skip waiting. Null uses the provider default (10m)."
  type        = string
  default     = null
}

variable "min_elb_capacity" {
  description = "Terraform waits until this many instances are healthy in the attached target groups/ELBs before completing create. Useful for ELB-fronted fleets."
  type        = number
  default     = null
}

variable "wait_for_elb_capacity" {
  description = "Like min_elb_capacity but enforced on both create and update."
  type        = number
  default     = null
}

variable "default_cooldown" {
  description = "Default cooldown (seconds) between scaling activities."
  type        = number
  default     = null
}

variable "default_instance_warmup" {
  description = "Default instance warmup (seconds) before an instance contributes to metrics."
  type        = number
  default     = null
}

variable "termination_policies" {
  description = "Instance termination policies (e.g. OldestInstance, NewestInstance, Default)."
  type        = list(string)
  default     = ["Default"]
}

variable "target_group_arns" {
  description = "Load balancer target group ARNs to register instances with (ALB/NLB)."
  type        = list(string)
  default     = []
}

variable "suspended_processes" {
  description = "ASG processes to suspend (e.g. AZRebalance during a migration)."
  type        = list(string)
  default     = []
}

# ============================================================================
# METRICS COLLECTION
# ============================================================================

variable "metrics_granularity" {
  description = "Granularity of the collected ASG metrics. Only '1Minute' is supported by AWS."
  type        = string
  default     = "1Minute"
}

variable "enabled_metrics" {
  description = "ASG group metrics to collect (free, 1-minute). Empty disables collection."
  type        = list(string)
  default = [
    "GroupMinSize",
    "GroupMaxSize",
    "GroupDesiredCapacity",
    "GroupInServiceInstances",
    "GroupPendingInstances",
    "GroupStandbyInstances",
    "GroupTerminatingInstances",
    "GroupTotalInstances",
  ]
}

# ============================================================================
# SPOT (optional mixed-instances policy)
# ============================================================================
# finops: spot ~up to 90% off but reclaimable on 2-min notice. keep a small
# on-demand base for availability; let the rest ride spot.

variable "spot" {
  description = <<-EOT
    Enable a mixed-instances policy. Null = 100% on-demand single type.
    WARNING: the defaults (on_demand_base_capacity = 0, percentage = 0) mean the
    ENTIRE fleet runs on Spot and can be reclaimed at once - set
    on_demand_base_capacity >= 1 if you need an always-on baseline. Diversify
    instance_types for better Spot availability. spot_instance_pools is only
    valid with allocation_strategy = "lowest-price".
  EOT
  type = object({
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 0)
    allocation_strategy                      = optional(string, "price-capacity-optimized")
    spot_max_price                           = optional(string)
    spot_instance_pools                      = optional(number)
  })
  default = null

  validation {
    condition     = var.spot == null || (var.spot.on_demand_percentage_above_base_capacity >= 0 && var.spot.on_demand_percentage_above_base_capacity <= 100)
    error_message = "spot.on_demand_percentage_above_base_capacity must be between 0 and 100."
  }

  validation {
    condition     = var.spot == null || var.spot.spot_instance_pools == null || var.spot.allocation_strategy == "lowest-price"
    error_message = "spot.spot_instance_pools is only valid with allocation_strategy = \"lowest-price\"."
  }

  validation {
    condition     = var.spot == null || var.spot.on_demand_base_capacity <= var.max_size
    error_message = "spot.on_demand_base_capacity must be <= max_size."
  }
}

# ============================================================================
# INSTANCE REFRESH / WARM POOL / LIFECYCLE HOOKS
# ============================================================================

variable "instance_refresh" {
  description = "Roll instances when the launch template changes. Null disables (changes apply to new instances only)."
  type = object({
    strategy               = optional(string, "Rolling")
    min_healthy_percentage = optional(number, 90)
    max_healthy_percentage = optional(number)
    instance_warmup        = optional(number)
    auto_rollback          = optional(bool)
  })
  default = null
}

variable "warm_pool" {
  description = "Optional warm pool for faster scale-out. Null disables."
  type = object({
    pool_state                  = optional(string, "Stopped")
    min_size                    = optional(number, 0)
    max_group_prepared_capacity = optional(number)
  })
  default = null
}

variable "initial_lifecycle_hooks" {
  description = "Lifecycle hooks created with the ASG (keyed map)."
  type = map(object({
    lifecycle_transition    = string # autoscaling:EC2_INSTANCE_LAUNCHING | _TERMINATING
    default_result          = optional(string)
    heartbeat_timeout       = optional(number)
    notification_target_arn = optional(string)
    role_arn                = optional(string)
    notification_metadata   = optional(string)
  }))
  default = {}
}

# ============================================================================
# TARGET-TRACKING SCALING POLICIES
# ============================================================================

variable "target_tracking_policies" {
  description = <<-EOT
    Target-tracking scaling policies (keyed map). Each tracks a predefined metric
    to a target value. predefined_metric_type is one of ASGAverageCPUUtilization,
    ASGAverageNetworkIn, ASGAverageNetworkOut, or ALBRequestCountPerTarget (which
    needs resource_label).
  EOT
  type = map(object({
    predefined_metric_type    = string
    target_value              = number
    resource_label            = optional(string)
    disable_scale_in          = optional(bool, false)
    estimated_instance_warmup = optional(number)
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, p in var.target_tracking_policies :
      contains(["ASGAverageCPUUtilization", "ASGAverageNetworkIn", "ASGAverageNetworkOut", "ALBRequestCountPerTarget"], p.predefined_metric_type)
    ])
    error_message = "predefined_metric_type must be ASGAverageCPUUtilization, ASGAverageNetworkIn, ASGAverageNetworkOut, or ALBRequestCountPerTarget."
  }

  validation {
    condition = alltrue([
      for k, p in var.target_tracking_policies :
      p.predefined_metric_type != "ALBRequestCountPerTarget" || p.resource_label != null
    ])
    error_message = "resource_label is required when predefined_metric_type = ALBRequestCountPerTarget."
  }
}

# ============================================================================
# SCHEDULED ACTIONS
# ============================================================================

variable "scheduled_actions" {
  description = "Scheduled capacity changes (keyed map). Set recurrence (cron) for repeating, or start_time/end_time for one-off. Omit a size field to leave it unchanged."
  type = map(object({
    min_size         = optional(number)
    max_size         = optional(number)
    desired_capacity = optional(number)
    recurrence       = optional(string)
    start_time       = optional(string)
    end_time         = optional(string)
    time_zone        = optional(string)
  }))
  default = {}
}

# ============================================================================
# CLOUDWATCH ALARMS (optional)
# ============================================================================
# off by default - alarms cost per alarm. the in-service alarm relies on
# GroupInServiceInstances, which enabled_metrics collects by default.

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms (high CPU across the group, and low in-service instance count)."
  type        = bool
  default     = false
}

variable "alarm_cpu_threshold" {
  description = "Average CPUUtilization (%) across the ASG for the high-CPU alarm."
  type        = number
  default     = 85
}

variable "alarm_min_in_service" {
  description = "Alarm when GroupInServiceInstances drops below this. Null defaults to min_size."
  type        = number
  default     = null
}

variable "alarm_evaluation_periods" {
  description = "Evaluation periods for the alarms."
  type        = number
  default     = 3
}

variable "alarm_period" {
  description = "Period (seconds) for the alarm statistics."
  type        = number
  default     = 60
}

variable "alarm_actions" {
  description = "ARNs notified on ALARM (e.g. an SNS topic)."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs notified when an alarm returns to OK."
  type        = list(string)
  default     = []
}
