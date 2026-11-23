# ---------------------------------------------------------------------------
# The team
# ---------------------------------------------------------------------------

variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "components" {
  description = <<-EOT
    What this call creates, so one account spanning Regions takes one call per Region.
      account   once per account: the limits (budgets are global) and the FinOps read-only role
      region    in every Region the team uses: the severity topics and their forwarding, AI inference profiles
                and the burn meter, quotas, invocation logs, schedules
    The account part needs the region part in the same call: limits notify that Region's topics.
  EOT
  type = object({
    account = optional(bool, true)
    region  = optional(bool, true)
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.components.region
    error_message = "components.region must be true: every call creates the Region's severity topics, which the account part's limits notify."
  }
}

variable "team" {
  description = "The team's short name: the prefix of everything the module names, and the Team tag on it."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,24}$", var.team))
    error_message = "team must be 2-25 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "cost_centre" {
  description = "The cost centre the team's spend is charged to. Tagged on everything the module creates; must hold no personal data."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9_.:/=+@ -]{0,63}$", var.cost_centre))
    error_message = "cost_centre must be 1-64 tag-value characters."
  }
}

variable "tier" {
  description = "The default tier of the team's limits and platforms (keel-limits tiers): production, non-production or sandbox. A limit or platform may set its own."
  type        = string
  default     = "production"
  nullable    = false

  validation {
    condition     = contains(length(var.tiers) > 0 ? keys(var.tiers) : ["production", "non-production", "sandbox"], var.tier)
    error_message = "tier must be one of the tiers: production, non-production or sandbox, or a key of var.tiers."
  }
}

variable "tiers" {
  description = "Tier defaults passed to keel-limits. Empty: keel-limits' production, non-production and sandbox."
  type = map(object({
    forecast_thresholds = list(number)
    actual_thresholds   = list(number)
    critical_at_percent = number
    automatic_actions   = bool
    anomaly_min_impact  = number
    anomaly_severity    = string
  }))
  default  = {}
  nullable = false
}

variable "emails" {
  description = "Owners subscribed to the team's severity topics, by severity (info, warning, high, critical). Each confirms the subscription. Applies in every Region this module creates topics in."
  type        = map(list(string))
  default     = {}
  nullable    = false
}

variable "tags" {
  description = "Tags on everything the module creates. The module adds Team, CostCentre, ManagedBy and Module last."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name: this module's and keel-limits' (README, \"Advisory checks\")."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for c in var.acknowledged_checks : contains([
      "every_account_has_a_limit", "sandboxes_lock_at_their_limit", "somebody_hears_the_team", "ai_burn_is_metered",
      "ai_invocations_are_logged", "signals_reach_the_control_plane", "production_changes_only_by_people", "every_limit_has_an_owner",
    ], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for every role the module creates. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

# ---------------------------------------------------------------------------
# Limits
# ---------------------------------------------------------------------------

variable "limits" {
  description = <<-EOT
    The account's limits, passed to keel-limits (its README lists the fields): the whole account (scope left empty),
    a service line, data transfer, a commitment target. One with an empty scope is the account's budget (FC-01).
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.limits)) ? alltrue([for k in keys(var.limits) : !startswith(k, "platform-") ? !startswith(k, "ai-") : false]) : false
    error_message = "limits must be a map of keel-limits limit objects; the prefixes platform- and ai- are the module's own (platforms, ai.applications)."
  }
}

variable "platform_tag_key" {
  description = "The cost allocation tag that says which platform a resource belongs to. It must be active in billing (keel-billing) and required on resources (keel-guardrails)."
  type        = string
  default     = "Platform"
  nullable    = false

  validation {
    condition     = can(regex("^[\\p{L}\\p{N}\\s_.:/=+@-]{1,128}$", var.platform_tag_key)) ? !startswith(lower(var.platform_tag_key), "aws:") : false
    error_message = "platform_tag_key must be a tag key, not starting with aws:."
  }
}

variable "platforms" {
  description = <<-EOT
    Platforms sharing this account, each with its own limit on the spend tagged platform_tag_key = <key>. The fields
    are keel-limits' (amount, period, tier, owners, anomaly, action, thresholds), with the scope set to the tag; a
    platform may add scope fields (for example regions) to narrow it.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.platforms)) ? alltrue([for k in keys(var.platforms) : can(regex("^[a-z][a-z0-9-]{0,30}$", k))]) : false
    error_message = "platforms must be a map keyed by lowercase platform names."
  }
}

# ---------------------------------------------------------------------------
# AI
# ---------------------------------------------------------------------------

