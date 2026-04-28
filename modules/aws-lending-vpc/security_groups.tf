# Custom SGs declared via var.security_groups. Inline rules — convenient for
# small SGs, but if you have a large or churn-heavy rule set, prefer
# aws_vpc_security_group_{ingress,egress}_rule outside the module so edits
# don't replace the whole SG.
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

  # create_before_destroy avoids "SG in use by ENIs" errors when names change.
  lifecycle {
    create_before_destroy = true
  }
}

# Default SG. AWS attaches this to every ENI without an explicit SG, and it
# CAN'T be deleted. Best practice: adopt + strip its rules so nothing slips
# through accidentally.
#
# DESTRUCTIVE: turning manage_default_security_group on overwrites every
# rule, including ones added out-of-band. Don't do this lightly on shared
# VPCs.
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
