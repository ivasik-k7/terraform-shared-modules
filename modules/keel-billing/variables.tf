# ---------------------------------------------------------------------------
# Module
# ---------------------------------------------------------------------------

variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of what the module names: the severity topics, anomaly monitors and subscriptions, budgets, billing views and the forwarding rules."
  type        = string
  default     = "keel"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on every resource the module creates. Billing metadata is processed in us-east-1 by AWS: tags must never hold customer or personal data. The module adds ManagedBy and Module last."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\"). Listed in output.governance."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([for c in var.acknowledged_checks : contains([
      "somebody_hears_an_anomaly",
      "every_cost_category_is_watched",
      "spend_is_allocated_by_tags",
      "anomaly_events_reach_the_control_plane",
      "commitments_are_watched",
      "finops_agent_data_stays_in_the_us",
      "production_changes_only_by_people",
      "every_limit_has_an_owner",
    ], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

# ---------------------------------------------------------------------------
# Allocation
# ---------------------------------------------------------------------------

variable "cost_allocation_tags" {
  description = "User-defined tag keys to activate as cost allocation tags, so they reach Cost Explorer, budgets, cost categories and the CUR 2.0 and FOCUS exports. A key must have been seen on a resource before AWS accepts it. Free."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.cost_allocation_tags : can(regex("^[\\p{L}\\p{N}\\s_.:/=+@-]{1,128}$", t)) ? !startswith(lower(t), "aws:") : false])
    error_message = "cost_allocation_tags must be tag keys of 1-128 characters, not starting with aws:."
  }
}

variable "cost_categories" {
  description = <<-EOT
    Cost categories: the owner taxonomy every budget, monitor and dashboard groups by. Keyed by category name
    (for example BusinessUnit). Rules are evaluated in order; the first match wins.
      rules             [{ value, accounts }] or [{ value, tag_key, tag_values }]: a value for spend in these
                        accounts, or with this tag
      inherit_from_tag  after the rules, take the value from this tag on the resource (an inherited-value rule)
      default_value     spend no rule matched. Unallocated spend stays visible under this value
      split_charges     [{ source, targets, method }]: share a value's cost (a shared platform) across others,
                        PROPORTIONAL, EVEN or FIXED (FIXED needs percentages, not supported here)
    Free. Changes apply to the current month and later, never to closed months.
  EOT
  type = map(object({
    default_value = optional(string, "Unallocated")
    rules = optional(list(object({
      value      = string
      accounts   = optional(list(string), [])
      tag_key    = optional(string, "")
      tag_values = optional(list(string), [])
    })), [])
    inherit_from_tag = optional(string, "")
    split_charges = optional(list(object({
      source  = string
      targets = list(string)
      method  = optional(string, "PROPORTIONAL")
    })), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, c in var.cost_categories : can(regex("^[A-Za-z0-9][A-Za-z0-9 _-]{0,49}$", k))])
    error_message = "cost_categories keys must be 1-50 letters, digits, spaces, underscores or hyphens."
  }

  validation {
    condition = alltrue([for k, c in var.cost_categories : alltrue([for r in c.rules : alltrue([
      r.value != "",
      length(r.accounts) > 0 ? r.tag_key == "" : (r.tag_key != "" ? length(r.tag_values) > 0 : false),
      alltrue([for a in r.accounts : can(regex("^[0-9]{12}$", a))]),
    ])])])
    error_message = "cost_categories[*].rules: each rule has a value and either accounts (12-digit IDs) or a tag_key with tag_values, not both."
  }

  validation {
    condition = alltrue([for k, c in var.cost_categories : alltrue([
      length(c.rules) > 0 ? true : c.inherit_from_tag != "",
      alltrue([for s in c.split_charges : contains(["PROPORTIONAL", "EVEN"], s.method) ? length(s.targets) > 0 : false]),
    ])])
    error_message = "cost_categories: each needs rules or inherit_from_tag; split_charges use PROPORTIONAL or EVEN with one or more targets."
  }
}

# ---------------------------------------------------------------------------
# Optimisation
# ---------------------------------------------------------------------------

variable "optimization" {
  description = <<-EOT
    The free AWS recommendation services, for the whole organization.
      cost_optimization_hub    rightsizing, idle, Graviton and commitment recommendations in one place
      compute_optimizer        sizing for EC2, Auto Scaling, EBS, Lambda, ECS on Fargate, RDS and Aurora
      include_member_accounts  every member account, not only this one
      savings_estimation_mode  AfterDiscounts: savings net of the organization's discounts
      member_discount_visibility  All: member accounts see estimates with the organization's discounts
  EOT
  type = object({
    cost_optimization_hub      = optional(bool, true)
    compute_optimizer          = optional(bool, true)
    include_member_accounts    = optional(bool, true)
    savings_estimation_mode    = optional(string, "AfterDiscounts")
    member_discount_visibility = optional(string, "All")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      contains(["AfterDiscounts", "BeforeDiscounts"], var.optimization.savings_estimation_mode),
      contains(["All", "None"], var.optimization.member_discount_visibility),
    ])
    error_message = "optimization: savings_estimation_mode AfterDiscounts or BeforeDiscounts; member_discount_visibility All or None."
  }
}

