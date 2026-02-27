# ─────────────────────────────────────────────────────────────────────────────
# security_groups.tf
#
# Uses aws_vpc_security_group_ingress_rule / aws_vpc_security_group_egress_rule
# instead of the legacy aws_security_group_rule resource.
#
# Why: the new resources are individual API objects — no in-place updates that
# cause dependency cycles, and no "already exists" errors on parallel applies.
# ─────────────────────────────────────────────────────────────────────────────

# ── Control-plane SG ──────────────────────────────────────────────────────────

resource "aws_security_group" "cluster" {
  name        = "${local.name}-cluster-sg"
  description = "EKS control-plane – managed by Terraform"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${local.name}-cluster-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes_443" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.node.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow node groups to reach the Kubernetes API server"
  tags                         = merge(local.common_tags, { Name = "cluster-from-nodes-443" })
}

resource "aws_vpc_security_group_egress_rule" "cluster_egress_all" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic from the control plane"
  tags              = merge(local.common_tags, { Name = "cluster-egress-all" })
}

# ── Worker-node SG ────────────────────────────────────────────────────────────

resource "aws_security_group" "node" {
  name        = "${local.name}-node-sg"
  description = "EKS worker nodes – managed by Terraform"
  vpc_id      = var.vpc_id
  tags = merge(
    local.common_tags,
    {
      Name                                  = "${local.name}-node-sg"
      "kubernetes.io/cluster/${local.name}" = "owned"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "node_ingress_self" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "Allow unrestricted traffic between nodes (pod networking)"
  tags                         = merge(local.common_tags, { Name = "node-ingress-self" })
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_ephemeral" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 1025
  to_port                      = 65535
  ip_protocol                  = "tcp"
  description                  = "Allow control plane to reach node high-ports (kubelet, etc.)"
  tags                         = merge(local.common_tags, { Name = "node-from-cluster-ephemeral" })
}

resource "aws_vpc_security_group_ingress_rule" "node_from_cluster_443" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.cluster.id
  from_port                    = 443
  to_port                      = 443
  ip_protocol                  = "tcp"
  description                  = "Allow control plane to call admission webhooks on nodes"
  tags                         = merge(local.common_tags, { Name = "node-from-cluster-443" })
}

resource "aws_vpc_security_group_egress_rule" "node_egress_all" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all outbound traffic from nodes"
  tags              = merge(local.common_tags, { Name = "node-egress-all" })
}
