locals {
  create = var.create

  common_tags = merge(var.tags, {
    "ManagedBy" = "Terraform"
    "Module"    = "waf"
  })

  block_action_enabled = var.default_action == "block"

  # ---- baseline preset -------------------------------------------------------
  # curated AWS best-practice groups, rendered in their own dynamic block so we
  # never have to unify their object type with the user's managed_rule_groups.
  baseline_groups = var.enable_baseline ? [
    { name = "AWSManagedRulesCommonRuleSet", count_only = var.baseline_count_only },
    { name = "AWSManagedRulesKnownBadInputsRuleSet", count_only = var.baseline_count_only },
    { name = "AWSManagedRulesAmazonIpReputationList", count_only = var.baseline_count_only },
  ] : []

  baseline_rate_enabled = var.enable_baseline && var.baseline_rate_limit > 0

  # ---- geo ---------------------------------------------------------------------
  geo_block_enabled = length(var.geo_block_countries) > 0
  geo_allow_enabled = length(var.geo_allow_countries) > 0

  # ---- IP sets -----------------------------------------------------------------
  # WAF IP sets are single-version; infer from the addresses, fall back to the
  # configured default when a list is empty.
  ip_allow_version = { for k, v in var.ip_allow_lists : k => length([for c in v : c if strcontains(c, ":")]) > 0 ? "IPV6" : (length(v) > 0 ? "IPV4" : var.ip_address_version_default) }
  ip_block_version = { for k, v in var.ip_block_lists : k => length([for c in v : c if strcontains(c, ":")]) > 0 ? "IPV6" : (length(v) > 0 ? "IPV4" : var.ip_address_version_default) }

  # ============================================================================
  # PRIORITY - the DX payoff: assigned from a fixed precedence, never by hand.
  # allow-IP first (short-circuit), then block-IP, geo, rate, managed, custom.
  # ============================================================================
  # custom rules can sit BEFORE managed groups (phase = "pre") to rescue
  # legitimate traffic from a managed-rule false positive, or after (default).
  rule_order = concat(
    [for k in sort(keys(var.ip_allow_lists)) : "ipallow/${k}"],
    [for k in sort(keys(var.ip_block_lists)) : "ipblock/${k}"],
    [for r in var.ip_reference_rules : "ipref/${r.name}"],
    local.geo_block_enabled ? ["geo/block"] : [],
    local.geo_allow_enabled ? ["geo/allow"] : [],
    local.baseline_rate_enabled ? ["rate/__baseline__"] : [],
    [for r in var.rate_based_rules : "rate/${r.name}"],
    [for r in var.custom_rules : "custom/${r.name}" if r.phase == "pre"],
    [for g in local.baseline_groups : "managed/${g.name}"],
    [for g in var.managed_rule_groups : "managed/${g.name}"],
    [for r in var.custom_rules : "custom/${r.name}" if r.phase != "pre"],
  )
  priority = { for i, id in distinct(local.rule_order) : id => i }

  # referential check: a block_response body key must exist in custom_response_bodies.
  # nested ternaries, not ||: terraform < 1.10 evaluates || eagerly and would
  # dereference block_response even when it's null.
  block_response_key_ok = var.block_response == null ? true : (
    try(var.block_response.custom_response_body_key, null) == null ? true :
    contains(keys(var.custom_response_bodies), var.block_response.custom_response_body_key)
  )

  # rule-name uniqueness across the composed ACL (WAF rejects duplicates) -
  # surfaced as a plan-time check via the rule_order having unique ids.
  rule_names           = [for id in local.rule_order : id]
  rule_names_unique_ok = length(distinct(local.rule_names)) == length(local.rule_names)

  # rate rules with scope-down flags resolved once (dynamic blocks can't hold locals)
  rate_rules = [for r in var.rate_based_rules : {
    name              = r.name
    limit             = r.limit
    action            = r.action
    aggregate_key     = r.aggregate_key
    evaluation_window = r.evaluation_window
    sd_uri            = try(r.scope_down.uri_path_contains, "")
    sd_geo            = try(r.scope_down.country_codes, [])
    has_sd            = try(r.scope_down.uri_path_contains, "") != "" || length(try(r.scope_down.country_codes, [])) > 0
    sd_both           = try(r.scope_down.uri_path_contains, "") != "" && length(try(r.scope_down.country_codes, [])) > 0
  }]

  # byte-match positional constraint mapping (module vocabulary -> WAF enum)
  byte_match_positional = {
    contains    = "CONTAINS"
    starts_with = "STARTS_WITH"
    ends_with   = "ENDS_WITH"
    exactly     = "EXACTLY"
  }
  size_operator_default = "GT"
}
