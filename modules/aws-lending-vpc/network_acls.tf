# The default NACL on every VPC allows all traffic in and out. To lock it
# down (regulated environments often require this) opt in via
# manage_default_network_acl and pass your rule sets.
#
# DESTRUCTIVE: this resource REPLACES the default rules. If you set both
# rule lists empty, every subnet associated with the default NACL becomes
# unreachable. The check{} block doesn't catch this on purpose — sometimes
# "deny everything" is exactly what you want, just be intentional.
#
# Subnet-specific NACLs are out of scope for this module; use a separate
# aws_network_acl resource if you need them.
resource "aws_default_network_acl" "this" {
  count = var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = local.should_create_vpc ? aws_vpc.this[0].default_network_acl_id : data.aws_network_acls.default[0].ids[0]

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      rule_no    = ingress.value.rule_no
      action     = ingress.value.action
      protocol   = ingress.value.protocol
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
      cidr_block = ingress.value.cidr_block
    }
  }

  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      rule_no    = egress.value.rule_no
      action     = egress.value.action
      protocol   = egress.value.protocol
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
      cidr_block = egress.value.cidr_block
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-default-nacl"
  })
}
