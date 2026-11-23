variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of what the module names: budgets <name>-<limit>, anomaly monitors, lock policies and roles."
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

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\")."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.acknowledged_checks : contains(["production_changes_only_by_people", "every_limit_has_an_owner"], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the roles AWS Budgets uses to run lock actions. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

variable "topic_arns" {
  description = "SNS topics by severity (info, warning, high, critical), from keel-signals: each threshold of each limit notifies the topic of its severity, which forwards to the control plane."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.topic_arns : contains(["info", "warning", "high", "critical"], k) ? can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:.+$", v)) : false])
    error_message = "topic_arns must be keyed by info, warning, high or critical, with SNS topic ARNs."
  }
}

variable "tiers" {
  description = <<-EOT
    Defaults by tier, which each limit picks with tier and may override.
      forecast_thresholds   percent of the limit the forecast may reach before a WARNING
      actual_thresholds     percent of the limit actual spend may reach before an alert: under 100 WARNING,
                            from 100 HIGH, from critical_at_percent CRITICAL
      automatic_actions     whether a lock may run without a person approving it
      anomaly_min_impact    a limit's anomaly monitor alerts from this impact, unless the limit sets its own
      anomaly_severity      the topic its anomaly alerts go to
  EOT
  type = map(object({
    forecast_thresholds = list(number)
    actual_thresholds   = list(number)
    critical_at_percent = number
    automatic_actions   = bool
    anomaly_min_impact  = number
    anomaly_severity    = string
  }))
  default = {
    production = {
      forecast_thresholds = [80, 100]
      actual_thresholds   = [90, 100, 120]
      critical_at_percent = 120
      automatic_actions   = false
      anomaly_min_impact  = 500
      anomaly_severity    = "high"
    }
    non-production = {
      forecast_thresholds = [80, 100]
      actual_thresholds   = [100, 150]
      critical_at_percent = 150
      automatic_actions   = true
      anomaly_min_impact  = 100
      anomaly_severity    = "warning"
    }
    sandbox = {
      forecast_thresholds = [100]
      actual_thresholds   = [80, 100]
      critical_at_percent = 100
      automatic_actions   = true
      anomaly_min_impact  = 50
      anomaly_severity    = "warning"
    }
  }
  nullable = false

  validation {
    condition = alltrue([for k, t in var.tiers : alltrue([
      can(regex("^[a-z][a-z0-9-]{0,30}$", k)),
      alltrue([for p in concat(t.forecast_thresholds, t.actual_thresholds) : p > 0 ? p <= 1000 : false]),
      length(t.forecast_thresholds) + length(t.actual_thresholds) > 0,
      length(t.forecast_thresholds) + length(t.actual_thresholds) <= 10,
      t.critical_at_percent > 0, t.anomaly_min_impact >= 0,
      contains(["info", "warning", "high", "critical"], t.anomaly_severity),
    ])])
    error_message = "tiers: keys lowercase; thresholds percentages above 0, one to ten in all; critical_at_percent above 0; anomaly_min_impact 0 or more; anomaly_severity info, warning, high or critical."
  }
}

