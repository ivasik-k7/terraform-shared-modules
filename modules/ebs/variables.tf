###############################################################################
# General
###############################################################################

variable "name" {
  description = "Name prefix applied to all resources created by this module (volumes, KMS alias, DLM policy, alarms)"
  type        = string
}

variable "tags" {
  description = "A map of tags applied to every resource created by this module"
  type        = map(string)
  default     = {}
}

###############################################################################
# Volumes
###############################################################################

variable "volumes" {
  description = <<-EOT
    Map of EBS volumes to create. The map key is used as a logical name and is
    embedded in the volume's Name tag. Each volume is independently configurable
    and may optionally be attached to an instance.

    Object attributes:
      availability_zone   - AZ in which to create the volume. Falls back to var.availability_zone.
      size                - Size in GiB. Optional when restoring from a snapshot.
      type                - Volume type: gp3 (default), gp2, io1, io2, st1, sc1, standard.
      iops                - Provisioned IOPS. Required for io1/io2, optional for gp3.
      throughput          - Throughput in MiB/s. gp3 only (125-1000).
      encrypted           - Override the module-level encryption setting for this volume.
      kms_key_id          - Override the module-level KMS key for this volume.
      snapshot_id         - Snapshot ID to restore the volume from.
      multi_attach_enabled- Enable Multi-Attach (io1/io2 only).
      outpost_arn         - ARN of the Outpost to create the volume on.
      final_snapshot      - Take a final snapshot before deletion.
      instance_id         - Single-instance attachment shortcut. When set, an attachment is created.
      device_name         - Device name for the single-instance attachment (e.g. /dev/sdh). Required when instance_id is set.
      stop_instance_before_detaching - Stop the instance before detaching the single-instance attachment (safer detach).
      force_detach        - Force detachment of the single-instance attachment on destroy. Use with caution; may corrupt data.
      skip_destroy        - Do not detach the single-instance attachment on destroy (leave it attached).
      attachments         - List of additional attachment targets. Use this (or combine with instance_id) to attach
                            an io1/io2 Multi-Attach volume to multiple instances. All target instances must be in
                            the same Availability Zone as the volume. Each entry:
                              instance_id                    - Instance to attach to (required).
                              device_name                    - Device name (required).
                              stop_instance_before_detaching - Stop instance before detaching (default true).
                              force_detach                   - Force detach on destroy (default false).
                              skip_destroy                   - Leave attached on destroy (default false).
      managed_by_dlm      - Include this volume in the DLM snapshot lifecycle policy (default true).
      tags                - Additional tags merged onto this specific volume.
  EOT
  type = map(object({
    availability_zone              = optional(string)
    size                           = optional(number)
    type                           = optional(string, "gp3")
    iops                           = optional(number)
    throughput                     = optional(number)
    encrypted                      = optional(bool)
    kms_key_id                     = optional(string)
    snapshot_id                    = optional(string)
    multi_attach_enabled           = optional(bool, false)
    outpost_arn                    = optional(string)
    final_snapshot                 = optional(bool, false)
    instance_id                    = optional(string)
    device_name                    = optional(string)
    stop_instance_before_detaching = optional(bool, true)
    force_detach                   = optional(bool, false)
    skip_destroy                   = optional(bool, false)
    attachments = optional(list(object({
      instance_id                    = string
      device_name                    = string
      stop_instance_before_detaching = optional(bool, true)
      force_detach                   = optional(bool, false)
      skip_destroy                   = optional(bool, false)
    })), [])
    managed_by_dlm = optional(bool, true)
    tags           = optional(map(string), {})
  }))
  default = {}

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      contains(["gp2", "gp3", "io1", "io2", "st1", "sc1", "standard"], v.type)
    ])
    error_message = "Each volume type must be one of: gp2, gp3, io1, io2, st1, sc1, standard."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.size != null || v.snapshot_id != null
    ])
    error_message = "Each volume must specify either size or snapshot_id."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.throughput == null || v.type == "gp3"
    ])
    error_message = "throughput is only valid for gp3 volumes."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.iops == null || contains(["gp3", "io1", "io2"], v.type)
    ])
    error_message = "iops is only valid for gp3, io1, and io2 volumes."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      !contains(["io1", "io2"], v.type) || v.iops != null
    ])
    error_message = "iops is required for io1 and io2 volumes."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.throughput == null || (v.throughput >= 125 && v.throughput <= 1000)
    ])
    error_message = "gp3 throughput must be between 125 and 1000 MiB/s."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.multi_attach_enabled == false || contains(["io1", "io2"], v.type)
    ])
    error_message = "multi_attach_enabled is only supported for io1 and io2 volumes."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      v.instance_id == null || v.device_name != null
    ])
    error_message = "device_name is required when instance_id is set."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      (length(v.attachments) + (v.instance_id != null ? 1 : 0)) <= 1
      || (contains(["io1", "io2"], v.type) && v.multi_attach_enabled)
    ])
    error_message = "Attaching a volume to more than one instance requires type io1/io2 with multi_attach_enabled = true."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      length(distinct(concat(
        v.instance_id != null ? [v.instance_id] : [],
        [for a in v.attachments : a.instance_id]
      ))) == (length(v.attachments) + (v.instance_id != null ? 1 : 0))
    ])
    error_message = "A volume cannot be attached to the same instance twice (duplicate instance_id across instance_id and attachments)."
  }

  validation {
    condition = alltrue([
      for v in values(var.volumes) :
      !contains(["st1", "sc1"], v.type) || v.size == null || v.size >= 125
    ])
    error_message = "st1 and sc1 volumes require a minimum size of 125 GiB."
  }
}

