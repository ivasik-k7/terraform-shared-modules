# ---------------------------------------------------------------------------
# Identity and posture
# ---------------------------------------------------------------------------

variable "create" {
  description = "Master switch. false plans to nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of the launch template, the Auto Scaling group, the instance role and the alarms. Changing it replaces all of them."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{0,35}$", var.name))
    error_message = "name must be 1-36 letters, digits or hyphens, starting with a letter or digit. The instance role is created with name_prefix \"<name>-\", which IAM caps at 38 characters."
  }
}

variable "tags" {
  description = "Tags on every resource the module creates, propagated to the instances and their volumes and network interfaces. The module adds ManagedBy and Module last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.tags : length(k) <= 128 ? (length(v) <= 256 ? !startswith(lower(k), "aws:") : false) : false])
    error_message = "tags keys must be at most 128 characters, values at most 256, and no key may start with the reserved \"aws:\" prefix."
  }
}

variable "autoscaling_group_tags" {
  description = "Tags on the Auto Scaling group only, propagated to its instances: fleet markers such as { AmazonECSManaged = \"\" } or { \"k8s.io/cluster-autoscaler/enabled\" = \"true\" }."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "instance_tags" {
  description = "Extra tags on the instances, their volumes and network interfaces only (for example a backup-plan selector), set through the launch template."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "required_tag_keys" {
  description = "Tag keys that must be in tags (and so on every resource and instance), for example [\"CostCenter\", \"Environment\", \"Owner\"]. A missing or empty value fails the plan. Empty: no requirement."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\"). An acknowledged check stops warning in plans and HCP Terraform health assessments, and is listed in output.governance so a reviewer still sees the decision."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for c in var.acknowledged_checks : contains([
        "somebody_hears_a_failure",
        "fleet_survives_an_az",
        "spot_fleets_keep_an_on_demand_floor",
        "volumes_use_a_customer_key",
        "burstable_credits_are_bounded",
        "instances_are_reached_without_ssh_keys",
        "instances_have_no_public_ip",
        "launch_template_changes_reach_the_fleet",
        "containers_cannot_reach_instance_credentials",
        "ami_is_pinned",
        "retained_instances_are_cleaned_up",
      ], c)
    ])
    error_message = "acknowledged_checks names a check that does not exist. The check names are the check blocks in checks.tf, listed in the README under \"Advisory checks\"."
  }
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "subnet_ids" {
  description = "Subnets the group launches into, one per AZ it may use. Two AZs or more for a fleet that must survive one."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.subnet_ids) > 0 ? alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))]) : false
    error_message = "subnet_ids must hold at least one subnet ID (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Security groups for the instances. Required: the module creates none, and an instance without one falls back to the VPC's default group."
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.security_group_ids) > 0 ? alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))]) : false
    error_message = "security_group_ids must hold at least one security group ID (sg-...)."
  }
}

variable "public_ip" {
  description = "Public IPv4 on the instances: \"\" leaves it to the subnet's setting, \"assign\" always assigns one, \"none\" never does. A public IP in a public subnet exposes every port the security groups open."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "assign", "none"], var.public_ip)
    error_message = "public_ip must be \"\", \"assign\" or \"none\"."
  }
}

variable "availability_zone_distribution" {
  description = "How launches spread over AZs when one has no capacity: \"balanced-best-effort\" launches in another AZ, \"balanced-only\" retries the same one, \"reservations-then-balanced\" fills capacity reservations first. Empty: the AWS default (balanced-best-effort)."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "balanced-best-effort", "balanced-only", "reservations-then-balanced"], var.availability_zone_distribution)
    error_message = "availability_zone_distribution must be \"\", \"balanced-best-effort\", \"balanced-only\" or \"reservations-then-balanced\"."
  }
}

# ---------------------------------------------------------------------------
# Image and instance shape
# ---------------------------------------------------------------------------

variable "ami" {
  description = "AMI ID. Exactly one of ami and ami_ssm_parameter. A pinned ID changes only when you change it, so an instance refresh never starts on its own."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ami == "" ? true : can(regex("^ami-[0-9a-f]{8,17}$", var.ami))
    error_message = "ami must be empty or an AMI ID (ami-...)."
  }
}

variable "ami_ssm_parameter" {
  description = "SSM parameter holding an AMI ID, resolved at every plan (for example /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64, or the ECS-optimized one). When AWS publishes a new image, the next apply moves the launch template and, with instance_refresh, replaces the fleet."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = (var.ami == "") != (var.ami_ssm_parameter == "")
    error_message = "Set exactly one of ami and ami_ssm_parameter."
  }

  validation {
    condition     = var.ami_ssm_parameter == "" ? true : can(regex("^(/[A-Za-z0-9_.\\-/]+|arn:aws[a-z-]*:ssm:[a-z0-9-]+:[0-9]{0,12}:parameter/.+)$", var.ami_ssm_parameter))
    error_message = "ami_ssm_parameter must be a parameter path starting with / or a parameter ARN."
  }
}

variable "instance_type" {
  description = "Instance type of a single-type fleet, and the first type of a mixed one. Ignored with instance_requirements."
  type        = string
  default     = "t3.medium"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.instance_type))
    error_message = "instance_type must be an EC2 instance type such as m7i.large."
  }
}

variable "instance_types" {
  description = "Instance types of a mixed fleet, in order of preference. Diversifying across types and generations keeps Spot available. Empty: [instance_type]."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.instance_types : can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", t))])
    error_message = "instance_types must be EC2 instance types such as m7i.large."
  }
}

