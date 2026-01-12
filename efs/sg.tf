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

resource "aws_security_group_rule" "efs_ingress_cidr" {
  count = var.create_security_group && length(var.allowed_cidr_blocks) > 0 ? 1 : 0

  type              = "ingress"
  from_port         = 2049
  to_port           = 2049
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.efs[0].id
  description       = "Allow NFS traffic from specified CIDR blocks"
}

resource "aws_security_group_rule" "efs_ingress_sg" {
  for_each = var.create_security_group ? toset(var.allowed_security_group_ids) : []

  type                     = "ingress"
  from_port                = 2049
  to_port                  = 2049
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.efs[0].id
  description              = "Allow NFS traffic from security group ${each.value}"
}

resource "aws_security_group_rule" "efs_egress" {
  count = var.create_security_group ? 1 : 0

  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.efs[0].id
  description       = "Allow all outbound traffic"
}
