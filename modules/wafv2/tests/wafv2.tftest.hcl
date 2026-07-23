# plan-level, mocked. Priorities and rule composition are pure functions of the
# inputs, so the auto-priority map and rule graph are assertable offline. A few
# checks use mocked apply to read computed ARNs.

mock_provider "aws" {
  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn      = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/mock/abc"
      capacity = 100
    }
  }
  mock_resource "aws_wafv2_ip_set" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/ipset/mock/abc" }
  }
  mock_resource "aws_wafv2_regex_pattern_set" {
    defaults = { arn = "arn:aws:wafv2:us-east-1:123456789012:global/regexpatternset/mock/abc" }
  }
}

variables {
  name = "edge"
}

# --- baseline: three groups + rate, correct precedence ----------------------
run "baseline_defaults" {
  command = plan

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1
    error_message = "Web ACL should be created"
  }

  # baseline groups + baseline rate present in the priority map
  assert {
    condition = alltrue([
      can(output.rule_priorities["managed/AWSManagedRulesCommonRuleSet"]),
      can(output.rule_priorities["managed/AWSManagedRulesKnownBadInputsRuleSet"]),
      can(output.rule_priorities["managed/AWSManagedRulesAmazonIpReputationList"]),
      can(output.rule_priorities["rate/__baseline__"]),
    ])
    error_message = "Baseline should contribute three managed groups and a rate rule"
  }

  # rate rule (earlier band) evaluates before managed groups
  assert {
    condition     = output.rule_priorities["rate/__baseline__"] < output.rule_priorities["managed/AWSManagedRulesCommonRuleSet"]
    error_message = "Rate band must precede the managed band"
  }
}

# --- baseline off -----------------------------------------------------------
run "baseline_off" {
  command = plan

  variables {
    enable_baseline = false
  }

  assert {
    condition     = length(local.baseline_groups) == 0 && !local.baseline_rate_enabled
    error_message = "Disabling baseline should drop its groups and rate rule"
  }
}

# --- precedence: allow-IP first, custom last --------------------------------
run "precedence" {
  command = plan

  variables {
    enable_baseline     = false
    ip_allow_lists      = { office = ["203.0.113.0/24"] }
    ip_block_lists      = { banned = ["198.51.100.7/32"] }
    geo_block_countries = ["CN"]
    rate_based_rules    = [{ name = "api", limit = 1000 }]
    managed_rule_groups = [{ name = "AWSManagedRulesSQLiRuleSet" }]
    custom_rules        = [{ name = "no-xmlrpc", field = "uri_path", type = "contains", value = "/xmlrpc.php" }]
  }

  assert {
    condition = alltrue([
      output.rule_priorities["ipallow/office"] < output.rule_priorities["ipblock/banned"],
      output.rule_priorities["ipblock/banned"] < output.rule_priorities["geo/block"],
      output.rule_priorities["geo/block"] < output.rule_priorities["rate/api"],
      output.rule_priorities["rate/api"] < output.rule_priorities["managed/AWSManagedRulesSQLiRuleSet"],
      output.rule_priorities["managed/AWSManagedRulesSQLiRuleSet"] < output.rule_priorities["custom/no-xmlrpc"],
    ])
    error_message = "Precedence must be allow-IP < block-IP < geo < rate < managed < custom"
  }

  # priorities are a dense 0..N-1 sequence (unique, no gaps)
  assert {
    condition     = length(values(output.rule_priorities)) == length(distinct(values(output.rule_priorities)))
    error_message = "Priorities must be unique"
  }
}

# --- IP set version inference -----------------------------------------------
run "ip_version_inference" {
  command = plan

  variables {
    enable_baseline = false
    ip_block_lists = {
      v4 = ["10.0.0.0/8"]
      v6 = ["2001:db8::/32"]
    }
  }

  assert {
    condition = alltrue([
      aws_wafv2_ip_set.block["v4"].ip_address_version == "IPV4",
      aws_wafv2_ip_set.block["v6"].ip_address_version == "IPV6",
    ])
    error_message = "IP set version should be inferred from the addresses"
  }
}

# --- managed group count-mode + overrides -----------------------------------
run "managed_overrides" {
  command = apply

  variables {
    enable_baseline = false
    managed_rule_groups = [{
      name       = "AWSManagedRulesCommonRuleSet"
      count_only = true
      rule_action_overrides = {
        SizeRestrictions_BODY = "block"
      }
    }]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1
    error_message = "count-mode managed group with overrides should plan+apply"
  }
}

