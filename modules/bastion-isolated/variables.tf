# general

variable "create" {
  description = "Master switch. When false the module creates nothing."
  type        = bool
  default     = true
}

variable "name" {
  description = "Base name used to prefix all created resources."
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 100 && can(regex("^[a-zA-Z0-9-]+$", var.name))
    error_message = "name must be 1-100 characters, letters/numbers/hyphens only."
  }
}

variable "tags" {
  description = "Additional tags applied to every resource (drop map-migrated here for MAP)."
  type        = map(string)
  default     = {}
}

# ami / compute
# byo ami only - isolated accounts don't run user_data, so bake the image elsewhere

variable "ami_id" {
  description = "Pre-built AMI id to launch. Module does no AMI lookup - data-source it in the caller."
  type        = string

  validation {
    condition     = can(regex("^ami-[0-9a-f]+$", var.ami_id))
    error_message = "ami_id must be a valid AMI id (ami-...)."
  }
}

variable "instance_type" {
  description = "Primary instance type for the bastion."
  type        = string
  default     = "t3.micro"
}

variable "instance_types" {
  description = "Extra instance types. When set (or spot_enabled), the ASG switches to a mixed instances policy."
  type        = list(string)
  default     = []
}

variable "key_name" {
  description = "Optional EC2 key pair for SSH. Prefer SSM (no key, no inbound)."
  type        = string
  default     = null
}

variable "user_data" {
  description = "Optional plain-text user-data. Reminder: isolated envs usually don't run it - bake into the AMI."
  type        = string
  default     = null
}

variable "user_data_base64" {
  description = "Optional base64 user-data (wins over user_data). Same caveat."
  type        = string
  default     = null
}

variable "ebs_optimized" {
  description = "Whether the instances are EBS-optimized."
  type        = bool
  default     = true
}

variable "enable_detailed_monitoring" {
  description = "Enable detailed (1-minute) CloudWatch monitoring. Costs extra - off by default."
  type        = bool
  default     = false
}

variable "metadata_options" {
  description = "IMDS options. Defaults force IMDSv2 (http_tokens = required)."
  type = object({
    http_endpoint               = optional(string, "enabled")
    http_tokens                 = optional(string, "required")
    http_put_response_hop_limit = optional(number, 1)
    instance_metadata_tags      = optional(string, "enabled")
  })
  default = {}

  validation {
    condition     = contains(["enabled", "disabled"], var.metadata_options.http_endpoint)
    error_message = "metadata_options.http_endpoint must be 'enabled' or 'disabled'."
  }

  validation {
    condition     = contains(["optional", "required"], var.metadata_options.http_tokens)
    error_message = "metadata_options.http_tokens must be 'optional' or 'required' (prefer 'required' for IMDSv2)."
  }

  validation {
    condition     = var.metadata_options.http_put_response_hop_limit >= 1 && var.metadata_options.http_put_response_hop_limit <= 64
    error_message = "metadata_options.http_put_response_hop_limit must be between 1 and 64."
  }
}

variable "root_block_device" {
  description = "Root EBS volume. Encrypted by default."
  type = object({
    device_name           = optional(string, "/dev/xvda")
    volume_size           = optional(number, 8)
    volume_type           = optional(string, "gp3")
    iops                  = optional(number)
    throughput            = optional(number)
    encrypted             = optional(bool, true)
    kms_key_id            = optional(string)
    delete_on_termination = optional(bool, true)
  })
  default = {}

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "standard"], var.root_block_device.volume_type)
    error_message = "root_block_device.volume_type must be one of gp2, gp3, io1, io2, standard."
  }
}