variable "instance_weights" {
  description = "Units of capacity each type counts as, for example { \"m7i.2xlarge\" = 4, \"m7i.large\" = 1 }. min, max and desired are then in those units. Types not listed count as 1."
  type        = map(number)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for t, w in var.instance_weights : w >= 1 ? w <= 999 : false])
    error_message = "instance_weights values must be 1-999."
  }
}

variable "instance_requirements" {
  description = <<-EOT
    Attribute-based instance type selection: EC2 picks every current type that matches, which is the widest Spot diversification there is. Set vcpu_min above 0 to use it; instance_type and instance_types are then ignored.
      vcpu_min/vcpu_max, memory_mib_min/memory_mib_max  ranges (-1: no maximum)
      cpu_manufacturers                                 intel, amd, amazon-web-services
      instance_generations                              current, previous
      burstable_performance, bare_metal                 included, excluded, required
      allowed_instance_types / excluded_instance_types  patterns such as m7i.* (at most one of the two)
      spot_max_price_percentage_over_lowest_price,
      on_demand_max_price_percentage_over_lowest_price  price protection (-1: the AWS default)
  EOT
  type = object({
    vcpu_min                                         = optional(number, 0)
    vcpu_max                                         = optional(number, -1)
    memory_mib_min                                   = optional(number, 0)
    memory_mib_max                                   = optional(number, -1)
    cpu_manufacturers                                = optional(list(string), [])
    instance_generations                             = optional(list(string), ["current"])
    burstable_performance                            = optional(string, "excluded")
    bare_metal                                       = optional(string, "excluded")
    allowed_instance_types                           = optional(list(string), [])
    excluded_instance_types                          = optional(list(string), [])
    spot_max_price_percentage_over_lowest_price      = optional(number, -1)
    on_demand_max_price_percentage_over_lowest_price = optional(number, -1)
  })
  default  = {}
  nullable = false

  validation {
    condition = var.instance_requirements.vcpu_min == 0 ? true : alltrue([
      var.instance_requirements.vcpu_min >= 1,
      var.instance_requirements.vcpu_max == -1 ? true : var.instance_requirements.vcpu_max >= var.instance_requirements.vcpu_min,
      var.instance_requirements.memory_mib_min >= 0,
      var.instance_requirements.memory_mib_max == -1 ? true : var.instance_requirements.memory_mib_max >= var.instance_requirements.memory_mib_min,
      alltrue([for m in var.instance_requirements.cpu_manufacturers : contains(["intel", "amd", "amazon-web-services"], m)]),
      alltrue([for g in var.instance_requirements.instance_generations : contains(["current", "previous"], g)]),
      contains(["included", "excluded", "required"], var.instance_requirements.burstable_performance),
      contains(["included", "excluded", "required"], var.instance_requirements.bare_metal),
      length(var.instance_requirements.allowed_instance_types) == 0 ? true : length(var.instance_requirements.excluded_instance_types) == 0,
    ])
    error_message = "instance_requirements: vcpu_min 1 or more (0 turns it off) with vcpu_max -1 or at least vcpu_min; memory ranges likewise; cpu_manufacturers intel, amd or amazon-web-services; instance_generations current or previous; burstable_performance and bare_metal included, excluded or required; allowed_instance_types and excluded_instance_types not both."
  }
}

variable "key_name" {
  description = "EC2 key pair for SSH. Empty (recommended): reach instances with SSM Session Manager, which the default instance profile allows."
  type        = string
  default     = ""
  nullable    = false
}

variable "user_data" {
  description = "Plain-text user data; the module base64-encodes it. It is stored in the launch template, so it is visible to anyone who can describe it: keep secrets out and fetch them at boot."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true
}

variable "user_data_base64" {
  description = "User data already base64-encoded (for gzip or MIME multipart payloads). Not with user_data."
  type        = string
  default     = ""
  nullable    = false
  sensitive   = true

  validation {
    condition     = var.user_data == "" ? true : var.user_data_base64 == ""
    error_message = "Set only one of user_data and user_data_base64."
  }

  validation {
    condition     = var.user_data_base64 == "" ? true : can(base64decode(var.user_data_base64))
    error_message = "user_data_base64 must be valid base64."
  }
}

variable "metadata_hop_limit" {
  description = "IMDSv2 response hop limit. 1 keeps instance credentials away from containers on the host; containers in bridge mode that must reach IMDS (the ECS agent itself does not) need 2."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.metadata_hop_limit >= 1 ? var.metadata_hop_limit <= 64 : false
    error_message = "metadata_hop_limit must be 1-64."
  }
}

variable "metadata_tags" {
  description = "Expose the instance's tags through the instance metadata service."
  type        = bool
  default     = false
  nullable    = false
}

variable "cpu_credits" {
  description = "Credit mode for burstable (T-family) instances: \"standard\" throttles at zero credits, \"unlimited\" bills for surplus credits ($0.05 per vCPU-hour on Linux) with no ceiling. Applied only when every instance type is burstable."
  type        = string
  default     = "standard"
  nullable    = false

  validation {
    condition     = contains(["standard", "unlimited"], var.cpu_credits)
    error_message = "cpu_credits must be standard or unlimited."
  }
}

variable "auto_recovery" {
  description = "Simplified automatic recovery after a system status check failure: \"default\" (on, the AWS default) or \"disabled\". Empty: not sent."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "default", "disabled"], var.auto_recovery)
    error_message = "auto_recovery must be \"\", \"default\" or \"disabled\"."
  }
}

