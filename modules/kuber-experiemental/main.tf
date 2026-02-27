# ─────────────────────────────────────────────────────────────────────────────
# main.tf – EKS Cluster + OIDC provider
#
# Deliberately thin. Everything else (KMS, IAM, SGs, node groups, IRSA, auth)
# lives in its own focused file so diffs stay readable.
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_eks_cluster" "this" {
  name     = local.name
  role_arn = aws_iam_role.cluster.arn
  version  = var.cluster_version

  vpc_config {
    subnet_ids              = local.control_plane_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_public_access  = var.cluster_endpoint_public_access
    endpoint_private_access = var.cluster_endpoint_private_access
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  dynamic "encryption_config" {
    for_each = local.kms_key_arn != null ? [1] : []
    content {
      resources = ["secrets"]
      provider {
        key_arn = local.kms_key_arn
      }
    }
  }

  access_config {
    authentication_mode                         = var.auth_mode
    bootstrap_cluster_creator_admin_permissions = false
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
    aws_cloudwatch_log_group.eks,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# OIDC Provider – required for IRSA
#
# AWS provider ≥ 5.7: thumbprint_list is auto-managed for EKS issuers.
# The data "tls_certificate" lookup is no longer needed and has been removed.
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_openid_connect_provider" "this" {
  url            = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list = ["sts.amazonaws.com"]

  # AWS manages the EKS OIDC thumbprint automatically (provider ≥ 5.7).
  # Passing an explicit thumbprint is still accepted but unnecessary and will
  # silently drift when AWS rotates the certificate.
  thumbprint_list = []

  tags = merge(local.common_tags, { Name = "${local.name}-oidc-provider" })
}
