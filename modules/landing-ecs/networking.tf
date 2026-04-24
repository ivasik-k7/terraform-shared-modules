# Empty SG per service — ingress rules are the caller's concern, added
# with aws_vpc_security_group_ingress_rule outside the module.
resource "aws_security_group" "service" {
  for_each = local.services_with_sg

  name        = "${var.cluster_name}-${each.key}-sg"
  description = "ECS service ${each.key} in cluster ${var.cluster_name}"
  vpc_id      = var.vpc_id

  tags = merge(each.value.tags, { Name = "${var.cluster_name}-${each.key}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# Fargate tasks need egress for ECR pulls, Secrets Manager, SSM, CW Logs.
# Narrow via VPC endpoints + a restrictive egress list if you need to.
resource "aws_vpc_security_group_egress_rule" "service_all" {
  for_each = local.services_with_sg

  security_group_id = aws_security_group.service[each.key].id
  description       = "Allow all outbound (ECR pull, SM, SSM, external APIs)"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = { Name = "${var.cluster_name}-${each.key}-egress-all" }
}
