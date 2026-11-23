variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of what the module names: the severity topics <name>-<severity>, the queue, the pipes and the forwarding rules."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on every resource. The module adds ManagedBy and Module last."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "kms_key_arn" {
  description = "Customer managed key for the topics and the queue. Empty: AWS-managed encryption for the queue, none for the topics. Requirements in output.kms_key_policy_requirements."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.kms_key_arn))
    error_message = "kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the roles the module creates (the pipes', the forwarding rules'). Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

variable "emails" {
  description = "Owners subscribed to each severity's topic in this account, by severity (info, warning, high, critical). Each confirms the subscription."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.emails : contains(["info", "warning", "high", "critical"], k) ? alltrue([for e in v : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))]) : false])
    error_message = "emails must be keyed by info, warning, high or critical, with e-mail addresses."
  }
}

variable "control_plane_bus_arn" {
  description = "The keel-control-plane event bus. Set: everything published to the severity topics, and the alarms and anomaly events selected in forward, reach it. Empty: signals stay in this account."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.control_plane_bus_arn == "" ? true : can(regex("^arn:aws[a-z-]*:events:[a-z0-9-]+:[0-9]{12}:event-bus/.+$", var.control_plane_bus_arn))
    error_message = "control_plane_bus_arn must be empty or an EventBridge event bus ARN."
  }
}

variable "forward" {
  description = <<-EOT
    What else goes to the control plane, besides the severity topics.
      alarm_name_prefixes   CloudWatch alarms entering ALARM whose names start with one of these
      anomalies             Cost Anomaly Detection's Anomaly Detected events (management account, us-east-1)
  EOT
  type = object({
    alarm_name_prefixes = optional(list(string), [])
    anomalies           = optional(bool, false)
  })
  default  = {}
  nullable = false
}
