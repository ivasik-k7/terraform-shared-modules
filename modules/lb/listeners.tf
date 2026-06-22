locals {
  listeners = local.create ? var.listeners : {}

  # Default SSL policy applied to HTTPS/TLS listeners when none is given.
  default_ssl_policy = "ELBSecurityPolicy-TLS13-1-2-2021-06"

  # Flatten additional (SNI) certificates into a per-listener attachment map.
  listener_certificates = merge([
    for l_key, l in local.listeners : {
      for cert in l.additional_certificate_arns :
      "${l_key}/${cert}" => {
        listener_key    = l_key
        certificate_arn = cert
      }
    }
  ]...)
}

resource "aws_lb_listener" "this" {
  for_each = local.listeners

  load_balancer_arn = aws_lb.this[0].arn
  port              = each.value.port
  protocol          = coalesce(each.value.protocol, local.default_listener_protocol)

  certificate_arn          = each.value.certificate_arn
  ssl_policy               = each.value.certificate_arn != null ? coalesce(each.value.ssl_policy, local.default_ssl_policy) : null
  alpn_policy              = each.value.alpn_policy
  tcp_idle_timeout_seconds = each.value.tcp_idle_timeout_seconds

  dynamic "mutual_authentication" {
    for_each = each.value.mutual_authentication != null ? [each.value.mutual_authentication] : []
    content {
      mode                             = mutual_authentication.value.mode
      trust_store_arn                  = mutual_authentication.value.trust_store_arn
      ignore_client_certificate_expiry = mutual_authentication.value.ignore_client_certificate_expiry
    }
  }

  # Optional edge authentication action, evaluated before the main action.
  dynamic "default_action" {
    for_each = each.value.default_action.authenticate_cognito != null ? [each.value.default_action.authenticate_cognito] : []
    content {
      type  = "authenticate-cognito"
      order = 1
      authenticate_cognito {
        user_pool_arn                       = default_action.value.user_pool_arn
        user_pool_client_id                 = default_action.value.user_pool_client_id
        user_pool_domain                    = default_action.value.user_pool_domain
        authentication_request_extra_params = default_action.value.authentication_request_extra_params
        on_unauthenticated_request          = default_action.value.on_unauthenticated_request
        scope                               = default_action.value.scope
        session_cookie_name                 = default_action.value.session_cookie_name
        session_timeout                     = default_action.value.session_timeout
      }
    }
  }

  dynamic "default_action" {
    for_each = each.value.default_action.authenticate_oidc != null ? [each.value.default_action.authenticate_oidc] : []
    content {
      type  = "authenticate-oidc"
      order = 1
      authenticate_oidc {
        authorization_endpoint              = default_action.value.authorization_endpoint
        client_id                           = default_action.value.client_id
        client_secret                       = default_action.value.client_secret
        issuer                              = default_action.value.issuer
        token_endpoint                      = default_action.value.token_endpoint
        user_info_endpoint                  = default_action.value.user_info_endpoint
        authentication_request_extra_params = default_action.value.authentication_request_extra_params
        on_unauthenticated_request          = default_action.value.on_unauthenticated_request
        scope                               = default_action.value.scope
        session_cookie_name                 = default_action.value.session_cookie_name
        session_timeout                     = default_action.value.session_timeout
      }
    }
  }

  default_action {
    type  = each.value.default_action.type
    order = (each.value.default_action.authenticate_cognito != null || each.value.default_action.authenticate_oidc != null) ? 2 : null

    target_group_arn = (
      each.value.default_action.type == "forward" && each.value.default_action.target_group_key != null
      ? local.target_group_arns[each.value.default_action.target_group_key]
      : null
    )

    dynamic "forward" {
      for_each = each.value.default_action.target_groups != null ? [each.value.default_action] : []
      content {
        dynamic "target_group" {
          for_each = forward.value.target_groups
          content {
            arn    = local.target_group_arns[target_group.value.target_group_key]
            weight = target_group.value.weight
          }
        }
        dynamic "stickiness" {
          for_each = forward.value.stickiness != null ? [forward.value.stickiness] : []
          content {
            enabled  = stickiness.value.enabled
            duration = stickiness.value.duration
          }
        }
      }
    }

    dynamic "redirect" {
      for_each = each.value.default_action.redirect != null ? [each.value.default_action.redirect] : []
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
      for_each = each.value.default_action.fixed_response != null ? [each.value.default_action.fixed_response] : []
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.name}-${each.key}" })
}

resource "aws_lb_listener_certificate" "this" {
  for_each = local.listener_certificates

  listener_arn    = aws_lb_listener.this[each.value.listener_key].arn
  certificate_arn = each.value.certificate_arn
}
