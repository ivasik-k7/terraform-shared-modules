data "aws_vpc" "this" {
  id = var.vpc_id
}

resource "aws_security_group" "this" {
  for_each = var.security_groups

  name        = local.name != null ? "${local.name}-${each.key}" : each.key
  description = each.value.description
  vpc_id      = var.vpc_id

  revoke_rules_on_delete = var.revoke_rules_on_delete

  tags = merge(
    { Name = local.name != null ? "${local.name}-${each.key}" : each.key },
    var.default_tags,
    each.value.tags,
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cidr_ipv4" {
  for_each = local.ingress_cidr_ipv4

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = each.value.cidr_ipv4

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "cidr_ipv6" {
  for_each = local.ingress_cidr_ipv6

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv6         = each.value.cidr_ipv6

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "self" {
  for_each = local.ingress_self

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = aws_security_group.this[each.value.sg_key].id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "sg_key" {
  for_each = local.ingress_sg_key

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = aws_security_group.this[each.value.source_security_group_key].id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "sg_id" {
  for_each = local.ingress_sg_id

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = each.value.source_security_group_id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_ingress_rule" "prefix_list" {
  for_each = local.ingress_prefix_list

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  prefix_list_id    = each.value.prefix_list_id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "cidr_ipv4" {
  for_each = local.egress_cidr_ipv4

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv4         = each.value.cidr_ipv4

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "cidr_ipv6" {
  for_each = local.egress_cidr_ipv6

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  cidr_ipv6         = each.value.cidr_ipv6

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "self" {
  for_each = local.egress_self

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = aws_security_group.this[each.value.sg_key].id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "sg_key" {
  for_each = local.egress_sg_key

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = aws_security_group.this[each.value.destination_security_group_key].id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "sg_id" {
  for_each = local.egress_sg_id

  security_group_id            = aws_security_group.this[each.value.sg_key].id
  description                  = each.value.description
  from_port                    = each.value.protocol == "-1" ? null : each.value.from_port
  to_port                      = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol                  = each.value.protocol
  referenced_security_group_id = each.value.destination_security_group_id

  tags = { Rule = each.key }
}

resource "aws_vpc_security_group_egress_rule" "prefix_list" {
  for_each = local.egress_prefix_list

  security_group_id = aws_security_group.this[each.value.sg_key].id
  description       = each.value.description
  from_port         = each.value.protocol == "-1" ? null : each.value.from_port
  to_port           = each.value.protocol == "-1" ? null : each.value.to_port
  ip_protocol       = each.value.protocol
  prefix_list_id    = each.value.prefix_list_id

  tags = { Rule = each.key }
}
