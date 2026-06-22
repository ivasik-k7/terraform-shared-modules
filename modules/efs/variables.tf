variable "name" {
  description = "Name of the EFS file system"
  type        = string

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "Name must be between 1 and 64 characters (it is used as the creation token)."
  }
}

variable "creation_token" {
  description = "A unique name used as reference when creating the EFS. If not provided, uses the name variable"
  type        = string
  default     = null

  validation {
    condition     = var.creation_token == null || length(coalesce(var.creation_token, "x")) <= 64
    error_message = "Creation token must be 64 characters or less."
  }
}

variable "encrypted" {
  description = "Whether to encrypt the file system"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN of the KMS key to use for encryption. If not specified, uses the default AWS EFS KMS key"
  type        = string
  default     = null

  validation {
    condition     = var.kms_key_id == null || var.encrypted
    error_message = "kms_key_id can only be set when encrypted is true."
  }
}

variable "performance_mode" {
  description = "The file system performance mode. Can be either generalPurpose or maxIO"
  type        = string
  default     = "generalPurpose"

  validation {
    condition     = contains(["generalPurpose", "maxIO"], var.performance_mode)
    error_message = "Performance mode must be either generalPurpose or maxIO."
  }
}

variable "throughput_mode" {
  description = "Throughput mode for the file system. Valid values: bursting, provisioned, or elastic"
  type        = string
  default     = "bursting"

  validation {
    condition     = contains(["bursting", "provisioned", "elastic"], var.throughput_mode)
    error_message = "Throughput mode must be bursting, provisioned, or elastic."
  }
}

variable "provisioned_throughput_in_mibps" {
  description = "The throughput, measured in MiB/s, to provision for the file system. Only applicable with throughput_mode set to provisioned"
  type        = number
  default     = null

  validation {
    condition = (
      var.throughput_mode == "provisioned"
      ? (var.provisioned_throughput_in_mibps != null && var.provisioned_throughput_in_mibps > 0)
      : var.provisioned_throughput_in_mibps == null
    )
    error_message = "provisioned_throughput_in_mibps must be > 0 when throughput_mode is 'provisioned', and null otherwise."
  }
}

variable "availability_zone_name" {
  description = "The AWS Availability Zone in which to create the file system. Used to create a one-zone file system"
  type        = string
  default     = null
}

variable "lifecycle_policy_transition_to_ia" {
  description = "How long before transitioning files to the IA storage class. Valid values: AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, AFTER_365_DAYS"
  type        = string
  default     = null

  validation {
    condition = var.lifecycle_policy_transition_to_ia == null || contains([
      "AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", "AFTER_60_DAYS",
      "AFTER_90_DAYS", "AFTER_180_DAYS", "AFTER_270_DAYS", "AFTER_365_DAYS"
    ], coalesce(var.lifecycle_policy_transition_to_ia, "none"))
    error_message = "Invalid transition_to_ia value. See AWS EFS lifecycle policy documentation for allowed AFTER_* values."
  }
}

variable "lifecycle_policy_transition_to_primary_storage_class" {
  description = "Describes the policy used to transition a file from IA storage to primary storage. Valid value: AFTER_1_ACCESS"
  type        = string
  default     = null

  validation {
    condition     = var.lifecycle_policy_transition_to_primary_storage_class == null || var.lifecycle_policy_transition_to_primary_storage_class == "AFTER_1_ACCESS"
    error_message = "transition_to_primary_storage_class only supports the value 'AFTER_1_ACCESS'."
  }
}

variable "lifecycle_policy_transition_to_archive" {
  description = "How long before transitioning files to the Archive storage class. Valid values: AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, AFTER_365_DAYS"
  type        = string
  default     = null

  validation {
    condition = var.lifecycle_policy_transition_to_archive == null || contains([
      "AFTER_1_DAY", "AFTER_7_DAYS", "AFTER_14_DAYS", "AFTER_30_DAYS", "AFTER_60_DAYS",
      "AFTER_90_DAYS", "AFTER_180_DAYS", "AFTER_270_DAYS", "AFTER_365_DAYS"
    ], coalesce(var.lifecycle_policy_transition_to_archive, "none"))
    error_message = "Invalid transition_to_archive value. See AWS EFS lifecycle policy documentation for allowed AFTER_* values."
  }
}

variable "enable_replication_overwrite_protection" {
  description = "Enable replication overwrite protection to prevent accidental deletion of replicated file systems"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for mount targets. Leave empty to create a file system with no mount targets (e.g. a replication destination)."
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "List of existing security group IDs to attach to mount targets (in addition to the one created when create_security_group is true)."
  type        = list(string)
  default     = []
}

variable "mount_target_ip_addresses" {
  description = "Map of subnet IDs to specific IP addresses for mount targets. If not specified, an available IP is automatically assigned"
  type        = map(string)
  default     = {}

  validation {
    condition     = alltrue([for subnet in keys(var.mount_target_ip_addresses) : contains(var.subnet_ids, subnet)])
    error_message = "Every key in mount_target_ip_addresses must be one of subnet_ids (otherwise the IP override is silently ignored)."
  }
}

variable "enable_backup_policy" {
  description = "Whether to enable automatic backups"
  type        = bool
  default     = true
}

