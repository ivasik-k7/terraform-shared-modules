locals {
  target_groups = local.create ? var.target_groups : {}

  # Flatten per-target-group static targets into a single attachment map.
  target_group_attachments = merge([
    for tg_key, tg in local.target_groups : {
      for t_key, t in tg.targets :
      "${tg_key}/${t_key}" => {
        target_group_key  = tg_key
        target_id         = t.target_id
        port              = t.port
        availability_zone = t.availability_zone
      }
    }
  ]...)

  # Lambda targets need an invoke permission for the ELB service.
  lambda_permissions = {
    for att_key, att in local.target_group_attachments :
    att_key => att
    if var.target_groups[att.target_group_key].target_type == "lambda" && var.target_groups[att.target_group_key].create_lambda_permission
  }
}

resource "aws_lb_target_group" "this" {
  for_each = local.target_groups

  # Prefer an explicit name; else a (CBD-safe) name_prefix derived from the key.
  # Sanitize to alphanumeric and cap at 6 chars (target-group name_prefix rules).
  name        = each.value.name
  name_prefix = each.value.name == null ? substr(replace(coalesce(each.value.name_prefix, each.key), "/[^a-zA-Z0-9]/", ""), 0, 6) : null

  target_type = each.value.target_type

  # Lambda target groups take no port/protocol/vpc.
  port             = each.value.target_type == "lambda" ? null : each.value.port
  protocol         = each.value.target_type == "lambda" ? null : coalesce(each.value.protocol, local.default_tg_protocol)
  protocol_version = each.value.target_type == "lambda" ? null : each.value.protocol_version
  vpc_id           = each.value.target_type == "lambda" ? null : coalesce(each.value.vpc_id, var.vpc_id)

  deregistration_delay          = each.value.deregistration_delay
  slow_start                    = each.value.slow_start
  load_balancing_algorithm_type = each.value.load_balancing_algorithm_type
  preserve_client_ip            = each.value.preserve_client_ip
  proxy_protocol_v2             = each.value.proxy_protocol_v2
  connection_termination        = each.value.connection_termination
  ip_address_type               = each.value.ip_address_type

  dynamic "health_check" {
    for_each = each.value.health_check != null ? [each.value.health_check] : []
    content {
      enabled             = health_check.value.enabled
      healthy_threshold   = health_check.value.healthy_threshold
      unhealthy_threshold = health_check.value.unhealthy_threshold
      interval            = health_check.value.interval
      timeout             = health_check.value.timeout
      path                = health_check.value.path
      port                = health_check.value.port
      protocol            = health_check.value.protocol
      matcher             = health_check.value.matcher
    }
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness != null ? [each.value.stickiness] : []
    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_duration = stickiness.value.cookie_duration
      cookie_name     = stickiness.value.cookie_name
    }
  }

  dynamic "target_failover" {
    for_each = each.value.target_failover != null ? [each.value.target_failover] : []
    content {
      on_deregistration = target_failover.value.on_deregistration
      on_unhealthy      = target_failover.value.on_unhealthy
    }
  }

  dynamic "target_health_state" {
    for_each = each.value.target_health_state != null ? [each.value.target_health_state] : []
    content {
      enable_unhealthy_connection_termination = target_health_state.value.enable_unhealthy_connection_termination
      unhealthy_draining_interval             = target_health_state.value.unhealthy_draining_interval
    }
  }

  dynamic "target_group_health" {
    for_each = each.value.target_group_health != null ? [each.value.target_group_health] : []
    content {
      dynamic "dns_failover" {
        for_each = target_group_health.value.dns_failover != null ? [target_group_health.value.dns_failover] : []
        content {
          minimum_healthy_targets_count      = dns_failover.value.minimum_healthy_targets_count
          minimum_healthy_targets_percentage = dns_failover.value.minimum_healthy_targets_percentage
        }
      }
      dynamic "unhealthy_state_routing" {
        for_each = target_group_health.value.unhealthy_state_routing != null ? [target_group_health.value.unhealthy_state_routing] : []
        content {
          minimum_healthy_targets_count      = unhealthy_state_routing.value.minimum_healthy_targets_count
          minimum_healthy_targets_percentage = unhealthy_state_routing.value.minimum_healthy_targets_percentage
        }
      }
    }
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = coalesce(each.value.name, "${var.name}-${each.key}") })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lambda_permission" "this" {
  for_each = local.lambda_permissions

  statement_id  = "AllowExecutionFromLB-${replace(each.key, "/[^a-zA-Z0-9]/", "-")}"
  action        = "lambda:InvokeFunction"
  function_name = each.value.target_id
  principal     = "elasticloadbalancing.amazonaws.com"
  source_arn    = aws_lb_target_group.this[each.value.target_group_key].arn
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = local.target_group_attachments

  target_group_arn  = aws_lb_target_group.this[each.value.target_group_key].arn
  target_id         = each.value.target_id
  port              = each.value.port
  availability_zone = each.value.availability_zone

  # Lambda registration requires the invoke permission to exist first.
  depends_on = [aws_lambda_permission.this]
}