variable "ebs_optimized" {
  description = "EBS optimization: \"true\", \"false\", or \"\" for the instance type's default (on for every current generation)."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "true", "false"], var.ebs_optimized)
    error_message = "ebs_optimized must be \"\", \"true\" or \"false\"."
  }
}

variable "detailed_monitoring" {
  description = "One-minute EC2 metrics instead of five-minute ones, billed as CloudWatch custom metrics per instance. Target tracking reacts faster with it."
  type        = bool
  default     = false
  nullable    = false
}

variable "placement_group" {
  description = "Placement group the instances launch into, by name, or by ID (pg-...) for a group shared from another account. Empty: none."
  type        = string
  default     = ""
  nullable    = false
}

variable "tenancy" {
  description = "Instance tenancy: \"default\", \"dedicated\" or \"host\". Empty: the VPC's."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "default", "dedicated", "host"], var.tenancy)
    error_message = "tenancy must be \"\", \"default\", \"dedicated\" or \"host\"."
  }
}

variable "cpu_options" {
  description = "CPU cores and threads per core (1 turns simultaneous multithreading off, for licensing or side-channel isolation), and nested virtualization (\"enabled\" or \"disabled\", on the instance types that support it). -1 and \"\": the instance type's default."
  type = object({
    core_count            = optional(number, -1)
    threads_per_core      = optional(number, -1)
    nested_virtualization = optional(string, "")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains([-1, 1, 2], var.cpu_options.threads_per_core),
      var.cpu_options.core_count == -1 ? true : var.cpu_options.core_count >= 1,
      contains(["", "enabled", "disabled"], var.cpu_options.nested_virtualization),
    ])
    error_message = "cpu_options: threads_per_core is -1, 1 or 2; core_count is -1 or 1 or more; nested_virtualization is \"\", enabled or disabled."
  }
}

variable "bandwidth_weighting" {
  description = "How the instance's network bandwidth is split: \"vpc-1\" favours VPC traffic, \"ebs-1\" favours EBS, \"default\" is the type's own split. Only on instance types that support bandwidth weighting. Empty: not sent."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "default", "vpc-1", "ebs-1"], var.bandwidth_weighting)
    error_message = "bandwidth_weighting must be \"\", default, vpc-1 or ebs-1."
  }
}

variable "capacity_reservation" {
  description = "On-demand capacity reservations: preference \"open\" (use any matching open reservation), \"none\", or \"\" (not sent); or target specific reservation IDs or resource groups."
  type = object({
    preference          = optional(string, "")
    reservation_ids     = optional(list(string), [])
    resource_group_arns = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains(["", "open", "none"], var.capacity_reservation.preference),
      var.capacity_reservation.preference == "" ? true : length(var.capacity_reservation.reservation_ids) + length(var.capacity_reservation.resource_group_arns) == 0,
      length(var.capacity_reservation.reservation_ids) == 0 ? true : length(var.capacity_reservation.resource_group_arns) == 0,
      alltrue([for r in var.capacity_reservation.reservation_ids : can(regex("^cr-[0-9a-f]{17}$", r))]),
    ])
    error_message = "capacity_reservation: preference is \"\", open or none, and not together with a target; target either reservation_ids (cr-...) or resource_group_arns."
  }
}

# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------

variable "root_volume" {
  description = "The root volume. Always encrypted, with kms_key_arn or the account's EBS key. gp3 $0.0928 per GB-month in eu-west-2 (COSTS.md); iops and throughput above gp3's included 3,000 and 125 are billed. -1: the volume type's default."
  type = object({
    size_gib    = optional(number, 30)
    type        = optional(string, "gp3")
    iops        = optional(number, -1)
    throughput  = optional(number, -1)
    device_name = optional(string, "/dev/xvda")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.root_volume.size_gib >= 1, var.root_volume.size_gib <= 16384,
      contains(["gp2", "gp3", "io1", "io2"], var.root_volume.type),
      var.root_volume.iops == -1 ? true : contains(["gp3", "io1", "io2"], var.root_volume.type),
      var.root_volume.throughput == -1 ? true : var.root_volume.type == "gp3",
      can(regex("^/dev/[a-z0-9]+$", var.root_volume.device_name)),
    ])
    error_message = "root_volume: size_gib 1-16384; type gp2, gp3, io1 or io2; iops only on gp3, io1 and io2; throughput only on gp3; device_name such as /dev/xvda (Amazon Linux) or /dev/sda1 (Ubuntu)."
  }
}

variable "ebs_volumes" {
  description = "Extra EBS volumes, keyed by device name (for example /dev/sdf). Always encrypted with kms_key_arn or the account's EBS key."
  type = map(object({
    size_gib              = optional(number, 20)
    type                  = optional(string, "gp3")
    iops                  = optional(number, -1)
    throughput            = optional(number, -1)
    snapshot_id           = optional(string, "")
    delete_on_termination = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for d, v in var.ebs_volumes : alltrue([
      can(regex("^/dev/[a-z0-9]+$", d)),
      d != var.root_volume.device_name,
      v.size_gib >= 1, v.size_gib <= 65536,
      contains(["gp2", "gp3", "io1", "io2", "st1", "sc1", "standard"], v.type),
      v.iops == -1 ? true : contains(["gp3", "io1", "io2"], v.type),
      v.throughput == -1 ? true : v.type == "gp3",
      v.snapshot_id == "" ? true : can(regex("^snap-[0-9a-f]{8,17}$", v.snapshot_id)),
    ])])
    error_message = "ebs_volumes: keys are device names (/dev/sdf) other than the root device; size_gib 1-65536; type gp2, gp3, io1, io2, st1, sc1 or standard; iops only on gp3, io1 and io2; throughput only on gp3; snapshot_id empty or snap-..."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key for every volume. Auto Scaling launches with its service-linked role, which has no access to customer keys: output.kms_key_policy_requirements says what the key policy must allow, and without it every launch fails while the apply stays green. Empty: the account's EBS key."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "service_linked_role_arn" {
  description = "Auto Scaling service-linked role the group launches with. Empty: AWSServiceRoleForAutoScaling. A custom-suffix role (AWSServiceRoleForAutoScaling_<suffix>) lets one key admit one group's launches only."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.service_linked_role_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/aws-service-role/autoscaling\\.amazonaws\\.com/AWSServiceRoleForAutoScaling", var.service_linked_role_arn))
    error_message = "service_linked_role_arn must be empty or an Auto Scaling service-linked role ARN (.../aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling...)."
  }
}

