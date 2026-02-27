# ─────────────────────────────────────────────────────────────────────────────
# irsa.tf – IRSA role instantiations (built-in + custom)
#
# Each block calls modules/irsa once.
# IAM policies are in irsa_policies.tf to keep this file about wiring only.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  irsa_common = {
    cluster_name      = local.name
    oidc_provider_arn = aws_iam_openid_connect_provider.this.arn
    oidc_provider_url = aws_iam_openid_connect_provider.this.url
    tags              = local.common_tags
  }
}

# ── AWS Load Balancer Controller ──────────────────────────────────────────────

module "irsa_aws_load_balancer_controller" {
  source = "./modules/irsa"
  count  = var.enable_irsa_aws_load_balancer_controller ? 1 : 0

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-aws-lb-controller"
  namespace         = "kube-system"
  service_account   = "aws-load-balancer-controller"
  policy_arns       = [aws_iam_policy.aws_load_balancer_controller[0].arn]
  tags              = local.irsa_common.tags
}

# ── Cluster Autoscaler ────────────────────────────────────────────────────────

module "irsa_cluster_autoscaler" {
  source = "./modules/irsa"
  count  = var.enable_irsa_cluster_autoscaler ? 1 : 0

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-cluster-autoscaler"
  namespace         = "kube-system"
  service_account   = "cluster-autoscaler"
  policy_arns       = [aws_iam_policy.cluster_autoscaler[0].arn]
  tags              = local.irsa_common.tags
}

# ── ExternalDNS ───────────────────────────────────────────────────────────────

module "irsa_external_dns" {
  source = "./modules/irsa"
  count  = var.enable_irsa_external_dns ? 1 : 0

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-external-dns"
  namespace         = "external-dns"
  service_account   = "external-dns"
  policy_arns       = [aws_iam_policy.external_dns[0].arn]
  tags              = local.irsa_common.tags
}

# ── EBS CSI Driver ────────────────────────────────────────────────────────────

module "irsa_ebs_csi_driver" {
  source = "./modules/irsa"
  count  = var.enable_irsa_ebs_csi_driver ? 1 : 0

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-ebs-csi-driver"
  namespace         = "kube-system"
  service_account   = "ebs-csi-controller-sa"
  policy_arns       = ["arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"]
  tags              = local.irsa_common.tags
}

# ── External Secrets Operator ─────────────────────────────────────────────────

module "irsa_external_secrets" {
  source = "./modules/irsa"
  count  = var.enable_irsa_external_secrets ? 1 : 0

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-external-secrets"
  namespace         = "external-secrets"
  service_account   = "external-secrets-sa"
  policy_arns       = [aws_iam_policy.external_secrets[0].arn]
  tags              = local.irsa_common.tags
}

# ── Custom IRSA roles (caller-defined) ────────────────────────────────────────

module "irsa_custom" {
  source   = "./modules/irsa"
  for_each = var.irsa_roles

  cluster_name      = local.irsa_common.cluster_name
  oidc_provider_arn = local.irsa_common.oidc_provider_arn
  oidc_provider_url = local.irsa_common.oidc_provider_url
  role_name         = "${local.name}-irsa-${each.key}"
  namespace         = each.value.namespace
  service_account   = each.value.service_account
  policy_arns       = each.value.policy_arns
  inline_policies   = each.value.inline_policies
  tags              = local.irsa_common.tags
}