variable "limits" {
  description = <<-EOT
    Limits, keyed by a short name: a platform, a team, a service line, a commitment target. Each is an AWS budget with
    alerts by severity, and optionally its own anomaly monitor and a lock at the limit. Budgets are free; a lock (budget
    action) costs $0.10 a day after the first two in the account (COSTS.md).
      type           COST (default), USAGE, SAVINGS_PLANS_COVERAGE, SAVINGS_PLANS_UTILIZATION, RI_COVERAGE, RI_UTILIZATION
      scope          what the limit counts; every field narrows it (AND): tags (key => values; the key must be an
                     active cost allocation tag), cost_categories (name => values), accounts, services (Cost
                     Explorer names), regions, usage_types, usage_type_groups. Empty: everything the account sees
      amount, unit   COST: the limit in a currency; USAGE: in the usage unit (GB, Hrs)
      auto_adjust_months  COST, 1-60: the limit follows the average of that many past months instead of amount
      target_percent commitment types: alert when coverage or utilization falls below it
      period         MONTHLY, QUARTERLY or ANNUALLY
      metric         COST: AmortizedCost (default), UnblendedCost, NetAmortizedCost, NetUnblendedCost, BlendedCost
      tier           the defaults it takes (var.tiers)
      owners         e-mails told directly at every threshold, besides the severity topics
      anomaly        a monitor on exactly this scope (one tag key, one cost category, or up to ten accounts), alerting
                     from min_impact (default: the tier's)
      action         at at_percent of actual spend: attach a deny policy to lock_roles (denied_actions: by default the
                     actions that start new spend), or apply an SCP (scp, management account only). approval
                     AUTOMATIC or MANUAL; production tiers expect MANUAL
  EOT
  type = map(object({
    type = optional(string, "COST")
    tier = optional(string, "production")
    scope = optional(object({
      tags              = optional(map(list(string)), {})
      cost_categories   = optional(map(list(string)), {})
      accounts          = optional(list(string), [])
      services          = optional(list(string), [])
      regions           = optional(list(string), [])
      usage_types       = optional(list(string), [])
      usage_type_groups = optional(list(string), [])
    }), {})
    amount              = optional(string, "")
    unit                = optional(string, "USD")
    auto_adjust_months  = optional(number, 0)
    target_percent      = optional(number, 0)
    period              = optional(string, "MONTHLY")
    metric              = optional(string, "AmortizedCost")
    forecast_thresholds = optional(list(number))
    actual_thresholds   = optional(list(number))
    owners              = optional(list(string), [])
    anomaly = optional(object({
      min_impact            = optional(number)
      min_impact_percentage = optional(number, 0)
    }))
    action = optional(object({
      at_percent     = optional(number, 100)
      approval       = optional(string, "AUTOMATIC")
      lock_roles     = optional(list(string), [])
      denied_actions = optional(list(string))
      scp = optional(object({
        policy_id  = string
        target_ids = list(string)
      }))
    }))
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for k, l in var.limits : alltrue([
      can(regex("^[a-z][a-z0-9-]{0,40}$", k)),
      contains(["COST", "USAGE", "SAVINGS_PLANS_COVERAGE", "SAVINGS_PLANS_UTILIZATION", "RI_COVERAGE", "RI_UTILIZATION"], l.type),
      contains(["MONTHLY", "QUARTERLY", "ANNUALLY"], l.period),
      contains(["AmortizedCost", "UnblendedCost", "NetAmortizedCost", "NetUnblendedCost", "BlendedCost"], l.metric),
      contains(keys(var.tiers), l.tier),
      length(l.owners) <= 10,
      alltrue([for a in l.scope.accounts : can(regex("^[0-9]{12}$", a))]),
      l.auto_adjust_months >= 0, l.auto_adjust_months <= 60, floor(l.auto_adjust_months) == l.auto_adjust_months,
      l.auto_adjust_months == 0 ? true : l.type == "COST",
      startswith(l.metric, "Net") ? length(l.scope.tags) + length(l.scope.cost_categories) + length(l.scope.accounts) + length(l.scope.services) + length(l.scope.regions) + length(l.scope.usage_types) + length(l.scope.usage_type_groups) > 0 : true,
    ])])
    error_message = "limits: keys lowercase; type COST, USAGE or a commitment type; period MONTHLY, QUARTERLY or ANNUALLY; metric a cost metric; tier one of var.tiers; at most ten owners; accounts 12-digit IDs; auto_adjust_months a whole number 0-60, on COST limits only; the Net metrics only with a scope (an unscoped budget sets its cost basis through cost types, which have no net option)."
  }

  validation {
    condition     = alltrue([for k, l in var.limits : contains(["COST", "USAGE"], l.type) ? (l.auto_adjust_months > 0 ? true : can(regex("^[0-9]+(\\.[0-9]+)?$", l.amount))) : (l.target_percent > 0 ? l.target_percent <= 100 : false)])
    error_message = "limits: COST and USAGE limits need an amount (or auto_adjust_months); commitment limits need target_percent 1-100."
  }

  validation {
    condition = alltrue([for k, l in var.limits : alltrue([
      l.type == "USAGE" ? length(l.scope.usage_types) + length(l.scope.usage_type_groups) > 0 : true,
      startswith(l.type, "RI_") ? length(l.scope.services) == 1 : true,
      startswith(l.type, "SAVINGS_PLANS") || startswith(l.type, "RI_") ? (l.action == null ? l.anomaly == null : false) : true,
    ])])
    error_message = "limits: USAGE needs usage_types or usage_type_groups; RI types need exactly one service; commitment limits take no action and no anomaly monitor."
  }

  validation {
    condition = alltrue([for k, l in var.limits : l.action == null ? true : alltrue([
      contains(["AUTOMATIC", "MANUAL"], l.action.approval),
      l.action.at_percent > 0, l.action.at_percent <= 1000,
      length(l.action.lock_roles) > 0 ? l.action.scp == null : l.action.scp != null,
      alltrue([for r in l.action.lock_roles : can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", r))]),
      l.type == "COST",
    ])])
    error_message = "limits[*].action: on COST limits only; approval AUTOMATIC or MANUAL; at_percent above 0; either lock_roles (IAM role names) or scp, not both."
  }
}
