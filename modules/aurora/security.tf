# ============================================================================
# SECURITY GROUP
# ============================================================================

resource "aws_security_group" "aurora" {
  count       = var.create_security_group ? 1 : 0
  name_prefix = "${var.cluster_identifier}-"
  description = "Security group for Aurora cluster ${var.cluster_identifier}"
  vpc_id      = var.vpc_id

  tags = merge(
    local.common_tags,
    var.security_group_tags,
    {
      "Name" = local.security_group_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# INGRESS RULES - CIDR BLOCKS
# ============================================================================

resource "aws_vpc_security_group_ingress_rule" "from_cidr" {
  count = var.create_security_group && length(var.allowed_cidr_blocks) > 0 ? length(var.allowed_cidr_blocks) : 0

  security_group_id = aws_security_group.aurora[0].id
  from_port         = local.port
  to_port           = local.port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.allowed_cidr_blocks[count.index]
  description       = "Allow database access from ${var.allowed_cidr_blocks[count.index]}"

  tags = {
    "Name" = "${var.cluster_identifier}-from-cidr-${count.index}"
  }
}

# ============================================================================
# INGRESS RULES - SECURITY GROUPS
# ============================================================================

resource "aws_vpc_security_group_ingress_rule" "from_security_group" {
  count = var.create_security_group && length(var.allowed_security_groups) > 0 ? length(var.allowed_security_groups) : 0

  security_group_id            = aws_security_group.aurora[0].id
  from_port                    = local.port
  to_port                      = local.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = var.allowed_security_groups[count.index]
  description                  = "Allow database access from security group ${var.allowed_security_groups[count.index]}"

  tags = {
    "Name" = "${var.cluster_identifier}-from-sg-${count.index}"
  }
}

# ============================================================================
# EGRESS RULES
# ============================================================================

resource "aws_vpc_security_group_egress_rule" "allow_all" {
  count             = var.create_security_group ? 1 : 0
  security_group_id = aws_security_group.aurora[0].id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
  description       = "Allow all outbound traffic"

  tags = {
    "Name" = "${var.cluster_identifier}-allow-all-out"
  }
}