# --- custom rule types render (mocked apply reads regex set arn) ------------
run "custom_rule_types" {
  command = apply

  variables {
    enable_baseline = false
    custom_rules = [
      { name = "big-body", field = "body", type = "size", size_operator = "GT", size = 8192 },
      { name = "bad-agent", field = "single_header", header_name = "User-Agent", type = "contains", value = "sqlmap" },
      { name = "path-rx", field = "uri_path", type = "regex_set", regex_patterns = ["(?i)\\.\\./", "/etc/passwd"] },
    ]
  }

  assert {
    condition = alltrue([
      length(aws_wafv2_web_acl.this) == 1,
      length(aws_wafv2_regex_pattern_set.custom) == 1, # only the regex_set rule
      contains(keys(aws_wafv2_regex_pattern_set.custom), "path-rx"),
    ])
    error_message = "Custom size/header/regex_set rules should compose; regex sets only for regex_set type"
  }
}

# --- rate scope-down (both uri + geo -> AND) --------------------------------
run "rate_scope_down" {
  command = apply

  variables {
    enable_baseline = false
    rate_based_rules = [{
      name          = "login"
      limit         = 100
      aggregate_key = "FORWARDED_IP"
      scope_down    = { uri_path_contains = "/login", country_codes = ["US"] }
    }]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1
    error_message = "Rate rule with AND scope-down + forwarded IP should plan+apply"
  }
}

# --- REGIONAL association ----------------------------------------------------
run "regional_association" {
  command = apply

  variables {
    scope                   = "REGIONAL"
    associate_resource_arns = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/x/1"]
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "REGIONAL scope should associate the given resource ARNs"
  }
}

# --- logging with redaction + filter ----------------------------------------
run "logging" {
  command = apply

  variables {
    enable_logging      = true
    log_destination_arn = "arn:aws:logs:us-east-1:123456789012:log-group:aws-waf-logs-edge"
    log_redacted_fields = [{ type = "single_header", header_name = "Authorization" }]
    log_filter = {
      default_behavior = "DROP"
      filters = [{
        behavior   = "KEEP"
        conditions = [{ action_condition = "BLOCK" }]
      }]
    }
  }

  assert {
    condition     = length(aws_wafv2_web_acl_logging_configuration.this) == 1
    error_message = "Logging configuration should be created"
  }
}

# --- create = false ----------------------------------------------------------
run "create_false" {
  command = plan
  variables {
    create = false
  }
  assert {
    condition     = length(aws_wafv2_web_acl.this) == 0
    error_message = "create=false builds nothing"
  }
}

# --- count_mode forces every module-owned block to count -------------------
run "count_mode" {
  command = apply

  variables {
    count_mode          = true
    ip_block_lists      = { bad = ["198.51.100.0/24"] }
    geo_block_countries = ["CN"]
    rate_based_rules    = [{ name = "api", limit = 500 }] # action defaults to block
    custom_rules        = [{ name = "xmlrpc", field = "uri_path", type = "contains", value = "/xmlrpc.php" }]
  }

  # nothing should render a block action anywhere while observing
  assert {
    condition     = length(regexall("\"block\":\\[\\{", jsonencode(aws_wafv2_web_acl.this[0]))) == 0
    error_message = "count_mode must render no block actions (dry-run observe)"
  }
}

# --- custom rule phase: pre-managed sits before managed groups --------------
run "custom_phase_pre" {
  command = plan

  variables {
    enable_baseline     = false
    managed_rule_groups = [{ name = "AWSManagedRulesCommonRuleSet" }]
    custom_rules = [
      { name = "rescue", phase = "pre", action = "allow", field = "uri_path", type = "starts_with", value = "/api/upload" },
      { name = "late", field = "uri_path", type = "contains", value = "/x" },
    ]
  }

  assert {
    condition = alltrue([
      output.rule_priorities["custom/rescue"] < output.rule_priorities["managed/AWSManagedRulesCommonRuleSet"],
      output.rule_priorities["managed/AWSManagedRulesCommonRuleSet"] < output.rule_priorities["custom/late"],
    ])
    error_message = "phase=pre custom rules must precede managed groups; phase=post must follow"
  }
}

# --- label match custom rule -------------------------------------------------
run "custom_label" {
  command = apply

  variables {
    enable_baseline     = false
    managed_rule_groups = [{ name = "AWSManagedRulesBotControlRuleSet" }]
    custom_rules = [
      { name = "block-bots", type = "label", value = "awswaf:managed:aws:bot-control:bot:category:http_library" },
    ]
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this) == 1
    error_message = "label-match custom rule should compose"
  }
}

# --- block_response reaches geo + rate blocks (consistency) -----------------
run "block_response_everywhere" {
  command = apply

  variables {
    enable_baseline     = false
    geo_block_countries = ["CN"]
    rate_based_rules    = [{ name = "api", limit = 500 }]
    custom_response_bodies = {
      denied = { content_type = "APPLICATION_JSON", content = "{\"e\":\"blocked\"}" }
    }
    block_response = { status_code = 403, custom_response_body_key = "denied" }
  }

  # every block action carries the custom response body key
  assert {
    condition     = length(regexall("\"custom_response_body_key\":\"denied\"", jsonencode(aws_wafv2_web_acl.this[0]))) >= 2
    error_message = "block_response must apply to geo and rate blocks, not only IP/custom"
  }
}

