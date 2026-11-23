variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of what the module names: the event bus, its rules, the severity topics, the evidence bucket and stream."
  type        = string
  default     = "keel"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 2-21 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on every resource. The module adds ManagedBy and Module last."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name: this module's (README) and modules/s3's for the evidence bucket (access_is_logged, data_uses_a_customer_key)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.acknowledged_checks : contains(["evidence_is_immutable", "every_severity_reaches_someone", "access_is_logged", "data_uses_a_customer_key"], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

variable "kms_key_arn" {
  description = "Customer managed key for the severity topics, the evidence stream and bucket, and the dead-letter queue. Empty: AWS-owned or AWS-managed keys. Requirements in output.kms_key_policy_requirements."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the roles the module creates (EventBridge to Firehose, Firehose to S3). Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

# ---------------------------------------------------------------------------
# Who may send
# ---------------------------------------------------------------------------

variable "sources" {
  description = <<-EOT
    Who may put events on the bus: every account of an organization, listed accounts, or both. keel-signals forwards
    with a role from each account and Region (keel-billing's anomalies, every account's severity topics).
  EOT
  type = object({
    organization_id = optional(string, "")
    account_ids     = optional(list(string), [])
  })
  nullable = false

  validation {
    condition = alltrue([
      var.sources.organization_id == "" ? true : can(regex("^o-[a-z0-9]{10,32}$", var.sources.organization_id)),
      alltrue([for a in var.sources.account_ids : can(regex("^[0-9]{12}$", a))]),
      var.sources.organization_id != "" ? true : length(var.sources.account_ids) > 0,
    ])
    error_message = "sources: an organization_id (o-...) or one or more 12-digit account_ids."
  }
}

# ---------------------------------------------------------------------------
# Severity
# ---------------------------------------------------------------------------

variable "severity" {
  description = <<-EOT
    How signals map to INFO, WARNING, HIGH and CRITICAL, and who hears each.
      anomaly_warning, anomaly_high, anomaly_critical   a cost anomaly's total impact (in the bill's currency) from
                        which it is WARNING, HIGH, CRITICAL; below the first it is INFO
      critical_alarm_suffix   alarms whose name ends with this are CRITICAL (keel-team's burn meter); every other
                        alarm that reaches the bus is HIGH
      emails            per severity, addresses subscribed to its topic (each confirms). Chat and paging tools
                        subscribe to output.topic_arns outside this module
    Events of source "keel" with detail.severity (info, warning, high, critical), and keel-signals' events of source
    keel.<severity>, are routed as they say.
  EOT
  type = object({
    anomaly_warning       = optional(number, 100)
    anomaly_high          = optional(number, 1000)
    anomaly_critical      = optional(number, 5000)
    critical_alarm_suffix = optional(string, "-ai-burn")
    emails                = optional(map(list(string)), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.severity.anomaly_warning > 0,
      var.severity.anomaly_high > var.severity.anomaly_warning,
      var.severity.anomaly_critical > var.severity.anomaly_high,
      var.severity.critical_alarm_suffix != "",
      alltrue([for k, v in var.severity.emails : contains(["info", "warning", "high", "critical"], k)]),
    ])
    error_message = "severity: 0 < anomaly_warning < anomaly_high < anomaly_critical; a critical_alarm_suffix; emails keyed by info, warning, high or critical."
  }
}

# ---------------------------------------------------------------------------
# Evidence
# ---------------------------------------------------------------------------

variable "evidence" {
  description = <<-EOT
    Every event on the bus is kept: streamed by Data Firehose to an S3 bucket with Object Lock, so no one can
    change or delete it before retention_days, and archived on the bus for replay.
      mode                  GOVERNANCE (users with s3:BypassGovernanceRetention may remove) or COMPLIANCE (nobody,
                            not even root). Start with GOVERNANCE; COMPLIANCE cannot be undone
      retention_days        how long each record is locked; the bucket deletes it after that
      archive_days          how long the bus keeps events for replay (0: forever)
    The volume is small: a few kilobytes per alert (COSTS.md).
  EOT
  type = object({
    mode           = optional(string, "GOVERNANCE")
    retention_days = optional(number, 2557)
    archive_days   = optional(number, 90)
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains(["GOVERNANCE", "COMPLIANCE"], var.evidence.mode),
      var.evidence.retention_days >= 1, floor(var.evidence.retention_days) == var.evidence.retention_days,
      var.evidence.archive_days >= 0, floor(var.evidence.archive_days) == var.evidence.archive_days,
    ])
    error_message = "evidence: mode GOVERNANCE or COMPLIANCE; retention_days a whole number 1 or more; archive_days a whole number 0 or more."
  }
}
