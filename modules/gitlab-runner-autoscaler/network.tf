resource "aws_security_group" "manager" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-manager-"
  description = "GitLab runner managers: HTTPS out, SSH to the job instances"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-manager" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  count = local.create ? 1 : 0

  name_prefix = "${var.name}-instance-"
  description = "GitLab runner job instances: SSH from the managers, HTTPS out"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = "${var.name}-instance" })

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  security_group_ids = {
    manager  = one(aws_security_group.manager[*].id)
    instance = one(aws_security_group.instance[*].id)
  }
  https_cidr_rules = { for pair in setproduct(["manager", "instance"], var.egress_cidr_blocks) : "${pair[0]}-${pair[1]}" => {
    group = pair[0]
    cidr  = pair[1]
  } }
}

resource "aws_vpc_security_group_egress_rule" "https" {
  for_each = local.create ? local.https_cidr_rules : {}

  security_group_id = local.security_group_ids[each.value.group]
  description       = "HTTPS: VPC endpoints, GitLab, registries"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value.cidr
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "s3" {
  for_each = local.create ? toset(["manager", "instance"]) : toset([])

  security_group_id = local.security_group_ids[each.key]
  description       = "HTTPS to S3, where ECR serves image layers"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = local.s3_prefix_list_id
  tags              = local.tags
}

resource "aws_vpc_security_group_egress_rule" "manager_ssh" {
  count = local.create ? 1 : 0

  security_group_id            = local.security_group_ids.manager
  description                  = "SSH to the job instances"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = local.security_group_ids.instance
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "instance_ssh" {
  count = local.create ? 1 : 0

  security_group_id            = local.security_group_ids.instance
  description                  = "SSH from the runner managers"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = local.security_group_ids.manager
  tags                         = local.tags
}
