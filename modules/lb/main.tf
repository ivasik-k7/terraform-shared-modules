locals {
  create         = var.create
  is_application = var.load_balancer_type == "application"
  is_network     = var.load_balancer_type == "network"

  # Protocol defaults differ by LB type.
  default_listener_protocol = local.is_application ? "HTTP" : "TCP"
  default_tg_protocol       = local.is_application ? "HTTP" : "TCP"

  create_security_group = local.create && var.create_security_group

  security_group_ids = concat(
    local.create_security_group ? [aws_security_group.this[0].id] : [],
    var.security_group_ids,
  )

  # Resolve target-group keys to ARNs for listeners and rules.
  target_group_arns = { for k, tg in aws_lb_target_group.this : k => tg.arn }

  common_tags = merge(
    var.tags,
    {
      "Module"    = "lb"
      "ManagedBy" = "Terraform"
    }
  )
}

resource "aws_lb" "this" {
  count = local.create ? 1 : 0

  name               = var.name
  internal           = var.internal
  load_balancer_type = var.load_balancer_type
  ip_address_type    = var.ip_address_type

  subnets         = length(var.subnets) > 0 ? var.subnets : null
  security_groups = length(local.security_group_ids) > 0 ? local.security_group_ids : null

  dynamic "subnet_mapping" {
    for_each = var.subnet_mappings
    content {
      subnet_id            = subnet_mapping.value.subnet_id
      allocation_id        = subnet_mapping.value.allocation_id
      private_ipv4_address = subnet_mapping.value.private_ipv4_address
      ipv6_address         = subnet_mapping.value.ipv6_address
    }
  }

  enable_deletion_protection = var.enable_deletion_protection

  # Application-only attributes (null elsewhere so the provider omits them).
  idle_timeout                                = local.is_application ? var.idle_timeout : null
  enable_http2                                = local.is_application ? var.enable_http2 : null
  drop_invalid_header_fields                  = local.is_application ? var.drop_invalid_header_fields : null
  preserve_host_header                        = local.is_application ? var.preserve_host_header : null
  desync_mitigation_mode                      = local.is_application ? var.desync_mitigation_mode : null
  client_keep_alive                           = local.is_application ? var.client_keep_alive : null
  enable_xff_client_port                      = local.is_application ? var.enable_xff_client_port : null
  xff_header_processing_mode                  = local.is_application ? var.xff_header_processing_mode : null
  enable_waf_fail_open                        = local.is_application ? var.enable_waf_fail_open : null
  enable_tls_version_and_cipher_suite_headers = local.is_application ? var.enable_tls_version_and_cipher_suite_headers : null

  # Network-only attributes.
  enable_cross_zone_load_balancing                             = local.is_application ? null : var.enable_cross_zone_load_balancing
  enforce_security_group_inbound_rules_on_private_link_traffic = local.is_network ? var.enforce_security_group_inbound_rules_on_private_link_traffic : null

  dynamic "access_logs" {
    for_each = var.access_logs != null ? [var.access_logs] : []
    content {
      bucket  = access_logs.value.bucket
      prefix  = access_logs.value.prefix
      enabled = access_logs.value.enabled
    }
  }

  dynamic "connection_logs" {
    for_each = local.is_application && var.connection_logs != null ? [var.connection_logs] : []
    content {
      bucket  = connection_logs.value.bucket
      prefix  = connection_logs.value.prefix
      enabled = connection_logs.value.enabled
    }
  }

  tags = merge(local.common_tags, { "Name" = var.name })

  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  lifecycle {
    precondition {
      condition     = var.load_balancer_type != "application" || var.create_security_group || length(var.security_group_ids) > 0
      error_message = "An application load balancer requires a security group: set create_security_group = true or provide security_group_ids."
    }

    precondition {
      condition     = length(var.subnets) > 0 || length(var.subnet_mappings) > 0
      error_message = "Provide either subnets or subnet_mappings for the load balancer."
    }

    precondition {
      condition     = !(length(var.subnets) > 0 && length(var.subnet_mappings) > 0)
      error_message = "Set either subnets or subnet_mappings, not both."
    }

    precondition {
      condition     = var.web_acl_arn == null || var.load_balancer_type == "application"
      error_message = "web_acl_arn can only be associated with an application load balancer."
    }
  }
}

# ============================================================================
# WAFv2 WEB ACL ASSOCIATION
# ============================================================================

resource "aws_wafv2_web_acl_association" "this" {
  count = local.create && var.web_acl_arn != null ? 1 : 0

  resource_arn = aws_lb.this[0].arn
  web_acl_arn  = var.web_acl_arn
}

# ============================================================================
# ROUTE 53 ALIAS RECORDS
# ============================================================================

resource "aws_route53_record" "this" {
  for_each = local.create ? var.route53_records : {}

  zone_id = each.value.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_lb.this[0].dns_name
    zone_id                = aws_lb.this[0].zone_id
    evaluate_target_health = each.value.evaluate_target_health
  }
}