# ---------------------------------------------------------------------------
# Instance role
# ---------------------------------------------------------------------------

variable "instance_profile" {
  description = <<-EOT
    The instances' IAM role.
      create = true      makes <name>-* with an instance profile (the default)
      ssm = true         attaches AmazonSSMManagedInstanceCore, so instances are reachable by Session Manager without SSH or a bastion
      policies           inline policies on the created role, name => JSON (values may be unknown at plan)
      managed_policies   managed policy ARNs on the created role, keyed by a stable name
      create = false     uses an existing instance profile by name
  EOT
  type = object({
    create           = optional(bool, true)
    name             = optional(string, "")
    ssm              = optional(bool, true)
    policies         = optional(map(string), {})
    managed_policies = optional(map(string), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = var.instance_profile.create ? var.instance_profile.name == "" : alltrue([
      var.instance_profile.name != "",
      length(var.instance_profile.policies) + length(var.instance_profile.managed_policies) == 0,
    ])
    error_message = "instance_profile: create = true (the default) with no name, or create = false with the name of an existing instance profile. policies and managed_policies apply only to a role the module creates."
  }

  validation {
    condition     = alltrue([for n, d in var.instance_profile.policies : can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", n))])
    error_message = "instance_profile.policies keys must be inline policy names (letters, digits and +=,.@_-)."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the instance role. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "min_size" {
  description = "Fewest instances (or weighted units)."
  type        = number
  default     = 1
  nullable    = false

  validation {
    condition     = var.min_size >= 0
    error_message = "min_size must be 0 or more."
  }
}

variable "max_size" {
  description = "Most instances (or weighted units): the ceiling of the bill."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.max_size >= var.min_size ? var.max_size >= 1 : false
    error_message = "max_size must be 1 or more and at least min_size."
  }
}

variable "desired_capacity" {
  description = "Instances to start with. -1: min_size. With ignore_desired_capacity_changes (the default) it is read only at creation; after that, scaling policies, scheduled actions or an ECS capacity provider own the count."
  type        = number
  default     = -1
  nullable    = false

  validation {
    condition     = var.desired_capacity == -1 ? true : (var.desired_capacity >= var.min_size ? var.desired_capacity <= var.max_size : false)
    error_message = "desired_capacity must be -1 or between min_size and max_size."
  }
}

variable "ignore_desired_capacity_changes" {
  description = "Leave the live instance count to something else: scaling policies, scheduled actions, an ECS capacity provider or a cluster autoscaler. false: Terraform owns desired_capacity, so every apply sets it back. Changing it on an existing group moves the group between two resource addresses; write a moved block (README)."
  type        = bool
  default     = true
  nullable    = false
}

variable "protect_from_scale_in" {
  description = "Protect new instances from scale-in. Required by an ECS capacity provider with managed termination protection."
  type        = bool
  default     = false
  nullable    = false
}

variable "capacity_rebalance" {
  description = "Replace Spot instances proactively when AWS signals elevated interruption risk. On whenever the fleet uses Spot."
  type        = bool
  default     = false
  nullable    = false
}

variable "max_instance_lifetime" {
  description = "Seconds after which an instance is replaced, so no instance runs unpatched for longer (86400-31536000). 0: no limit."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.max_instance_lifetime == 0 ? true : (var.max_instance_lifetime >= 86400 ? var.max_instance_lifetime <= 31536000 : false)
    error_message = "max_instance_lifetime must be 0 or 86400-31536000 seconds (one day to one year)."
  }
}

variable "health_check_type" {
  description = "EC2 (instance status checks) or ELB (also the target groups' health checks, so an instance a load balancer marks unhealthy is replaced)."
  type        = string
  default     = "EC2"
  nullable    = false

  validation {
    condition     = contains(["EC2", "ELB"], var.health_check_type)
    error_message = "health_check_type must be EC2 or ELB."
  }
}

variable "health_check_grace_period" {
  description = "Seconds after launch before health checks count."
  type        = number
  default     = 300
  nullable    = false

  validation {
    condition     = var.health_check_grace_period >= 0
    error_message = "health_check_grace_period must be 0 or more."
  }
}

variable "default_instance_warmup" {
  description = "Seconds a new instance takes to be ready, used by scaling, instance refresh and maintenance replacements. -1: not set."
  type        = number
  default     = -1
  nullable    = false

  validation {
    condition     = var.default_instance_warmup >= -1
    error_message = "default_instance_warmup must be -1 or 0 or more."
  }
}

variable "termination_policies" {
  description = "Which instances scale-in removes first."
  type        = list(string)
  default     = ["Default"]
  nullable    = false

  validation {
    condition     = alltrue([for p in var.termination_policies : contains(["Default", "AllocationStrategy", "OldestLaunchTemplate", "OldestLaunchConfiguration", "ClosestToNextInstanceHour", "NewestInstance", "OldestInstance"], p) ? true : can(regex("^arn:aws[a-z-]*:lambda:", p))])
    error_message = "termination_policies are Default, AllocationStrategy, OldestLaunchTemplate, OldestLaunchConfiguration, ClosestToNextInstanceHour, NewestInstance, OldestInstance, or a Lambda function ARN."
  }
}

variable "suspended_processes" {
  description = "Auto Scaling processes to suspend, for example AZRebalance during a migration."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.suspended_processes : contains(["Launch", "Terminate", "HealthCheck", "ReplaceUnhealthy", "AZRebalance", "AlarmNotification", "ScheduledActions", "AddToLoadBalancer", "InstanceRefresh"], p)])
    error_message = "suspended_processes are Launch, Terminate, HealthCheck, ReplaceUnhealthy, AZRebalance, AlarmNotification, ScheduledActions, AddToLoadBalancer or InstanceRefresh."
  }
}

variable "target_group_arns" {
  description = "ALB or NLB target groups the instances register with."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.target_group_arns : can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/", t))])
    error_message = "target_group_arns must be target group ARNs."
  }
}