variable "file_system_policy" {
  description = "JSON formatted file system policy for the EFS file system"
  type        = string
  default     = null
}

variable "bypass_policy_lockout_safety_check" {
  description = "Whether to bypass the policy lockout safety check. Set to true only if you intend to prevent the principal making the API call from making future PutFileSystemPolicy calls"
  type        = bool
  default     = false
}

variable "access_points" {
  description = "Map of access point definitions to create"
  type = map(object({
    posix_user = optional(object({
      gid            = number
      uid            = number
      secondary_gids = optional(list(number))
    }))
    root_directory = optional(object({
      path = optional(string)
      creation_info = optional(object({
        owner_gid   = number
        owner_uid   = number
        permissions = string
      }))
    }))
    tags = optional(map(string))
  }))
  default = {}

  # root_directory.creation_info.permissions must be a 3- or 4-digit octal mode.
  validation {
    condition = alltrue([
      for k, ap in var.access_points :
      ap.root_directory == null || ap.root_directory.creation_info == null ||
      can(regex("^[0-7]{3,4}$", ap.root_directory.creation_info.permissions))
    ])
    error_message = "access_points[*].root_directory.creation_info.permissions must be a 3- or 4-digit octal string (e.g. \"0755\")."
  }

  # POSIX uid/gid (and creation_info owner ids, and secondary gids) must be in
  # the valid 0..4294967295 range.
  validation {
    condition = alltrue(flatten([
      for k, ap in var.access_points : concat(
        ap.posix_user == null ? [] : [
          ap.posix_user.uid >= 0 && ap.posix_user.uid <= 4294967295,
          ap.posix_user.gid >= 0 && ap.posix_user.gid <= 4294967295,
        ],
        ap.posix_user == null || ap.posix_user.secondary_gids == null ? [] : [
          for g in ap.posix_user.secondary_gids : g >= 0 && g <= 4294967295
        ],
        ap.root_directory == null || ap.root_directory.creation_info == null ? [] : [
          ap.root_directory.creation_info.owner_uid >= 0 && ap.root_directory.creation_info.owner_uid <= 4294967295,
          ap.root_directory.creation_info.owner_gid >= 0 && ap.root_directory.creation_info.owner_gid <= 4294967295,
        ],
      )
    ]))
    error_message = "access_points POSIX uid/gid values (posix_user, secondary_gids, creation_info owners) must be between 0 and 4294967295."
  }
}

variable "replication_configuration" {
  description = "Replication configuration for the EFS file system. Specify region or availability_zone_name (for One Zone file systems)"
  type = object({
    region                 = optional(string)
    availability_zone_name = optional(string)
    kms_key_id             = optional(string)
    file_system_id         = optional(string)
  })
  default = null
}

variable "create_security_group" {
  description = "Whether to create a security group for EFS"
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID where the security group will be created. Required if create_security_group is true"
  type        = string
  default     = null

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
  }
}

variable "allowed_cidr_blocks" {
  description = "List of IPv4 CIDR blocks allowed to reach EFS on the NFS port (2049)"
  type        = list(string)
  default     = []
}

variable "allowed_ipv6_cidr_blocks" {
  description = "List of IPv6 CIDR blocks allowed to reach EFS on the NFS port (2049)"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to reach EFS on the NFS port (2049)"
  type        = list(string)
  default     = []
}

# ============================================================================
# FILE SYSTEM POLICY HELPERS
# ============================================================================

variable "enforce_in_transit_encryption" {
  description = "Attach a file system policy that denies any access not using TLS (aws:SecureTransport). Ignored when file_system_policy is set explicitly."
  type        = bool
  default     = false

  validation {
    condition     = !(var.enforce_in_transit_encryption && var.file_system_policy != null)
    error_message = "Set either enforce_in_transit_encryption or file_system_policy, not both."
  }
}

# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for the file system (burst credit balance and percent IO limit, where applicable)"
  type        = bool
  default     = false
}

variable "alarm_burst_credit_balance_threshold" {
  description = "Alarm when BurstCreditBalance (bytes) drops below this value. Only created for bursting throughput mode. Default ~192 GiB."
  type        = number
  default     = 206158430208

  validation {
    condition     = var.alarm_burst_credit_balance_threshold > 0
    error_message = "alarm_burst_credit_balance_threshold must be greater than 0."
  }
}

variable "alarm_percent_io_limit_threshold" {
  description = "Alarm when PercentIOLimit exceeds this percentage. Only created for generalPurpose performance mode."
  type        = number
  default     = 95

  validation {
    condition     = var.alarm_percent_io_limit_threshold > 0 && var.alarm_percent_io_limit_threshold <= 100
    error_message = "alarm_percent_io_limit_threshold must be between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for the CloudWatch alarms"
  type        = number
  default     = 3
}

variable "alarm_period" {
  description = "Period in seconds over which each CloudWatch alarm statistic is evaluated"
  type        = number
  default     = 300
}

variable "alarm_actions" {
  description = "List of ARNs (e.g. SNS topics) to notify when an alarm enters ALARM state"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs (e.g. SNS topics) to notify when an alarm returns to OK state"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
