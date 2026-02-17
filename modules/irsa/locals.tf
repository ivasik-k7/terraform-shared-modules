locals {
  oidc_provider_arn = var.oidc_provider_arn != null ? var.oidc_provider_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(var.cluster_oidc_issuer_url, "https://", "")}"

  oidc_provider_url = var.oidc_provider_url != null ? var.oidc_provider_url : replace(var.cluster_oidc_issuer_url, "https://", "")

  role_name = var.role_name != null ? var.role_name : "${var.cluster_name}-${var.service_account_name}-irsa"

  service_accounts = var.service_account_namespace != null ? [
    "system:serviceaccount:${var.service_account_namespace}:${var.service_account_name}"
    ] : var.service_account_namespaces != null ? [
    for ns in var.service_account_namespaces : "system:serviceaccount:${ns}:${var.service_account_name}"
  ] : []

  tags = merge(
    {
      "terraform.module"           = "eks-irsa"
      "kubernetes.cluster"         = var.cluster_name
      "kubernetes.service-account" = var.service_account_name
    },
    var.tags
  )

  policy_arns = concat(
    var.policy_arns,
    var.attach_ebs_csi_policy ? ["arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"] : [],
    var.attach_efs_csi_policy ? ["arn:aws:iam::aws:policy/service-role/AmazonEFSCSIDriverPolicy"] : [],
    var.attach_vpc_cni_policy ? ["arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"] : [],
    var.attach_cluster_autoscaler_policy ? [aws_iam_policy.cluster_autoscaler[0].arn] : [],
    var.attach_alb_controller_policy ? [aws_iam_policy.alb_controller[0].arn] : [],
    var.attach_external_dns_policy ? [aws_iam_policy.external_dns[0].arn] : [],
    var.attach_cert_manager_policy ? [aws_iam_policy.cert_manager[0].arn] : [],
    var.attach_external_secrets_policy ? [aws_iam_policy.external_secrets[0].arn] : [],
  )

  has_custom_policy = var.policy_statements != null && length(var.policy_statements) > 0
}
