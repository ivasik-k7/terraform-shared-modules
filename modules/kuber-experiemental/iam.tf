# ─────────────────────────────────────────────────────────────────────────────
# iam.tf – EKS control-plane IAM role
# Node group roles live in modules/node_group.
# IRSA roles live in irsa.tf + irsa_policies.tf.
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    sid     = "EKSAssumeRole"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.name}-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  description        = "EKS control-plane role for cluster ${local.name}"
  tags               = merge(local.common_tags, { Name = "${local.name}-cluster-role" })
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSVPCResourceController"
}