# ---------------------------------------------------------------------------
# Anomalies
# ---------------------------------------------------------------------------

variable "anomaly_detection" {
  description = <<-EOT
    Cost Anomaly Detection with AWS managed monitors, which pick up new accounts and values on their own. Free.
      services, linked_accounts   a monitor per service, and per member account
      cost_categories             a monitor per cost category, tracking each of its values
      tags                        a monitor per cost allocation tag key, tracking each of its values
      alert                       one immediate alert across every monitor, from min_impact_absolute: it emits the
                                  Anomaly Detected event the control plane routes by impact (one event per anomaly),
                                  and publishes to <name>-anomaly-alerts, where emails are subscribed
      digests                     DAILY or WEEKLY summaries to emails, each with its own floor
  EOT
  type = object({
    services        = optional(bool, true)
    linked_accounts = optional(bool, true)
    cost_categories = optional(list(string), [])
    tags            = optional(list(string), [])
    alert = optional(object({
      enabled               = optional(bool, true)
      min_impact_absolute   = optional(number, 100)
      min_impact_percentage = optional(number, 0)
      emails                = optional(list(string), [])
    }), {})
    digests = optional(map(object({
      frequency             = optional(string, "DAILY")
      min_impact_absolute   = number
      min_impact_percentage = optional(number, 0)
      emails                = list(string)
    })), {})
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.anomaly_detection.alert.min_impact_absolute >= 0, var.anomaly_detection.alert.min_impact_percentage >= 0,
      alltrue([for k, d in var.anomaly_detection.digests : alltrue([
        can(regex("^[a-z][a-z0-9-]{0,30}$", k)),
        contains(["DAILY", "WEEKLY"], d.frequency),
        d.min_impact_absolute >= 0, d.min_impact_percentage >= 0,
        length(d.emails) > 0, length(d.emails) <= 10,
      ])]),
    ])
    error_message = "anomaly_detection: impacts 0 or more; digests keyed lowercase, DAILY or WEEKLY, with one to ten emails."
  }
}

# ---------------------------------------------------------------------------
# Limits
# ---------------------------------------------------------------------------

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

variable "limits" {
  description = <<-EOT
    Organization limits, passed to keel-limits (its README lists the fields): the whole bill, a business unit (a cost
    category value), a platform across accounts (a tag), a service line such as Amazon Bedrock, data transfer, a set
    of accounts. Each alerts by severity on the severity topics; an action may apply an SCP. Anomalies here are the
    managed monitors' (anomaly_detection), so a limit takes no anomaly monitor of its own. Budgets are free.
  EOT
  type        = any
  default     = {}
  nullable    = false

  validation {
    condition     = can(keys(var.limits)) ? alltrue([for k, l in var.limits : !startswith(k, "sp-") ? (!startswith(k, "ri-") ? try(l.anomaly, null) == null : false) : false]) : false
    error_message = "limits must be a map of keel-limits limit objects, with no anomaly (the managed monitors cover the organization) and no key starting sp- or ri- (those are commitments')."
  }
}

variable "commitments" {
  description = <<-EOT
    Commitment targets, each a budget alerting WARNING when the period's figure falls below it. 0 leaves one out.
      savings_plans_utilization   percent of the Savings Plans commitment used: below it, commitment is paid for and idle
      savings_plans_coverage      percent of eligible spend Savings Plans cover: below it, on-demand is paid where a
                                  commitment would cost less
      ri_utilization, ri_coverage percent, by service (Cost Explorer name, for example
                                  "Amazon Relational Database Service")
      owners                      emails told directly, besides the WARNING topic
  EOT
  type = object({
    savings_plans_utilization = optional(number, 0)
    savings_plans_coverage    = optional(number, 0)
    ri_utilization            = optional(map(number), {})
    ri_coverage               = optional(map(number), {})
    owners                    = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for p in concat(
      [var.commitments.savings_plans_utilization, var.commitments.savings_plans_coverage],
      values(var.commitments.ri_utilization), values(var.commitments.ri_coverage),
    ) : p >= 0 ? p <= 100 : false])
    error_message = "commitments: targets are percentages, 0 (off) to 100."
  }
}

# ---------------------------------------------------------------------------
# Billing views
# ---------------------------------------------------------------------------