variable "ebs_block_devices" {
  description = "Extra EBS volumes, keyed. Encrypted by default. Rare on a bastion."
  type = map(object({
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
  default = {}

  validation {
    condition     = alltrue([for k, v in var.ebs_block_devices : contains(["gp2", "gp3", "io1", "io2", "st1", "sc1", "standard"], v.volume_type)])
    error_message = "ebs_block_devices[*].volume_type must be a valid EBS volume type."
  }
}

# networking

variable "vpc_id" {
  description = "VPC id. Required when create_security_group is true."
  type        = string
  default     = null

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
  }
}

variable "subnet_ids" {
  description = "Subnets for the ASG. Private subnets = SSM-only, internet-isolated."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "Provide at least one subnet id."
  }
}

variable "associate_public_ip" {
  description = "Assign a public IP. Keep false for isolated/private bastions."
  type        = bool
  default     = false
}

# security group

variable "create_security_group" {
  description = "Create a security group for the bastion."
  type        = bool
  default     = true
}

variable "security_group_ids" {
  description = "Extra existing security group IDs to attach."
  type        = list(string)
  default     = []
}

variable "ssh_port" {
  description = "TCP port for the SSH convenience ingress rules."
  type        = number
  default     = 22
}

variable "ssh_allowed_cidr_blocks" {
  description = "IPv4 CIDRs allowed on ssh_port. Empty = SSM-only (recommended)."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_ipv6_cidr_blocks" {
  description = "IPv6 CIDRs allowed on ssh_port."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_security_group_ids" {
  description = "Security group IDs allowed on ssh_port."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_prefix_list_ids" {
  description = "Prefix list IDs allowed on ssh_port."
  type        = list(string)
  default     = []
}

variable "security_group_ingress_rules" {
  description = "Extra ingress rules for full control (keyed map)."
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
  description = "Egress rules. Defaults to allow-all (needs to reach the SSM/VPC endpoints)."
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

# iam

variable "create_iam_role" {
  description = "Create the role + instance profile (with SSM). Ignored when iam_instance_profile_name is set."
  type        = bool
  default     = true
}

variable "iam_instance_profile_name" {
  description = "Existing instance profile name to use instead of creating one."
  type        = string
  default     = null
}

variable "enable_ssm" {
  description = "Attach AmazonSSMManagedInstanceCore (Session Manager). This is how you reach the box."
  type        = bool
  default     = true
}

variable "attach_cloudwatch_agent_policy" {
  description = "Attach CloudWatchAgentServerPolicy to the created role."
  type        = bool
  default     = false
}

variable "iam_role_additional_policy_arns" {
  description = "Extra managed policy ARNs for the created role (keyed map)."
  type        = map(string)
  default     = {}
}

variable "iam_role_permissions_boundary" {
  description = "Permissions boundary ARN for the created role."
  type        = string
  default     = null
}

# auto scaling

variable "min_size" {
  description = "ASG min size during working hours."
  type        = number
  default     = 1
}

variable "max_size" {
  description = "ASG max size during working hours."
  type        = number
  default     = 1
}

variable "desired_capacity" {
  description = "ASG desired capacity (working hours). Only seeds the initial size - schedules own it after that."
  type        = number
  default     = 1
}

variable "health_check_type" {
  description = "ASG health check: 'EC2' or 'ELB' (ELB needs target_group_arns)."
  type        = string
  default     = "EC2"

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be 'EC2' or 'ELB'."
  }
}

variable "health_check_grace_period" {
  description = "Seconds before health checks start after launch."
  type        = number
  default     = 120
}

variable "default_cooldown" {
  description = "Seconds between scaling activities."
  type        = number
  default     = 300
}

variable "termination_policies" {
  description = "ASG termination policies."
  type        = list(string)
  default     = ["OldestInstance"]
}

variable "capacity_rebalance" {
  description = "Capacity rebalancing (useful with spot)."
  type        = bool
  default     = false
}

variable "spot_enabled" {
  description = "Use Spot via a mixed instances policy. Cheap, interruptible - fine for a bastion."
  type        = bool
  default     = false
}

variable "on_demand_base_capacity" {
  description = "On-demand base capacity for the mixed instances policy."
  type        = number
  default     = 0
}

variable "on_demand_percentage_above_base_capacity" {
  description = "On-demand percentage above the base (mixed instances policy)."
  type        = number
  default     = 100
}

variable "spot_allocation_strategy" {
  description = "Spot allocation strategy for the mixed instances policy."
  type        = string
  default     = "price-capacity-optimized"
}

variable "enabled_metrics" {
  description = "ASG metrics to enable (e.g. GroupInServiceInstances)."
  type        = list(string)
  default     = []
}

variable "target_group_arns" {
  description = "Target groups to attach the ASG to (e.g. behind an NLB). Required when health_check_type is 'ELB'."
  type        = list(string)
  default     = []
}

variable "instance_refresh" {
  description = "Roll the fleet when the launch template / AMI changes."
  type = object({
    strategy               = optional(string, "Rolling")
    min_healthy_percentage = optional(number, 90)
    instance_warmup        = optional(number)
    auto_rollback          = optional(bool, false)
  })
  default = null
}

# monitoring / alarms

variable "create_cloudwatch_alarms" {
  description = "Create a CloudWatch alarm on EC2 StatusCheckFailed so a wedged bastion is actually visible."
  type        = bool
  default     = false
}

variable "alarm_evaluation_periods" {
  description = "Evaluation periods for the alarm."
  type        = number
  default     = 2
}

variable "alarm_period" {
  description = "Period (seconds) for the alarm statistic."
  type        = number
  default     = 60
}

variable "alarm_actions" {
  description = "ARNs notified on ALARM (e.g. an SNS topic)."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs notified on OK."
  type        = list(string)
  default     = []
}

# auto-shutdown / schedules

variable "auto_shutdown" {
  description = "Scale to 0 off-hours and back during working hours. Off-hours capacity defaults to 0. This is the FinOps knob."
  type = object({
    enabled               = optional(bool, true)
    scale_down_recurrence = optional(string, "0 19 * * MON-FRI")
    scale_up_recurrence   = optional(string, "0 7 * * MON-FRI")
    time_zone             = optional(string)
    off_min_size          = optional(number, 0)
    off_max_size          = optional(number, 0)
    off_desired_capacity  = optional(number, 0)
  })
  default = null
}

variable "scheduled_actions" {
  description = "Extra scheduled scaling actions (keyed map) for full control."
  type = map(object({
    recurrence       = optional(string)
    start_time       = optional(string)
    end_time         = optional(string)
    time_zone        = optional(string)
    min_size         = optional(number, -1)
    max_size         = optional(number, -1)
    desired_capacity = optional(number, -1)
  }))
  default = {}
}