variable "availability_zone" {
  description = "Default Availability Zone for volumes that do not specify one. Required if any volume omits availability_zone"
  type        = string
  default     = null
}

###############################################################################
# Encryption (KMS)
###############################################################################

variable "encrypted" {
  description = "Module-level default for volume encryption. Individual volumes may override via volumes[*].encrypted"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "ARN or ID of an existing KMS key used to encrypt volumes. If null and create_kms_key is false, the default AWS-managed EBS key (aws/ebs) is used"
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Whether to create a dedicated customer-managed KMS key for encrypting these volumes"
  type        = bool
  default     = false
}

variable "kms_key_deletion_window_in_days" {
  description = "Waiting period, in days, before the created KMS key is deleted after destruction"
  type        = number
  default     = 30

  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days."
  }
}

variable "kms_key_enable_rotation" {
  description = "Whether to enable automatic annual key rotation on the created KMS key"
  type        = bool
  default     = true
}

variable "kms_key_policy" {
  description = "JSON formatted policy document for the created KMS key. If null, a default policy is generated (account root + any kms_key_additional_principals)"
  type        = string
  default     = null
}

variable "kms_key_additional_principals" {
  description = <<-EOT
    List of IAM principal ARNs (roles/users) granted use of the created CMK in the
    default key policy. Add the ECS instance role and/or the Auto Scaling
    service-linked role here so instances can attach volumes encrypted with this key.
    Ignored when a custom kms_key_policy is supplied.
  EOT
  type        = list(string)
  default     = []
}

###############################################################################
# DLM (automated snapshot lifecycle)
###############################################################################

variable "create_lifecycle_policy" {
  description = "Whether to create a Data Lifecycle Manager (DLM) policy for automated, scheduled snapshots of the volumes"
  type        = bool
  default     = false
}

variable "create_dlm_role" {
  description = "Whether to create the IAM role DLM assumes. Set to false to supply an existing role via dlm_role_arn"
  type        = bool
  default     = true
}

variable "dlm_role_arn" {
  description = "ARN of an existing IAM role for DLM to assume. Required when create_lifecycle_policy is true and create_dlm_role is false"
  type        = string
  default     = null
}