# --- external IP set references: block-in-set + block-if-not-in-set ---------
run "ip_reference_rules" {
  command = apply

  variables {
    enable_baseline = false
    ip_reference_rules = [
      { name = "threat-intel", arn = "arn:aws:wafv2:us-east-1:123456789012:global/ipset/threat/abc", action = "block" },
      {
        name         = "proxy-allowlist"
        arn          = "arn:aws:wafv2:us-east-1:123456789012:global/ipset/proxy/def"
        action       = "block"
        negate       = true
        forwarded_ip = { header_name = "X-Forwarded-For", position = "FIRST" }
      },
    ]
  }

  assert {
    condition = alltrue([
      length(aws_wafv2_web_acl.this) == 1,
      # threat-intel evaluates before the proxy allowlist (list order)
      output.rule_priorities["ipref/threat-intel"] < output.rule_priorities["ipref/proxy-allowlist"],
      # the negated rule renders a not_statement; the plain one does not
      length(regexall("not_statement", jsonencode(aws_wafv2_web_acl.this[0]))) >= 1,
      # forwarded-IP matching renders on the allowlist rule
      length(regexall("ip_set_forwarded_ip_config", jsonencode(aws_wafv2_web_acl.this[0]))) >= 1,
    ])
    error_message = "External IP set refs should compose; negate=true wraps in not_statement; forwarded_ip renders"
  }
}

run "ip_reference_bad_arn_fails" {
  command = plan
  variables {
    ip_reference_rules = [{ name = "x", arn = "not-an-arn" }]
  }
  expect_failures = [var.ip_reference_rules]
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "mixed_ip_version_fails" {
  command = plan
  variables {
    ip_block_lists = { bad = ["10.0.0.0/8", "2001:db8::/32"] }
  }
  expect_failures = [var.ip_block_lists]
}

run "geo_both_models_fails" {
  command = plan
  variables {
    geo_block_countries = ["CN"]
    geo_allow_countries = ["US"]
  }
  expect_failures = [var.geo_allow_countries]
}

run "label_without_value_fails" {
  command = plan
  variables {
    custom_rules = [{ name = "x", type = "label" }]
  }
  expect_failures = [var.custom_rules]
}

run "redaction_single_header_without_name_fails" {
  command = plan
  variables {
    enable_logging      = true
    log_destination_arn = "arn:aws:logs:us-east-1:1:log-group:aws-waf-logs-x"
    log_redacted_fields = [{ type = "single_header" }]
  }
  expect_failures = [var.log_redacted_fields]
}

run "bad_content_type_fails" {
  command = plan
  variables {
    custom_response_bodies = { x = { content_type = "text/plain", content = "no" } }
  }
  expect_failures = [var.custom_response_bodies]
}

run "block_response_bad_key_fails" {
  command = plan
  variables {
    block_response = { status_code = 403, custom_response_body_key = "missing" }
  }
  expect_failures = [aws_wafv2_web_acl.this]
}

# ============================================================================
# LEGACY VALIDATION FAILURES
# ============================================================================

run "bad_scope_fails" {
  command = plan
  variables { scope = "EDGE" }
  expect_failures = [var.scope]
}

run "association_on_cloudfront_fails" {
  command = plan
  variables {
    scope                   = "CLOUDFRONT"
    associate_resource_arns = ["arn:aws:elasticloadbalancing:us-east-1:1:loadbalancer/app/x/1"]
  }
  expect_failures = [var.associate_resource_arns]
}

run "bad_rate_window_fails" {
  command = plan
  variables {
    rate_based_rules = [{ name = "x", limit = 100, evaluation_window = 45 }]
  }
  expect_failures = [var.rate_based_rules]
}

run "size_rule_without_size_fails" {
  command = plan
  variables {
    custom_rules = [{ name = "x", field = "body", type = "size" }]
  }
  expect_failures = [var.custom_rules]
}

run "single_header_without_name_fails" {
  command = plan
  variables {
    custom_rules = [{ name = "x", field = "single_header", type = "contains", value = "y" }]
  }
  expect_failures = [var.custom_rules]
}

run "bad_geo_code_fails" {
  command = plan
  variables { geo_block_countries = ["USA"] }
  expect_failures = [var.geo_block_countries]
}

run "logging_without_destination_fails" {
  command = plan
  variables { enable_logging = true }
  expect_failures = [var.log_destination_arn]
}
