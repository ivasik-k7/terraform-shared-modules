locals {
  create   = var.create
  account  = local.create ? var.components.account : false
  regional = local.create ? var.components.region : false

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "eu-west-2")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  module_tags = { ManagedBy = "Terraform", Module = "keel-team" }
  tags        = merge(var.tags, { Team = var.team, CostCentre = var.cost_centre }, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)
  limit_checks = ["production_changes_only_by_people", "every_limit_has_an_owner"]

  topic_arns = module.signals.topic_arns

  # What keel-limits enforces for the account: the caller's limits, one per
  # platform on its tag, and a cap per AI application on its tags.
  caller_limits = { for k, l in var.limits : k => merge({ tier = var.tier }, l) }
  platform_limits = { for p, cfg in var.platforms : "platform-${p}" => merge({ tier = var.tier }, cfg, {
    scope = merge(try(cfg.scope, {}), { tags = merge(try(cfg.scope.tags, {}), { (var.platform_tag_key) = [p] }) })
  }) }
  ai_limits = { for app, a in var.ai.applications : "ai-${app}" => {
    tier                = var.tier
    amount              = tostring(a.monthly_cap)
    unit                = var.ai.unit
    metric              = "UnblendedCost"
    scope               = { tags = { Team = [var.team], Application = [app] } }
    forecast_thresholds = []
    actual_thresholds   = [50, 80, 90, 100]
  } }
  limits = { for k, l in merge(local.caller_limits, local.platform_limits, local.ai_limits) : k => l if local.account }

  # A COST limit whose scope narrows nothing but the account is the account's
  # budget (FC-01).
  account_limits = sort([for k, l in local.caller_limits : k if try(l.type, "COST") == "COST" ? alltrue([for f, v in try(l.scope, {}) : f == "accounts" ? true : length(v) == 0]) : false])
  account_limit  = length(local.account_limits) > 0 ? local.caller_limits[local.account_limits[0]] : null
  account_limit_amount = local.account_limit == null ? null : (
    try(local.account_limit.auto_adjust_months, 0) > 0 ? null : (
      try(local.account_limit.period, "MONTHLY") != "MONTHLY" ? null : try(tonumber(local.account_limit.amount), null)
    )
  )
}

# ---------------------------------------------------------------------------
# Signals: the Region's severity topics, forwarded to the control plane
# ---------------------------------------------------------------------------

module "signals" {
  source = "../keel-signals"

  create                   = local.regional
  name                     = var.team
  tags                     = local.tags
  kms_key_arn              = var.signals.kms_key_arn
  permissions_boundary_arn = var.permissions_boundary_arn
  emails                   = var.emails
  control_plane_bus_arn    = var.signals.control_plane_bus_arn
}

# ---------------------------------------------------------------------------
# Limits: budgets are global, so the account part creates them once
# ---------------------------------------------------------------------------

module "limits" {
  source = "../keel-limits"

  create                   = local.account
  name                     = var.team
  tags                     = local.tags
  acknowledged_checks      = [for c in var.acknowledged_checks : c if contains(local.limit_checks, c)]
  permissions_boundary_arn = var.permissions_boundary_arn
  topic_arns               = local.topic_arns
  tiers                    = length(var.tiers) > 0 ? var.tiers : null
  limits                   = local.limits
}
