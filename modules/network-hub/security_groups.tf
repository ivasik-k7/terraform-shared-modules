# Custom security groups. Rules are declared inline on the SG for brevity.
# If you need to add/remove rules without destructive churn at scale, manage
# rules outside the module via aws_vpc_security_group_{ingress,egress}_rule.
resource "aws_security_group" "custom" {
  for_each = var.security_groups

  name        = "${var.name}-${each.key}"
  description = each.value.description
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = each.value.ingress_rules
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
      prefix_list_ids  = ingress.value.prefix_list_ids
      security_groups  = ingress.value.security_groups
      self             = ingress.value.self
    }
  }

  dynamic "egress" {
    for_each = each.value.egress_rules
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
      prefix_list_ids  = egress.value.prefix_list_ids
      security_groups  = egress.value.security_groups
      self             = egress.value.self
    }
  }

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# AWS creates a default SG on every VPC that cannot be deleted. Best practice
# is to adopt it and strip its rules (default has "allow all from self" which
# is often undesirable). Opt in via manage_default_security_group = true.
resource "aws_default_security_group" "this" {
  count = var.manage_default_security_group ? 1 : 0

  vpc_id = local.vpc_id

  dynamic "ingress" {
    for_each = var.default_security_group_ingress
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks
      prefix_list_ids  = ingress.value.prefix_list_ids
      security_groups  = ingress.value.security_groups
      self             = ingress.value.self
    }
  }

  dynamic "egress" {
    for_each = var.default_security_group_egress
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks
      prefix_list_ids  = egress.value.prefix_list_ids
      security_groups  = egress.value.security_groups
      self             = egress.value.self
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-default-sg"
  })
}
