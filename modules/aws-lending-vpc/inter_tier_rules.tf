# =============================================================================
# Inter-tier security group rules
# =============================================================================
# Migration-factory shortcut. Most VPCs end up with the same boilerplate:
#   - "app" SG can reach "db" SG on 5432
#   - "ingress" SG can reach "app" SG on 8080
#   - "bastion" SG can reach "app" SG on 22
#
# Writing those out as full SG rule objects is tedious. var.inter_tier_rules
# expresses the intent declaratively against SGs created by the module:
#
#   inter_tier_rules = [
#     { from = "app", to = "db",  from_port = 5432, to_port = 5432 },
#     { from = "alb", to = "app", from_port = 8080, to_port = 8080 },
#   ]
#
# Each entry creates an ingress rule on the 'to' SG that allows traffic
# from the 'from' SG. Egress rules: don't add them here — egress is allowed
# by default in AWS SGs and over-constraining it tends to bite later.
resource "aws_vpc_security_group_ingress_rule" "inter_tier" {
  for_each = {
    for r in var.inter_tier_rules :
    "${r.from}->${r.to}:${r.protocol}:${r.from_port}-${r.to_port}" => r
  }

  security_group_id            = aws_security_group.custom[each.value.to].id
  referenced_security_group_id = aws_security_group.custom[each.value.from].id
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  description                  = coalesce(each.value.description, "${each.value.from} -> ${each.value.to} ${each.value.protocol}/${each.value.from_port}-${each.value.to_port}")

  tags = merge(local.base_tags, {
    Name = "${var.name}-${each.value.from}-to-${each.value.to}"
  })
}