variable "wait_for_capacity_timeout" {
  description = "How long an apply waits for min_size healthy instances (\"10m\"). \"0\" does not wait. Empty: the provider's 10 minutes."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.wait_for_capacity_timeout == "" ? true : can(regex("^[0-9]+(s|m|h)?$", var.wait_for_capacity_timeout))
    error_message = "wait_for_capacity_timeout must be empty or a duration such as 10m."
  }
}

variable "wait_for_elb_capacity" {
  description = "Healthy instances in the target groups an apply waits for, on create and update. -1: do not wait for load balancers."
  type        = number
  default     = -1
  nullable    = false
}

variable "ignore_failed_scaling_activities" {
  description = "Let an apply that waits for capacity ignore failed scaling activities instead of failing on the first one."
  type        = bool
  default     = false
  nullable    = false
}

variable "enabled_metrics" {
  description = "Group metrics to collect at one-minute granularity (free). The in-service alarm reads GroupInServiceInstances. Empty: none."
  type        = list(string)
  default = [
    "GroupMinSize", "GroupMaxSize", "GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances",
    "GroupStandbyInstances", "GroupTerminatingInstances", "GroupTotalInstances", "GroupInServiceCapacity",
    "GroupPendingCapacity", "GroupStandbyCapacity", "GroupTerminatingCapacity", "GroupTotalCapacity",
    "WarmPoolDesiredCapacity", "WarmPoolWarmedCapacity", "WarmPoolPendingCapacity", "WarmPoolTerminatingCapacity",
    "WarmPoolTotalCapacity", "GroupAndWarmPoolDesiredCapacity", "GroupAndWarmPoolTotalCapacity",
  ]
  nullable = false
}

variable "instance_maintenance_policy" {
  description = "Healthy capacity kept while instances are replaced for health or refresh: min_healthy_percentage 100 with max_healthy_percentage 110-200 launches before it terminates. -1/-1: the AWS default (terminate, then launch)."
  type = object({
    min_healthy_percentage = optional(number, -1)
    max_healthy_percentage = optional(number, -1)
  })
  default  = {}
  nullable = false

  validation {
    condition = (var.instance_maintenance_policy.min_healthy_percentage == -1) == (var.instance_maintenance_policy.max_healthy_percentage == -1) ? (var.instance_maintenance_policy.min_healthy_percentage == -1 ? true : alltrue([
      var.instance_maintenance_policy.min_healthy_percentage >= 0, var.instance_maintenance_policy.min_healthy_percentage <= 100,
      var.instance_maintenance_policy.max_healthy_percentage >= 100, var.instance_maintenance_policy.max_healthy_percentage <= 200,
    ])) : false
    error_message = "instance_maintenance_policy: set both or neither; min_healthy_percentage 0-100, max_healthy_percentage 100-200."
  }
}

# ---------------------------------------------------------------------------
# Purchase options
# ---------------------------------------------------------------------------

variable "purchase_options" {
  description = <<-EOT
    On-demand and Spot mix of a mixed fleet. The default is all on-demand.
      on_demand_base_capacity                   always on-demand, before the percentage applies
      on_demand_percentage_above_base_capacity  100 all on-demand; 0 all Spot above the base
      spot_allocation_strategy                  price-capacity-optimized (recommended), capacity-optimized, capacity-optimized-prioritized, lowest-price
      on_demand_allocation_strategy             lowest-price or prioritized (instance_types order). Empty: the AWS default
      spot_max_price                            empty: the on-demand price (recommended)
      spot_instance_pools                       lowest-price only; 0: not set
    Spot instances can be reclaimed with two minutes' notice; capacity_rebalance is on whenever Spot is used.
  EOT
  type = object({
    on_demand_base_capacity                  = optional(number, 0)
    on_demand_percentage_above_base_capacity = optional(number, 100)
    spot_allocation_strategy                 = optional(string, "price-capacity-optimized")
    on_demand_allocation_strategy            = optional(string, "")
    spot_max_price                           = optional(string, "")
    spot_instance_pools                      = optional(number, 0)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.purchase_options.on_demand_base_capacity >= 0,
      var.purchase_options.on_demand_base_capacity <= var.max_size,
      var.purchase_options.on_demand_percentage_above_base_capacity >= 0,
      var.purchase_options.on_demand_percentage_above_base_capacity <= 100,
      contains(["price-capacity-optimized", "capacity-optimized", "capacity-optimized-prioritized", "lowest-price"], var.purchase_options.spot_allocation_strategy),
      contains(["", "lowest-price", "prioritized"], var.purchase_options.on_demand_allocation_strategy),
      var.purchase_options.spot_max_price == "" ? true : can(tonumber(var.purchase_options.spot_max_price)),
      var.purchase_options.spot_instance_pools == 0 ? true : (var.purchase_options.spot_allocation_strategy == "lowest-price" ? var.purchase_options.spot_instance_pools <= 20 : false),
    ])
    error_message = "purchase_options: on_demand_base_capacity 0 to max_size; on_demand_percentage_above_base_capacity 0-100; spot_allocation_strategy price-capacity-optimized, capacity-optimized, capacity-optimized-prioritized or lowest-price; on_demand_allocation_strategy empty, lowest-price or prioritized; spot_max_price empty or a number; spot_instance_pools 1-20, and only with lowest-price."
  }
}

