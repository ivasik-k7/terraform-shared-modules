resource "aws_security_group" "efs" {
  count = var.create_security_group ? 1 : 0

  name_prefix = "${var.name}-efs-"
  description = "Security group for EFS ${var.name}"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-efs"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# INGRESS RULES - IPv4 CIDR BLOCKS
# ============================================================================

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count = var.create_security_group ? length(var.allowed_cidr_blocks) : 0

  security_group_id = aws_security_group.efs[0].id
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  description       = "Allow NFS traffic from ${var.allowed_cidr_blocks[count.index]}"

  tags = merge(var.tags, { Name = "${var.name}-efs-from-cidr-${count.index}" })
}

# ============================================================================
# INGRESS RULES - IPv6 CIDR BLOCKS
# ============================================================================

resource "aws_vpc_security_group_ingress_rule" "from_ipv6_cidr" {
  count = var.create_security_group ? length(var.allowed_ipv6_cidr_blocks) : 0

  security_group_id = aws_security_group.efs[0].id
  from_port         = 2049
  to_port           = 2049
  ip_protocol       = "tcp"
  cidr_ipv6         = var.allowed_ipv6_cidr_blocks[count.index]
  description       = "Allow NFS traffic from ${var.allowed_ipv6_cidr_blocks[count.index]}"

  tags = merge(var.tags, { Name = "${var.name}-efs-from-ipv6-cidr-${count.index}" })
}

# ============================================================================
# INGRESS RULES - SECURITY GROUPS
# ============================================================================

resource "aws_vpc_security_group_ingress_rule" "from_security_group" {
  count = var.create_security_group ? length(var.allowed_security_group_ids) : 0

  security_group_id            = aws_security_group.efs[0].id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  description                  = "Allow NFS traffic from security group ${var.allowed_security_group_ids[count.index]}"

  tags = merge(var.tags, { Name = "${var.name}-efs-from-sg-${count.index}" })
}

# ============================================================================
# EGRESS RULE
# ============================================================================

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  count = var.create_security_group ? 1 : 0

  security_group_id = aws_security_group.efs[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all outbound traffic"

  tags = merge(var.tags, { Name = "${var.name}-efs-allow-all-out" })
}