variable "lifecycle_policy_description" {
  description = "Description for the DLM lifecycle policy. Defaults to a generated description based on var.name"
  type        = string
  default     = null
}

variable "lifecycle_policy_state" {
  description = "State of the DLM lifecycle policy. Valid values: ENABLED, DISABLED"
  type        = string
  default     = "ENABLED"

  validation {
    condition     = contains(["ENABLED", "DISABLED"], var.lifecycle_policy_state)
    error_message = "lifecycle_policy_state must be ENABLED or DISABLED."
  }
}

variable "snapshot_schedules" {
  description = <<-EOT
    Map of DLM snapshot schedules to apply to the volumes managed by this module.
    The map key is the schedule name.

    Object attributes:
      interval         - Snapshot creation interval. Valid: 1, 2, 3, 4, 6, 8, 12, 24.
      interval_unit    - HOURS (default).
      times            - List of start times in HH:MM format (UTC), e.g. ["03:00"].
      retain_count     - Number of snapshots to retain.
      copy_tags        - Copy volume tags onto snapshots (default true).
      tags_to_add      - Extra tags applied to created snapshots.
      cross_region_copy - Optional list of cross-region copy rules:
        target        - Destination region.
        encrypted     - Encrypt the copy (default true).
        cmk_arn       - KMS key ARN in the destination region.
        retain_count  - Retention for the copied snapshots.
  EOT
  type = map(object({
    interval      = optional(number, 24)
    interval_unit = optional(string, "HOURS")
    times         = optional(list(string), ["03:00"])
    retain_count  = optional(number, 7)
    copy_tags     = optional(bool, true)
    tags_to_add   = optional(map(string), {})
    cross_region_copy = optional(list(object({
      target       = string
      encrypted    = optional(bool, true)
      cmk_arn      = optional(string)
      retain_count = number
    })), [])
  }))
  default = {
    daily = {
      interval     = 24
      times        = ["03:00"]
      retain_count = 7
    }
  }

  validation {
    condition = alltrue([
      for s in values(var.snapshot_schedules) :
      contains([1, 2, 3, 4, 6, 8, 12, 24], s.interval)
    ])
    error_message = "snapshot_schedules interval must be one of: 1, 2, 3, 4, 6, 8, 12, 24."
  }

  validation {
    condition = alltrue([
      for s in values(var.snapshot_schedules) :
      s.retain_count >= 1 && s.retain_count <= 1000
    ])
    error_message = "snapshot_schedules retain_count must be between 1 and 1000."
  }
}

###############################################################################
# CloudWatch alarms (resilience / observability)
###############################################################################

variable "create_cloudwatch_alarms" {
  description = "Whether to create CloudWatch alarms monitoring volume health (idle time / burst balance)"
  type        = bool
  default     = false
}

variable "alarm_actions" {
  description = "List of ARNs (e.g. SNS topics) to notify when an alarm transitions to ALARM"
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs to notify when an alarm transitions back to OK"
  type        = list(string)
  default     = []
}

variable "burst_balance_alarm_threshold" {
  description = "BurstBalance percentage below which the alarm triggers. Only applies to gp2/st1/sc1 volumes"
  type        = number
  default     = 20
}

variable "enable_idle_alarm" {
  description = <<-EOT
    Whether to create the idle-volume alarm (gated by create_cloudwatch_alarms).
    This is a coarse FinOps heuristic that flags volumes with sustained idle time
    — useful for spotting detached-but-paid-for volumes, but it can false-positive
    on legitimately quiet volumes. Disable it for low-traffic volumes.
  EOT
  type        = bool
  default     = true
}

variable "idle_alarm_threshold_seconds" {
  description = "VolumeIdleTime (seconds, out of each 300s period) above which the idle alarm triggers"
  type        = number
  default     = 290
}

variable "idle_alarm_evaluation_periods" {
  description = "Number of consecutive 5-minute periods the idle threshold must be breached before alarming"
  type        = number
  default     = 12
}
