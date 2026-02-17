data "aws_region" "current" {}

data "aws_vpc" "this" {
  id = var.vpc_id
}

locals {
  region = var.region != "" ? var.region : data.aws_region.current.name
}

resource "aws_security_group" "default" {
  count = local.create_default_sg ? 1 : 0

  name        = var.default_security_group_name != "" ? var.default_security_group_name : "vpce-${var.vpc_id}-default"
  description = var.default_security_group_description
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    var.security_group_tags,
    { Name = var.default_security_group_name != "" ? var.default_security_group_name : "vpce-${var.vpc_id}-default" }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "default_ingress_vpc_cidr" {
  count = local.create_default_sg && length(var.default_security_group_ingress_rules) == 0 ? 1 : 0

  security_group_id = aws_security_group.default[0].id
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [data.aws_vpc.this.cidr_block]
  description       = "Allow HTTPS from within the VPC"
}

resource "aws_security_group_rule" "default_ingress_custom" {
  for_each = local.create_default_sg ? {
    for idx, rule in var.default_security_group_ingress_rules : tostring(idx) => rule
  } : {}

  security_group_id        = aws_security_group.default[0].id
  type                     = "ingress"
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  ipv6_cidr_blocks         = length(each.value.ipv6_cidr_blocks) > 0 ? each.value.ipv6_cidr_blocks : null
  source_security_group_id = length(each.value.security_groups) == 1 ? each.value.security_groups[0] : null
  self                     = each.value.self ? true : null
  description              = each.value.description
}

resource "aws_security_group_rule" "default_egress" {
  for_each = local.create_default_sg ? {
    for idx, rule in var.default_security_group_egress_rules : tostring(idx) => rule
  } : {}

  security_group_id        = aws_security_group.default[0].id
  type                     = "egress"
  from_port                = each.value.from_port
  to_port                  = each.value.to_port
  protocol                 = each.value.protocol
  cidr_blocks              = length(each.value.cidr_blocks) > 0 ? each.value.cidr_blocks : null
  ipv6_cidr_blocks         = length(each.value.ipv6_cidr_blocks) > 0 ? each.value.ipv6_cidr_blocks : null
  source_security_group_id = length(each.value.security_groups) == 1 ? each.value.security_groups[0] : null
  self                     = each.value.self ? true : null
  description              = each.value.description
}

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoints

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = each.value.private_dns_enabled
  auto_accept         = each.value.auto_accept
  ip_address_type     = each.value.ip_address_type
  policy              = each.value.policy
  subnet_ids          = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : null
  security_group_ids  = length(local.effective_sg_ids[each.key]) > 0 ? local.effective_sg_ids[each.key] : null

  dynamic "dns_options" {
    for_each = each.value.private_dns_enabled ? [1] : []
    content {
      dns_record_ip_type = each.value.ip_address_type != null ? each.value.ip_address_type : "ipv4"
    }
  }

  tags = merge(
    each.value.tags,
    { Name = each.key }
  )

  timeouts {
    create = try(each.value.timeouts.create, "10m")
    update = try(each.value.timeouts.update, "10m")
    delete = try(each.value.timeouts.delete, "10m")
  }
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoints

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  auto_accept       = each.value.auto_accept
  policy            = each.value.policy
  route_table_ids   = length(each.value.route_table_ids) > 0 ? each.value.route_table_ids : null

  tags = merge(
    each.value.tags,
    { Name = each.key }
  )

  timeouts {
    create = try(each.value.timeouts.create, "10m")
    update = try(each.value.timeouts.update, "10m")
    delete = try(each.value.timeouts.delete, "10m")
  }
}

resource "aws_vpc_endpoint" "gwlb" {
  for_each = local.gwlb_endpoints

  vpc_id            = var.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "GatewayLoadBalancer"
  auto_accept       = each.value.auto_accept
  subnet_ids        = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : null

  tags = merge(
    each.value.tags,
    { Name = each.key }
  )

  timeouts {
    create = try(each.value.timeouts.create, "10m")
    update = try(each.value.timeouts.update, "10m")
    delete = try(each.value.timeouts.delete, "10m")
  }
}

resource "aws_vpc_endpoint_connection_notification" "interface" {
  for_each = {
    for k, v in local.interface_endpoints : k => v
    if length(v.notification_arns) > 0
  }

  vpc_endpoint_id             = aws_vpc_endpoint.interface[each.key].id
  connection_notification_arn = each.value.notification_arns[0]
  connection_events           = ["Accept", "Reject", "Connect", "Delete"]
}

resource "aws_vpc_endpoint_connection_notification" "gateway" {
  for_each = {
    for k, v in local.gateway_endpoints : k => v
    if length(v.notification_arns) > 0
  }

  vpc_endpoint_id             = aws_vpc_endpoint.gateway[each.key].id
  connection_notification_arn = each.value.notification_arns[0]
  connection_events           = ["Accept", "Reject", "Connect", "Delete"]
}

resource "aws_vpc_endpoint_connection_notification" "gwlb" {
  for_each = {
    for k, v in local.gwlb_endpoints : k => v
    if length(v.notification_arns) > 0
  }

  vpc_endpoint_id             = aws_vpc_endpoint.gwlb[each.key].id
  connection_notification_arn = each.value.notification_arns[0]
  connection_events           = ["Accept", "Reject", "Connect", "Delete"]
}