# ---------------------------------------------------------------------------
# Replacement: instance refresh, warm pool, lifecycle hooks
# ---------------------------------------------------------------------------

variable "instance_refresh" {
  description = <<-EOT
    Replace instances when the launch template or the instance mix changes. On by default: without it a change reaches only instances launched afterwards, and the fleet runs mixed versions until scale-in removes the old ones.
      min_healthy_percentage / max_healthy_percentage  capacity kept during the refresh (max above 100 launches before it terminates)
      skip_matching        leave instances that already match (on)
      auto_rollback        roll back when the refresh fails or an alarm in alarm_names fires (on)
      checkpoint_percentages, checkpoint_delay_seconds  pause at those percentages
      triggers             other group attributes whose change also starts a refresh (for example tag)
    An apply that changes the template while a refresh runs cancels it and starts a new one.
  EOT
  type = object({
    enabled                      = optional(bool, true)
    min_healthy_percentage       = optional(number, 90)
    max_healthy_percentage       = optional(number, 100)
    instance_warmup              = optional(number, -1)
    skip_matching                = optional(bool, true)
    auto_rollback                = optional(bool, true)
    alarm_names                  = optional(list(string), [])
    checkpoint_percentages       = optional(list(number), [])
    checkpoint_delay_seconds     = optional(number, -1)
    scale_in_protected_instances = optional(string, "Ignore")
    standby_instances            = optional(string, "Ignore")
    triggers                     = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.instance_refresh.min_healthy_percentage >= 0, var.instance_refresh.min_healthy_percentage <= 100,
      var.instance_refresh.max_healthy_percentage >= 100, var.instance_refresh.max_healthy_percentage <= 200,
      var.instance_refresh.instance_warmup >= -1,
      contains(["Refresh", "Ignore", "Wait"], var.instance_refresh.scale_in_protected_instances),
      contains(["Terminate", "Ignore", "Wait"], var.instance_refresh.standby_instances),
      alltrue([for p in var.instance_refresh.checkpoint_percentages : p >= 1 ? p <= 100 : false]),
      # sort() orders as strings, so ascending is checked pairwise.
      length(var.instance_refresh.checkpoint_percentages) < 2 ? true : alltrue([for i in range(1, length(var.instance_refresh.checkpoint_percentages)) : var.instance_refresh.checkpoint_percentages[i] > var.instance_refresh.checkpoint_percentages[i - 1]]),
      length(var.instance_refresh.checkpoint_percentages) == 0 ? true : var.instance_refresh.checkpoint_percentages[length(var.instance_refresh.checkpoint_percentages) - 1] == 100,
      length(var.instance_refresh.alarm_names) == 0 ? true : var.instance_refresh.auto_rollback,
      alltrue([for t in var.instance_refresh.triggers : !contains(["launch_template", "mixed_instances_policy", "launch_configuration"], t)]),
    ])
    error_message = "instance_refresh: min_healthy_percentage 0-100; max_healthy_percentage 100-200; scale_in_protected_instances Refresh, Ignore or Wait; standby_instances Terminate, Ignore or Wait; checkpoint_percentages ascending, 1-100, ending at 100; alarm_names need auto_rollback; triggers never list launch_template or mixed_instances_policy (they always start a refresh)."
  }
}

variable "warm_pool" {
  description = "Pre-initialized instances kept Stopped (EBS billed, compute not), Hibernated or Running, so scale-out skips the boot. Not with Spot or instance weights."
  type = object({
    enabled                     = optional(bool, false)
    pool_state                  = optional(string, "Stopped")
    min_size                    = optional(number, 0)
    max_group_prepared_capacity = optional(number, -1)
    reuse_on_scale_in           = optional(bool, false)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains(["Stopped", "Running", "Hibernated"], var.warm_pool.pool_state),
      var.warm_pool.min_size >= 0,
      var.warm_pool.max_group_prepared_capacity >= -1,
    ])
    error_message = "warm_pool: pool_state Stopped, Running or Hibernated; min_size 0 or more; max_group_prepared_capacity -1 (max_size) or 0 or more."
  }
}

