resource "aws_lb_listener_rule" "this" {
  for_each = local.create ? var.listener_rules : {}

  listener_arn = aws_lb_listener.this[each.value.listener_key].arn
  priority     = each.value.priority

  dynamic "action" {
    for_each = each.value.actions
    content {
      type = action.value.type
      # Explicit order so multi-action rules (e.g. authenticate-* then forward)
      # are applied in declaration order; required by AWS when >1 action.
      order = action.key + 1

      target_group_arn = (
        action.value.type == "forward" && action.value.target_group_key != null
        ? local.target_group_arns[action.value.target_group_key]
        : null
      )

      dynamic "forward" {
        for_each = action.value.target_groups != null ? [action.value.target_groups] : []
        content {
          dynamic "target_group" {
            for_each = forward.value
            content {
              arn    = local.target_group_arns[target_group.value.target_group_key]
              weight = target_group.value.weight
            }
          }
        }
      }

      dynamic "redirect" {
        for_each = action.value.redirect != null ? [action.value.redirect] : []
        content {
          status_code = redirect.value.status_code
          host        = redirect.value.host
          path        = redirect.value.path
          port        = redirect.value.port
          protocol    = redirect.value.protocol
          query       = redirect.value.query
        }
      }

      dynamic "fixed_response" {
        for_each = action.value.fixed_response != null ? [action.value.fixed_response] : []
        content {
          content_type = fixed_response.value.content_type
          message_body = fixed_response.value.message_body
          status_code  = fixed_response.value.status_code
        }
      }

      dynamic "authenticate_cognito" {
        for_each = action.value.authenticate_cognito != null ? [action.value.authenticate_cognito] : []
        content {
          user_pool_arn                       = authenticate_cognito.value.user_pool_arn
          user_pool_client_id                 = authenticate_cognito.value.user_pool_client_id
          user_pool_domain                    = authenticate_cognito.value.user_pool_domain
          authentication_request_extra_params = authenticate_cognito.value.authentication_request_extra_params
          on_unauthenticated_request          = authenticate_cognito.value.on_unauthenticated_request
          scope                               = authenticate_cognito.value.scope
          session_cookie_name                 = authenticate_cognito.value.session_cookie_name
          session_timeout                     = authenticate_cognito.value.session_timeout
        }
      }

      dynamic "authenticate_oidc" {
        for_each = action.value.authenticate_oidc != null ? [action.value.authenticate_oidc] : []
        content {
          authorization_endpoint              = authenticate_oidc.value.authorization_endpoint
          client_id                           = authenticate_oidc.value.client_id
          client_secret                       = authenticate_oidc.value.client_secret
          issuer                              = authenticate_oidc.value.issuer
          token_endpoint                      = authenticate_oidc.value.token_endpoint
          user_info_endpoint                  = authenticate_oidc.value.user_info_endpoint
          authentication_request_extra_params = authenticate_oidc.value.authentication_request_extra_params
          on_unauthenticated_request          = authenticate_oidc.value.on_unauthenticated_request
          scope                               = authenticate_oidc.value.scope
          session_cookie_name                 = authenticate_oidc.value.session_cookie_name
          session_timeout                     = authenticate_oidc.value.session_timeout
        }
      }
    }
  }

  dynamic "condition" {
    for_each = each.value.conditions
    content {
      dynamic "path_pattern" {
        for_each = condition.value.path_patterns != null ? [1] : []
        content {
          values = condition.value.path_patterns
        }
      }

      dynamic "host_header" {
        for_each = condition.value.host_headers != null ? [1] : []
        content {
          values = condition.value.host_headers
        }
      }

      dynamic "http_header" {
        for_each = condition.value.http_header != null ? [condition.value.http_header] : []
        content {
          http_header_name = http_header.value.name
          values           = http_header.value.values
        }
      }

      dynamic "query_string" {
        for_each = condition.value.query_strings != null ? condition.value.query_strings : []
        content {
          key   = query_string.value.key
          value = query_string.value.value
        }
      }

      dynamic "source_ip" {
        for_each = condition.value.source_ips != null ? [1] : []
        content {
          values = condition.value.source_ips
        }
      }

      dynamic "http_request_method" {
        for_each = condition.value.http_request_methods != null ? [1] : []
        content {
          values = condition.value.http_request_methods
        }
      }
    }
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.name}-${each.key}" })
}
