# The web ACL. Rules are composed from the typed inputs in a fixed precedence
# (allow-IP -> block-IP -> geo -> rate -> [pre-custom] -> managed -> custom) and
# their priorities are assigned from local.priority - callers never hand-manage
# priority integers. CloudFront associates by setting web_acl_id on the
# distribution to the web_acl_arn output; REGIONAL scope uses the association
# resource. count_mode turns every module-owned block into Count for safe
# onboarding on live traffic.

resource "aws_wafv2_web_acl" "this" {
  count = local.create ? 1 : 0

  name          = var.name
  description   = var.description
  scope         = var.scope
  token_domains = length(var.token_domains) > 0 ? var.token_domains : null
  tags          = local.common_tags

  default_action {
    dynamic "allow" {
      for_each = local.block_action_enabled ? [] : [1]
      content {}
    }
    dynamic "block" {
      for_each = local.block_action_enabled ? [1] : []
      content {
        dynamic "custom_response" {
          for_each = var.block_response != null ? [var.block_response] : []
          content {
            response_code            = custom_response.value.status_code
            custom_response_body_key = custom_response.value.custom_response_body_key
            dynamic "response_header" {
              for_each = custom_response.value.response_headers
              content {
                name  = response_header.key
                value = response_header.value
              }
            }
          }
        }
      }
    }
  }

  dynamic "captcha_config" {
    for_each = var.captcha_immunity_seconds != null ? [1] : []
    content {
      immunity_time_property {
        immunity_time = var.captcha_immunity_seconds
      }
    }
  }

  dynamic "challenge_config" {
    for_each = var.challenge_immunity_seconds != null ? [1] : []
    content {
      immunity_time_property {
        immunity_time = var.challenge_immunity_seconds
      }
    }
  }

  dynamic "custom_response_body" {
    for_each = var.custom_response_bodies
    content {
      key          = custom_response_body.key
      content      = custom_response_body.value.content
      content_type = custom_response_body.value.content_type
    }
  }

  # ---- IP allowlists (allow + short-circuit) --------------------------------
  dynamic "rule" {
    for_each = aws_wafv2_ip_set.allow
    content {
      name     = "allow-${rule.key}"
      priority = local.priority["ipallow/${rule.key}"]
      action {
        allow {}
      }
      statement {
        ip_set_reference_statement {
          arn = rule.value.arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-allow-${rule.key}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- IP blocklists --------------------------------------------------------
  dynamic "rule" {
    for_each = aws_wafv2_ip_set.block
    content {
      name     = "block-${rule.key}"
      priority = local.priority["ipblock/${rule.key}"]
      action {
        dynamic "block" {
          for_each = var.count_mode ? [] : [1]
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = var.count_mode ? [1] : []
          content {}
        }
      }
      statement {
        ip_set_reference_statement {
          arn = rule.value.arn
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-block-${rule.key}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- external IP set references (threat-intel feeds, proxy allowlists) -----
  dynamic "rule" {
    for_each = { for r in var.ip_reference_rules : r.name => r }
    content {
      name     = "ipref-${rule.value.name}"
      priority = local.priority["ipref/${rule.value.name}"]
      action {
        dynamic "allow" {
          for_each = (!var.count_mode && rule.value.action == "allow") ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = (!var.count_mode && rule.value.action == "block") ? [1] : []
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = (var.count_mode || rule.value.action == "count") ? [1] : []
          content {}
        }
        dynamic "captcha" {
          for_each = (!var.count_mode && rule.value.action == "captcha") ? [1] : []
          content {}
        }
        dynamic "challenge" {
          for_each = (!var.count_mode && rule.value.action == "challenge") ? [1] : []
          content {}
        }
      }
      statement {
        # negate => match when the IP is NOT in the set (block-if-not-allowlisted)
        dynamic "not_statement" {
          for_each = rule.value.negate ? [1] : []
          content {
            statement {
              ip_set_reference_statement {
                arn = rule.value.arn
                dynamic "ip_set_forwarded_ip_config" {
                  for_each = rule.value.forwarded_ip != null ? [rule.value.forwarded_ip] : []
                  content {
                    header_name       = ip_set_forwarded_ip_config.value.header_name
                    position          = ip_set_forwarded_ip_config.value.position
                    fallback_behavior = ip_set_forwarded_ip_config.value.fallback_behavior
                  }
                }
              }
            }
          }
        }
        dynamic "ip_set_reference_statement" {
          for_each = rule.value.negate ? [] : [1]
          content {
            arn = rule.value.arn
            dynamic "ip_set_forwarded_ip_config" {
              for_each = rule.value.forwarded_ip != null ? [rule.value.forwarded_ip] : []
              content {
                header_name       = ip_set_forwarded_ip_config.value.header_name
                position          = ip_set_forwarded_ip_config.value.position
                fallback_behavior = ip_set_forwarded_ip_config.value.fallback_behavior
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-ipref-${rule.value.name}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- geo block (block listed countries) -----------------------------------
  dynamic "rule" {
    for_each = local.geo_block_enabled ? [1] : []
    content {
      name     = "geo-block"
      priority = local.priority["geo/block"]
      action {
        dynamic "block" {
          for_each = var.count_mode ? [] : [1]
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = var.count_mode ? [1] : []
          content {}
        }
      }
      statement {
        geo_match_statement {
          country_codes = var.geo_block_countries
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- geo allow-model (block everything NOT listed) ------------------------
  dynamic "rule" {
    for_each = local.geo_allow_enabled ? [1] : []
    content {
      name     = "geo-allow-only"
      priority = local.priority["geo/allow"]
      action {
        dynamic "block" {
          for_each = var.count_mode ? [] : [1]
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = var.count_mode ? [1] : []
          content {}
        }
      }
      statement {
        not_statement {
          statement {
            geo_match_statement {
              country_codes = var.geo_allow_countries
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-geo-allow-only"
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- baseline blanket rate limit ------------------------------------------
  dynamic "rule" {
    for_each = local.baseline_rate_enabled ? [1] : []
    content {
      name     = "baseline-rate-limit"
      priority = local.priority["rate/__baseline__"]
      action {
        dynamic "block" {
          for_each = (var.count_mode || var.baseline_count_only) ? [] : [1]
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = (var.count_mode || var.baseline_count_only) ? [1] : []
          content {}
        }
      }
      statement {
        rate_based_statement {
          limit              = var.baseline_rate_limit
          aggregate_key_type = "IP"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-baseline-rate-limit"
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- user rate-based rules ------------------------------------------------
  dynamic "rule" {
    for_each = { for r in local.rate_rules : r.name => r }
    content {
      name     = "rate-${rule.value.name}"
      priority = local.priority["rate/${rule.value.name}"]
      action {
        dynamic "block" {
          for_each = (!var.count_mode && rule.value.action == "block") ? [1] : []
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = (var.count_mode || rule.value.action == "count") ? [1] : []
          content {}
        }
        dynamic "captcha" {
          for_each = (!var.count_mode && rule.value.action == "captcha") ? [1] : []
          content {}
        }
        dynamic "challenge" {
          for_each = (!var.count_mode && rule.value.action == "challenge") ? [1] : []
          content {}
        }
      }
      statement {
        rate_based_statement {
          limit                 = rule.value.limit
          aggregate_key_type    = rule.value.aggregate_key
          evaluation_window_sec = rule.value.evaluation_window

          dynamic "forwarded_ip_config" {
            for_each = rule.value.aggregate_key == "FORWARDED_IP" ? [1] : []
            content {
              fallback_behavior = "MATCH"
              header_name       = "X-Forwarded-For"
            }
          }

          dynamic "scope_down_statement" {
            for_each = rule.value.has_sd ? [1] : []
            content {
              dynamic "and_statement" {
                for_each = rule.value.sd_both ? [1] : []
                content {
                  statement {
                    byte_match_statement {
                      search_string         = rule.value.sd_uri
                      positional_constraint = "CONTAINS"
                      field_to_match {
                        uri_path {}
                      }
                      text_transformation {
                        priority = 0
                        type     = "NONE"
                      }
                    }
                  }
                  statement {
                    geo_match_statement {
                      country_codes = rule.value.sd_geo
                    }
                  }
                }
              }
              dynamic "byte_match_statement" {
                for_each = (!rule.value.sd_both && rule.value.sd_uri != "") ? [1] : []
                content {
                  search_string         = rule.value.sd_uri
                  positional_constraint = "CONTAINS"
                  field_to_match {
                    uri_path {}
                  }
                  text_transformation {
                    priority = 0
                    type     = "NONE"
                  }
                }
              }
              dynamic "geo_match_statement" {
                for_each = (!rule.value.sd_both && rule.value.sd_uri == "" && length(rule.value.sd_geo) > 0) ? [1] : []
                content {
                  country_codes = rule.value.sd_geo
                }
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-rate-${rule.value.name}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- baseline managed groups ----------------------------------------------
  dynamic "rule" {
    for_each = { for g in local.baseline_groups : g.name => g }
    content {
      name     = rule.value.name
      priority = local.priority["managed/${rule.value.name}"]
      override_action {
        dynamic "none" {
          for_each = (rule.value.count_only || var.count_mode) ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = (rule.value.count_only || var.count_mode) ? [1] : []
          content {}
        }
      }
      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = "AWS"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-${rule.value.name}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- user managed groups --------------------------------------------------
  dynamic "rule" {
    for_each = { for g in var.managed_rule_groups : g.name => g }
    content {
      name     = rule.value.name
      priority = local.priority["managed/${rule.value.name}"]
      override_action {
        dynamic "none" {
          for_each = (rule.value.count_only || var.count_mode) ? [] : [1]
          content {}
        }
        dynamic "count" {
          for_each = (rule.value.count_only || var.count_mode) ? [1] : []
          content {}
        }
      }
      statement {
        managed_rule_group_statement {
          name        = rule.value.name
          vendor_name = rule.value.vendor
          version     = rule.value.version

          dynamic "rule_action_override" {
            for_each = rule.value.rule_action_overrides
            content {
              name = rule_action_override.key
              action_to_use {
                dynamic "allow" {
                  for_each = rule_action_override.value == "allow" ? [1] : []
                  content {}
                }
                dynamic "block" {
                  for_each = rule_action_override.value == "block" ? [1] : []
                  content {}
                }
                dynamic "count" {
                  for_each = rule_action_override.value == "count" ? [1] : []
                  content {}
                }
                dynamic "captcha" {
                  for_each = rule_action_override.value == "captcha" ? [1] : []
                  content {}
                }
                dynamic "challenge" {
                  for_each = rule_action_override.value == "challenge" ? [1] : []
                  content {}
                }
              }
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-${rule.value.name}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  # ---- custom match rules (priority encodes pre/post-managed phase) ----------
  dynamic "rule" {
    for_each = { for r in var.custom_rules : r.name => r }
    content {
      name     = "custom-${rule.value.name}"
      priority = local.priority["custom/${rule.value.name}"]
      action {
        dynamic "allow" {
          for_each = (!var.count_mode && rule.value.action == "allow") ? [1] : []
          content {}
        }
        dynamic "block" {
          for_each = (!var.count_mode && rule.value.action == "block") ? [1] : []
          content {
            dynamic "custom_response" {
              for_each = var.block_response != null ? [var.block_response] : []
              content {
                response_code            = custom_response.value.status_code
                custom_response_body_key = custom_response.value.custom_response_body_key
                dynamic "response_header" {
                  for_each = custom_response.value.response_headers
                  content {
                    name  = response_header.key
                    value = response_header.value
                  }
                }
              }
            }
          }
        }
        dynamic "count" {
          for_each = (var.count_mode || rule.value.action == "count") ? [1] : []
          content {}
        }
        dynamic "captcha" {
          for_each = (!var.count_mode && rule.value.action == "captcha") ? [1] : []
          content {}
        }
        dynamic "challenge" {
          for_each = (!var.count_mode && rule.value.action == "challenge") ? [1] : []
          content {}
        }
      }
      statement {
        # label match (act on a label emitted by a managed group / Bot Control)
        dynamic "label_match_statement" {
          for_each = rule.value.type == "label" ? [1] : []
          content {
            scope = "LABEL"
            key   = rule.value.value
          }
        }
        # byte match (contains / starts_with / ends_with / exactly)
        dynamic "byte_match_statement" {
          for_each = contains(["contains", "starts_with", "ends_with", "exactly"], rule.value.type) ? [1] : []
          content {
            search_string         = rule.value.value
            positional_constraint = local.byte_match_positional[rule.value.type]
            field_to_match {
              dynamic "uri_path" {
                for_each = rule.value.field == "uri_path" ? [1] : []
                content {}
              }
              dynamic "query_string" {
                for_each = rule.value.field == "query_string" ? [1] : []
                content {}
              }
              dynamic "method" {
                for_each = rule.value.field == "method" ? [1] : []
                content {}
              }
              dynamic "all_query_arguments" {
                for_each = rule.value.field == "all_query_args" ? [1] : []
                content {}
              }
              dynamic "body" {
                for_each = rule.value.field == "body" ? [1] : []
                content { oversize_handling = rule.value.oversize_handling }
              }
              dynamic "single_header" {
                for_each = rule.value.field == "single_header" ? [1] : []
                content { name = lower(rule.value.header_name) }
              }
            }
            text_transformation {
              priority = 0
              type     = rule.value.text_transform
            }
          }
        }
        # regex match (single pattern)
        dynamic "regex_match_statement" {
          for_each = rule.value.type == "regex" ? [1] : []
          content {
            regex_string = rule.value.value
            field_to_match {
              dynamic "uri_path" {
                for_each = rule.value.field == "uri_path" ? [1] : []
                content {}
              }
              dynamic "query_string" {
                for_each = rule.value.field == "query_string" ? [1] : []
                content {}
              }
              dynamic "method" {
                for_each = rule.value.field == "method" ? [1] : []
                content {}
              }
              dynamic "all_query_arguments" {
                for_each = rule.value.field == "all_query_args" ? [1] : []
                content {}
              }
              dynamic "body" {
                for_each = rule.value.field == "body" ? [1] : []
                content { oversize_handling = rule.value.oversize_handling }
              }
              dynamic "single_header" {
                for_each = rule.value.field == "single_header" ? [1] : []
                content { name = lower(rule.value.header_name) }
              }
            }
            text_transformation {
              priority = 0
              type     = rule.value.text_transform
            }
          }
        }
        # regex pattern set (multiple patterns)
        dynamic "regex_pattern_set_reference_statement" {
          for_each = rule.value.type == "regex_set" ? [1] : []
          content {
            arn = aws_wafv2_regex_pattern_set.custom[rule.value.name].arn
            field_to_match {
              dynamic "uri_path" {
                for_each = rule.value.field == "uri_path" ? [1] : []
                content {}
              }
              dynamic "query_string" {
                for_each = rule.value.field == "query_string" ? [1] : []
                content {}
              }
              dynamic "method" {
                for_each = rule.value.field == "method" ? [1] : []
                content {}
              }
              dynamic "all_query_arguments" {
                for_each = rule.value.field == "all_query_args" ? [1] : []
                content {}
              }
              dynamic "body" {
                for_each = rule.value.field == "body" ? [1] : []
                content { oversize_handling = rule.value.oversize_handling }
              }
              dynamic "single_header" {
                for_each = rule.value.field == "single_header" ? [1] : []
                content { name = lower(rule.value.header_name) }
              }
            }
            text_transformation {
              priority = 0
              type     = rule.value.text_transform
            }
          }
        }
        # size constraint
        dynamic "size_constraint_statement" {
          for_each = rule.value.type == "size" ? [1] : []
          content {
            comparison_operator = coalesce(rule.value.size_operator, local.size_operator_default)
            size                = rule.value.size
            field_to_match {
              dynamic "uri_path" {
                for_each = rule.value.field == "uri_path" ? [1] : []
                content {}
              }
              dynamic "query_string" {
                for_each = rule.value.field == "query_string" ? [1] : []
                content {}
              }
              dynamic "method" {
                for_each = rule.value.field == "method" ? [1] : []
                content {}
              }
              dynamic "all_query_arguments" {
                for_each = rule.value.field == "all_query_args" ? [1] : []
                content {}
              }
              dynamic "body" {
                for_each = rule.value.field == "body" ? [1] : []
                content { oversize_handling = rule.value.oversize_handling }
              }
              dynamic "single_header" {
                for_each = rule.value.field == "single_header" ? [1] : []
                content { name = lower(rule.value.header_name) }
              }
            }
            text_transformation {
              priority = 0
              type     = rule.value.text_transform
            }
          }
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace("${var.name}-custom-${rule.value.name}", "/[^0-9A-Za-z_-]/", "-")
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = replace(var.name, "/[^0-9A-Za-z_-]/", "-")
    sampled_requests_enabled   = true
  }

  lifecycle {
    precondition {
      condition     = local.rule_names_unique_ok
      error_message = "Rule names collide (a managed group name is duplicated, or a baseline group is re-added). Names must be unique across the ACL."
    }
    precondition {
      condition     = local.block_response_key_ok
      error_message = "block_response.custom_response_body_key must be a key defined in custom_response_bodies."
    }
  }
}

# WCU (Web ACL Capacity Units) is only known after apply and the WAF ceiling is
# 1500 by default. It's surfaced via the web_acl_capacity output rather than a
# check{} block (check assertions are known-after-apply and break plan-mode
# tests); wire an alarm on the output or watch it in CI as the ACL grows.