variable "lifecycle_hooks" {
  description = <<-EOT
    Lifecycle hooks, keyed by name, that hold an instance while something else prepares it (LAUNCHING) or drains it (TERMINATING).
    They are separate resources, so changing one is an update. initial = true puts a launch hook on the group itself, so it also holds
    the instances launched when the group is created; any change to an initial hook replaces the whole group, and with it every instance.
  EOT
  type = map(object({
    transition              = string
    default_result          = optional(string, "ABANDON")
    heartbeat_timeout       = optional(number, 3600)
    notification_target_arn = optional(string, "")
    role_arn                = optional(string, "")
    notification_metadata   = optional(string, "")
    initial                 = optional(bool, false)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for n, h in var.lifecycle_hooks : alltrue([
      can(regex("^[A-Za-z0-9_.-]{1,255}$", n)),
      contains(["LAUNCHING", "TERMINATING"], h.transition),
      contains(["CONTINUE", "ABANDON"], h.default_result),
      h.heartbeat_timeout >= 30 ? h.heartbeat_timeout <= 7200 : false,
      (h.notification_target_arn == "") == (h.role_arn == ""),
      h.notification_target_arn == "" ? true : can(regex("^arn:aws[a-z-]*:(sns|sqs):", h.notification_target_arn)),
      h.initial ? h.transition == "LAUNCHING" : true,
    ])])
    error_message = "lifecycle_hooks: names are letters, digits, _ . -; transition LAUNCHING or TERMINATING; default_result CONTINUE or ABANDON; heartbeat_timeout 30-7200; notification_target_arn (SNS or SQS) and role_arn together or not at all; initial only for LAUNCHING hooks."
  }
}

variable "terminate_hook_abandon" {
  description = "What happens to an instance whose TERMINATING lifecycle hook ends with ABANDON (a drain or a log shipment that failed): \"retain\" keeps it stopped out of service for investigation, \"terminate\" terminates it. A retained instance keeps billing, does not count toward desired capacity (so a replacement launches beside it), and stays until someone calls TerminateInstanceInAutoScalingGroup. Empty: not sent (terminate)."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = contains(["", "retain", "terminate"], var.terminate_hook_abandon)
    error_message = "terminate_hook_abandon must be \"\", retain or terminate."
  }

  validation {
    condition     = var.terminate_hook_abandon == "" ? true : anytrue([for h in values(var.lifecycle_hooks) : h.transition == "TERMINATING"])
    error_message = "terminate_hook_abandon acts only on TERMINATING lifecycle hooks, and lifecycle_hooks has none: it would never apply."
  }
}

# ---------------------------------------------------------------------------
# Scaling
# ---------------------------------------------------------------------------

variable "target_tracking_policies" {
  description = <<-EOT
    Target tracking policies, keyed by name. Either a predefined metric (ASGAverageCPUUtilization, ASGAverageNetworkIn,
    ASGAverageNetworkOut, ALBRequestCountPerTarget with resource_label app/<lb>/<id>/targetgroup/<tg>/<id>) or a customized one
    (namespace, metric_name, statistic, dimensions). Needs ignore_desired_capacity_changes.
  EOT
  type = map(object({
    target_value              = number
    predefined_metric_type    = optional(string, "")
    resource_label            = optional(string, "")
    disable_scale_in          = optional(bool, false)
    estimated_instance_warmup = optional(number, -1)
    customized = optional(object({
      namespace   = string
      metric_name = string
      statistic   = optional(string, "Average")
      unit        = optional(string, "")
      dimensions  = optional(map(string), {})
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for n, p in var.target_tracking_policies : alltrue([
      (p.predefined_metric_type != "") != (p.customized != null),
      p.predefined_metric_type == "" ? true : contains(["ASGAverageCPUUtilization", "ASGAverageNetworkIn", "ASGAverageNetworkOut", "ALBRequestCountPerTarget"], p.predefined_metric_type),
      p.predefined_metric_type == "ALBRequestCountPerTarget" ? can(regex("^app/[^/]+/[0-9a-f]+/targetgroup/[^/]+/[0-9a-f]+$", p.resource_label)) : p.resource_label == "",
      p.customized == null ? true : contains(["Average", "Minimum", "Maximum", "SampleCount", "Sum"], p.customized.statistic),
      p.target_value > 0,
    ])])
    error_message = "target_tracking_policies: exactly one of predefined_metric_type (ASGAverageCPUUtilization, ASGAverageNetworkIn, ASGAverageNetworkOut, ALBRequestCountPerTarget) and customized; resource_label app/<lb>/<id>/targetgroup/<tg>/<id> with ALBRequestCountPerTarget only; statistic Average, Minimum, Maximum, SampleCount or Sum; target_value above 0."
  }
}

variable "predictive_scaling" {
  description = <<-EOT
    Predictive scaling: forecasts load from 14 days of history and launches ahead of it. Start in ForecastOnly mode and compare the forecast with actual load before ForecastAndScale.
      metric          cpu, network_in, network_out or alb_requests (with resource_label)
      target_value    the metric's target per instance
      scheduling_buffer_seconds   launch this early (-1: the AWS default)
      max_capacity_breach_behavior HonorMaxCapacity, or IncreaseMaxCapacity by max_capacity_buffer percent
  EOT
  type = object({
    enabled                      = optional(bool, false)
    metric                       = optional(string, "cpu")
    target_value                 = optional(number, 50)
    resource_label               = optional(string, "")
    mode                         = optional(string, "ForecastOnly")
    scheduling_buffer_seconds    = optional(number, -1)
    max_capacity_breach_behavior = optional(string, "HonorMaxCapacity")
    max_capacity_buffer          = optional(number, -1)
  })
  default  = {}
  nullable = false

  validation {
    condition = !var.predictive_scaling.enabled ? true : alltrue([
      contains(["cpu", "network_in", "network_out", "alb_requests"], var.predictive_scaling.metric),
      var.predictive_scaling.metric == "alb_requests" ? can(regex("^app/[^/]+/[0-9a-f]+/targetgroup/[^/]+/[0-9a-f]+$", var.predictive_scaling.resource_label)) : var.predictive_scaling.resource_label == "",
      contains(["ForecastOnly", "ForecastAndScale"], var.predictive_scaling.mode),
      contains(["HonorMaxCapacity", "IncreaseMaxCapacity"], var.predictive_scaling.max_capacity_breach_behavior),
      var.predictive_scaling.max_capacity_buffer == -1 ? true : (var.predictive_scaling.max_capacity_breach_behavior == "IncreaseMaxCapacity" ? var.predictive_scaling.max_capacity_buffer <= 100 : false),
      var.predictive_scaling.scheduling_buffer_seconds >= -1, var.predictive_scaling.scheduling_buffer_seconds <= 3600,
      var.predictive_scaling.target_value > 0,
    ])
    error_message = "predictive_scaling: metric cpu, network_in, network_out or alb_requests (which needs resource_label); mode ForecastOnly or ForecastAndScale; max_capacity_breach_behavior HonorMaxCapacity or IncreaseMaxCapacity, max_capacity_buffer 0-100 only with the latter; scheduling_buffer_seconds -1 to 3600; target_value above 0."
  }
}

variable "scheduled_actions" {
  description = "Scheduled changes of min, max and desired, keyed by name: recurrence (cron, in time_zone) for a repeating change, or start_time/end_time (2026-12-01T08:00:00Z) for one-off. -1 leaves that bound unchanged."
  type = map(object({
    min_size         = optional(number, -1)
    max_size         = optional(number, -1)
    desired_capacity = optional(number, -1)
    recurrence       = optional(string, "")
    start_time       = optional(string, "")
    end_time         = optional(string, "")
    time_zone        = optional(string, "")
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for n, a in var.scheduled_actions : alltrue([
      a.min_size + a.max_size + a.desired_capacity > -3,
      a.min_size == -1 ? true : a.min_size >= 0,
      a.max_size == -1 ? true : (a.min_size == -1 ? true : a.max_size >= a.min_size),
      a.recurrence != "" ? true : a.start_time != "",
      a.start_time == "" ? true : can(formatdate("YYYY", a.start_time)),
      a.end_time == "" ? true : can(formatdate("YYYY", a.end_time)),
      a.time_zone == "" ? true : a.recurrence != "",
    ])])
    error_message = "scheduled_actions: change at least one of min_size, max_size, desired_capacity (max not below min); give a recurrence or a start_time (RFC 3339, 2026-12-01T08:00:00Z); time_zone only with a recurrence."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "Topic for alarms, failed launches and terminations, and failed or rolled-back instance refreshes. The module does not own it: output.notification_requirements is what its policy must allow. Empty: alarms have no actions unless alarm_actions is set, and no event rules are created."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_arn == "" ? true : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]+$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be empty or an SNS topic ARN."
  }
}

variable "sns_topic_kms_key_arn" {
  description = "The topic's customer managed key, if it has one, so kms_key_policy_requirements can say which publishers it must allow."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.sns_topic_kms_key_arn))
    error_message = "sns_topic_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "create_event_rules" {
  description = "EventBridge rules that forward failed launches and terminations and failed, cancelled or rolled-back instance refreshes to sns_topic_arn. Events from AWS services cost nothing to match. Not created without a topic."
  type        = bool
  default     = true
  nullable    = false
}

