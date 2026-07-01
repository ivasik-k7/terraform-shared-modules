# optional per-service security group (awsvpc). egress-only by default; ingress
# usually comes from the load balancer's SG, so callers add rules out of band or
# pass shared security_groups instead.

resource "aws_security_group" "service" {
  for_each = local.services_with_sg

  name_prefix = "${var.cluster_name}-${each.key}-"
  description = "ECS service ${each.key} in ${var.cluster_name}"
  vpc_id      = var.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}" })

  lifecycle {
    create_before_destroy = true
  }
}
