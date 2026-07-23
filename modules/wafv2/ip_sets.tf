# IP sets referenced by the allow/block rules. One set per named list; version
# inferred from the addresses (see locals). WAF sets are single-version.

resource "aws_wafv2_ip_set" "allow" {
  for_each = local.create ? var.ip_allow_lists : {}

  name               = "${var.name}-allow-${each.key}"
  description        = "Allowlist ${each.key} for ${var.name}"
  scope              = var.scope
  ip_address_version = local.ip_allow_version[each.key]
  addresses          = each.value
  tags               = local.common_tags
}

resource "aws_wafv2_ip_set" "block" {
  for_each = local.create ? var.ip_block_lists : {}

  name               = "${var.name}-block-${each.key}"
  description        = "Blocklist ${each.key} for ${var.name}"
  scope              = var.scope
  ip_address_version = local.ip_block_version[each.key]
  addresses          = each.value
  tags               = local.common_tags
}

# regex pattern sets backing custom rules of type = regex_set
resource "aws_wafv2_regex_pattern_set" "custom" {
  for_each = local.create ? { for r in var.custom_rules : r.name => r if r.type == "regex_set" } : {}

  name        = "${var.name}-${each.key}"
  description = "Regex set for custom rule ${each.key}"
  scope       = var.scope

  dynamic "regular_expression" {
    for_each = each.value.regex_patterns
    content {
      regex_string = regular_expression.value
    }
  }

  tags = local.common_tags
}