variable "create_alarms" {
  description = "A high-CPU alarm and an in-service-instances alarm ($0.10 per alarm-month). The second reads GroupInServiceInstances and is created only when enabled_metrics collects it."
  type        = bool
  default     = true
  nullable    = false
}

variable "alarm_cpu_percent" {
  description = "Average CPU across the group that raises the CPU alarm."
  type        = number
  default     = 85
  nullable    = false

  validation {
    condition     = var.alarm_cpu_percent > 0 ? var.alarm_cpu_percent <= 100 : false
    error_message = "alarm_cpu_percent must be 1-100."
  }
}

variable "alarm_min_in_service" {
  description = "In-service instances below which the in-service alarm fires. -1: the lowest count the group may run (min_size, or a scheduled action's lower min_size); 0: no in-service alarm."
  type        = number
  default     = -1
  nullable    = false

  validation {
    condition     = var.alarm_min_in_service >= -1
    error_message = "alarm_min_in_service must be -1 or 0 or more."
  }
}

variable "alarm_period" {
  description = "Seconds per datapoint. Group metrics are published every 60 seconds; EC2 CPU every 300 without detailed_monitoring."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.alarm_period >= 60 ? var.alarm_period % 60 == 0 : false
    error_message = "alarm_period must be a multiple of 60 seconds."
  }
}

variable "alarm_evaluation_periods" {
  description = "Consecutive breaching periods before an alarm fires."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.alarm_evaluation_periods >= 1 ? var.alarm_evaluation_periods * var.alarm_period <= 86400 : false
    error_message = "alarm_evaluation_periods must be 1 or more, and periods × alarm_period at most one day."
  }
}

variable "alarm_actions" {
  description = "Where alarms send ALARM (SNS, Lambda, incident plans). Empty: sns_topic_arn, when set."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.alarm_actions) <= 5 ? alltrue([for a in var.alarm_actions : startswith(a, "arn:")]) : false
    error_message = "alarm_actions must be at most five ARNs (CloudWatch's limit per state)."
  }
}

variable "ok_actions" {
  description = "Where alarms send OK. Empty: the same as the alarm actions."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.ok_actions) <= 5 ? alltrue([for a in var.ok_actions : startswith(a, "arn:")]) : false
    error_message = "ok_actions must be at most five ARNs (CloudWatch's limit per state)."
  }
}