variable "ai" {
  description = <<-EOT
    AI spend on Amazon Bedrock.
      applications       keyed by application: an application inference profile per model in this Region, tagged Team,
                         Application and (with platform) the platform tag; and, in the account part, a monthly cap
                         alerting at 50, 80, 90 and 100% of actual spend
      prices             per CloudWatch ModelId: price per million input and output tokens, in unit; at most five
      burn_per_hour      CRITICAL alarm when the last hour's priced token use exceeds this. Budgets see spend hours late
      unit               the currency of caps and prices
      quotas             Service Quotas to read in this Region, keyed by a name: { quota_code, model_id, service_code }.
                         A tokens-per-minute quota priced at model_id's higher price is the most the model can cost in
                         an hour, reported in output.ai_ceilings
      invocation_logs    Bedrock model invocation logging in this Region, metadata only: no prompt or response text,
                         image, embedding or video is delivered. Account-wide; one configuration per Region
  EOT
  type = object({
    applications = optional(map(object({
      models      = map(string)
      monthly_cap = number
      platform    = optional(string, "")
    })), {})
    prices = optional(map(object({
      input_per_million  = number
      output_per_million = number
    })), {})
    burn_per_hour = optional(number, 0)
    unit          = optional(string, "USD")
    quotas = optional(map(object({
      quota_code   = string
      model_id     = optional(string, "")
      service_code = optional(string, "bedrock")
    })), {})
    invocation_logs = optional(object({
      enabled        = optional(bool, false)
      retention_days = optional(number, 90)
    }), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      alltrue([for k, a in var.ai.applications : alltrue([
        can(regex("^[a-z][a-z0-9-]{0,30}$", k)),
        length(a.models) > 0, a.monthly_cap > 0,
        alltrue([for alias, arn in a.models : can(regex("^[a-z][a-z0-9-]{0,20}$", alias)) ? can(regex("^arn:aws[a-z-]*:bedrock:[a-z0-9-]+:([0-9]{12})?:(foundation-model|inference-profile)/.+$", arn)) : false]),
      ])]),
      length(var.ai.prices) <= 5,
      alltrue([for m, p in var.ai.prices : p.input_per_million >= 0 ? p.output_per_million >= 0 : false]),
      var.ai.burn_per_hour >= 0,
      var.ai.burn_per_hour == 0 ? true : length(var.ai.prices) > 0,
      can(regex("^[A-Z]{3}$", var.ai.unit)),
      alltrue([for k, q in var.ai.quotas : can(regex("^L-[A-F0-9]{8}$", q.quota_code)) ? (q.model_id == "" ? true : contains(keys(var.ai.prices), q.model_id)) : false]),
      contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.ai.invocation_logs.retention_days),
    ])
    error_message = "ai: applications keyed lowercase with models (alias => foundation-model or inference-profile ARN) and a monthly_cap above 0; at most five prices, not negative; burn_per_hour needs prices; unit a currency code; quotas with an L-XXXXXXXX code and a model_id from prices, or none; invocation_logs.retention_days a CloudWatch Logs retention."
  }
}

# ---------------------------------------------------------------------------
# Schedules
# ---------------------------------------------------------------------------

variable "schedules" {
  description = <<-EOT
    Non-production running hours, by name: stopped at stop and started at start (EventBridge Scheduler cron expressions,
    in timezone), by Systems Manager Automation.
      tag_key, tag_values   EC2 instances tagged tag_key = one of tag_values (AWS-StopEC2Instance, AWS-StartEC2Instance)
      rds_instances         RDS DB instance identifiers (AWS-StopRdsInstance, AWS-StartRdsInstance)
    Weekdays 08:00-19:00 is 55 of 168 hours: a third of the compute hours of an instance left running.
  EOT
  type = map(object({
    tag_key       = optional(string, "Schedule")
    tag_values    = optional(list(string), [])
    rds_instances = optional(list(string), [])
    stop          = string
    start         = string
    timezone      = optional(string, "Europe/London")
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for k, s in var.schedules : alltrue([
      can(regex("^[a-z][a-z0-9-]{0,20}$", k)),
      length(s.tag_values) + length(s.rds_instances) > 0,
      length(s.rds_instances) <= 20,
      alltrue([for d in s.rds_instances : can(regex("^[a-zA-Z][a-zA-Z0-9-]{0,62}$", d)) ? length("${k}-${d}-start") <= 64 : false]),
      can(regex("^cron\\(.+\\)$", s.stop)), can(regex("^cron\\(.+\\)$", s.start)),
    ])])
    error_message = "schedules: keys lowercase; tag_values, rds_instances (up to 20 DB instance identifiers, with the schedule name short enough for <name>-<instance>-start to fit 64 characters) or both; stop and start as cron(...) expressions."
  }
}

# ---------------------------------------------------------------------------
# Access and signals
# ---------------------------------------------------------------------------

variable "finops_access" {
  description = <<-EOT
    A read-only role for the FinOps team in this account (account part): billing, cost and resource metadata, no data.
      trusted_account_id   the FinOps account, whose roles may assume it
      trusted_role_arns    narrow it to these roles in that account. Empty: any role the account allows
      role_name            the role's name, the same in every account so a FinOps tool can find it
  EOT
  type = object({
    trusted_account_id = optional(string, "")
    trusted_role_arns  = optional(list(string), [])
    role_name          = optional(string, "keel-finops-read")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.finops_access.trusted_account_id == "" ? true : can(regex("^[0-9]{12}$", var.finops_access.trusted_account_id)),
      alltrue([for r in var.finops_access.trusted_role_arns : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", r))]),
      can(regex("^[A-Za-z0-9+=,.@_-]{1,64}$", var.finops_access.role_name)),
    ])
    error_message = "finops_access: trusted_account_id 12 digits; trusted_role_arns IAM role ARNs; role_name an IAM role name."
  }
}

variable "signals" {
  description = <<-EOT
    Where the team's signals go besides its owners.
      kms_key_arn             customer managed key for the topics, the queue and the invocation log group
      control_plane_bus_arn   the keel-control-plane event bus: every signal goes there with its severity
  EOT
  type = object({
    kms_key_arn           = optional(string, "")
    control_plane_bus_arn = optional(string, "")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.signals.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.signals.kms_key_arn)),
      var.signals.control_plane_bus_arn == "" ? true : can(regex("^arn:aws[a-z-]*:events:[a-z0-9-]+:[0-9]{12}:event-bus/.+$", var.signals.control_plane_bus_arn)),
    ])
    error_message = "signals: kms_key_arn a KMS key ARN; control_plane_bus_arn an EventBridge event bus ARN."
  }
}
