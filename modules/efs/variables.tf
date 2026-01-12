variable "name" {
  description = "Name of the EFS file system"
  type        = string
}

variable "creation_token" {
  description = "A unique name used as reference when creating the EFS. If not provided, uses the name variable"
  type        = string
  default     = null
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
}

variable "availability_zone_name" {
  description = "The AWS Availability Zone in which to create the file system. Used to create a one-zone file system"
  type        = string
  default     = null
}

variable "lifecycle_policy_transition_to_ia" {
  description = "Indicates how long it takes to transition files to the IA storage class. Valid values: AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, or AFTER_90_DAYS"
  type        = string
  default     = null
}

variable "lifecycle_policy_transition_to_primary_storage_class" {
  description = "Describes the policy used to transition a file from IA storage to primary storage. Valid values: AFTER_1_ACCESS"
  type        = string
  default     = null
}

variable "lifecycle_policy_transition_to_archive" {
  description = "Indicates how long it takes to transition files to Archive storage class. Valid values: AFTER_1_DAY, AFTER_7_DAYS, AFTER_14_DAYS, AFTER_30_DAYS, AFTER_60_DAYS, AFTER_90_DAYS, AFTER_180_DAYS, AFTER_270_DAYS, or AFTER_365_DAYS"
  type        = string
  default     = null
}

variable "enable_replication_overwrite_protection" {
  description = "Enable replication overwrite protection to prevent accidental deletion of replicated file systems"
  type        = bool
  default     = false
}

variable "subnet_ids" {
  description = "List of subnet IDs for mount targets"
  type        = list(string)
}

variable "security_group_ids" {
  description = "List of security group IDs to attach to mount targets"
  type        = list(string)
}

variable "mount_target_ip_addresses" {
  description = "Map of subnet IDs to specific IP addresses for mount targets. If not specified, an available IP is automatically assigned"
  type        = map(string)
  default     = {}
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
}

variable "allowed_cidr_blocks" {
  description = "List of CIDR blocks allowed to access EFS"
  type        = list(string)
  default     = []
}

variable "allowed_security_group_ids" {
  description = "List of security group IDs allowed to access EFS"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "A map of tags to add to all resources"
  type        = map(string)
  default     = {}
}
