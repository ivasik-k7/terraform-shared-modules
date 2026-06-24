# sg is ssm-only by default (no inbound). open ssh via the ssh_* helpers if you
# really must. egress stays open so the box can reach the ssm/vpc endpoints.

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  name_prefix = "${var.name}-bastion-"
  description = "Security group for bastion ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.create_security_group ? local.ingress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion-ingress-${each.key}" })
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.create_security_group ? var.security_group_egress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion-egress-${each.key}" })
}