variable "billing_views" {
  description = <<-EOT
    Custom billing views: a filtered slice of the organization's cost data, read in Cost Explorer by the accounts it is
    shared with through AWS RAM, so a team or the FinOps account sees its spend without management account access.
    A view filters on one dimension: accounts, or one tag key's values. Free.
      accounts     the linked accounts the view shows
      tag          { key, values }: spend carrying the tag
      share_with   account IDs to share the view with, inside the organization
  EOT
  type = map(object({
    description = optional(string, "")
    accounts    = optional(list(string), [])
    tag = optional(object({
      key    = string
      values = list(string)
    }))
    share_with = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for k, v in var.billing_views : alltrue([
      can(regex("^[a-z][a-z0-9-]{0,40}$", k)),
      length(v.accounts) > 0 ? v.tag == null : v.tag != null,
      alltrue([for a in concat(v.accounts, v.share_with) : can(regex("^[0-9]{12}$", a))]),
    ])])
    error_message = "billing_views: keys lowercase; accounts or tag, not both; accounts and share_with 12-digit IDs."
  }
}

# ---------------------------------------------------------------------------
# FinOps Agent
# ---------------------------------------------------------------------------

variable "finops_agent" {
  description = <<-EOT
    AWS FinOps Agent (preview, us-east-1 only), an AI agent that answers cost questions and investigates anomalies
    across the organization through its service-linked role. It keeps its data in us-east-1 and runs inference within
    the US geography, whichever Regions the accounts use: a data-residency decision (check
    finops_agent_data_stays_in_the_us). Pair it with keel-guardrails' ai_services_opt_out.
      enabled                      trusted access for finops-agent.amazonaws.com
      delegated_admin_account_id   the account that administers it, usually the FinOps account. Empty: the
                                   management account
  EOT
  type = object({
    enabled                    = optional(bool, false)
    delegated_admin_account_id = optional(string, "")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.finops_agent.delegated_admin_account_id == "" ? true : (var.finops_agent.enabled ? can(regex("^[0-9]{12}$", var.finops_agent.delegated_admin_account_id)) : false)
    error_message = "finops_agent.delegated_admin_account_id must be a 12-digit account ID, and needs enabled = true."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

variable "signals" {
  description = <<-EOT
    Where the management account's signals go.
      emails                   owners subscribed to the severity topics, by severity (info, warning, high, critical)
      kms_key_arn              customer managed key for the topics and the queue (output.kms_key_policy_requirements)
      control_plane_bus_arn    the keel-control-plane event bus: the severity topics' signals and the Anomaly
                               Detected events are forwarded there, for routing by severity and for evidence
  EOT
  type = object({
    emails                = optional(map(list(string)), {})
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

variable "permissions_boundary_arn" {
  description = "Permissions boundary for the roles the module creates (signal pipes and forwarding, limit actions). The CID data exports template takes a role path (data_exports.role_path), not a boundary. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

# ---------------------------------------------------------------------------
# Cost data for the dashboards
# ---------------------------------------------------------------------------

variable "data_exports" {
  description = <<-EOT
    The source side of the Cloud Intelligence Dashboards data pipeline, deployed with AWS's own CloudFormation
    template (data-exports-aggregation.yaml): CUR 2.0, FOCUS 1.2 and Cost Optimization Hub exports from this
    account, delivered to the destination account where keel-insights runs. S3 storage only (COSTS.md).
      destination_account_id   the account keel-insights deploys in
      version                  the template version, the same as keel-insights'
      resource_prefix          the same as keel-insights'
      cur2, focus, coh, carbon which exports to manage
      split_cost_allocation    container cost split data in CUR 2.0
      iam_principal            Bedrock cost by calling IAM role in CUR 2.0 (data from April 2026)
      cur2_granularity, focus_granularity  HOURLY, DAILY or MONTHLY. Changing it needs a purge and backfill
  EOT
  type = object({
    enabled                = optional(bool, false)
    destination_account_id = optional(string, "")
    version                = optional(string, "0.13.0")
    resource_prefix        = optional(string, "cid")
    cur2                   = optional(bool, true)
    focus                  = optional(bool, true)
    coh                    = optional(bool, true)
    carbon                 = optional(bool, false)
    split_cost_allocation  = optional(bool, true)
    iam_principal          = optional(bool, true)
    cur2_granularity       = optional(string, "HOURLY")
    focus_granularity      = optional(string, "HOURLY")
    role_path              = optional(string, "/")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.data_exports.enabled ? can(regex("^[0-9]{12}$", var.data_exports.destination_account_id)) : true,
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.data_exports.version)),
      can(regex("^[a-z0-9][a-z0-9-]{0,20}$", var.data_exports.resource_prefix)),
      contains(["HOURLY", "DAILY", "MONTHLY"], var.data_exports.cur2_granularity),
      contains(["HOURLY", "DAILY", "MONTHLY"], var.data_exports.focus_granularity),
      can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.data_exports.role_path)),
    ])
    error_message = "data_exports: enabled needs a 12-digit destination_account_id; version x.y.z; resource_prefix lowercase; granularities HOURLY, DAILY or MONTHLY; role_path an IAM path."
  }
}
