# ─────────────────────────────────────────────────────────────────────────────
# locals.tf
# Single source of truth for every computed value used across files.
# Having one locals block prevents shadowing and makes grep trivial.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  name = var.cluster_name

  # ── Tagging ────────────────────────────────────────────────────────────────
  common_tags = merge(
    {
      "terraform-module" = "terraform-aws-eks"
      "cluster-name"     = local.name
      "environment"      = var.environment
    },
    var.tags,
  )

  # ── Networking ─────────────────────────────────────────────────────────────
  # Control-plane subnets fall back to worker subnets when not explicitly set
  control_plane_subnet_ids = (
    length(var.control_plane_subnet_ids) > 0
    ? var.control_plane_subnet_ids
    : var.subnet_ids
  )

  # ── Encryption ─────────────────────────────────────────────────────────────
  # Effective KMS key ARN: created or pre-existing
  kms_key_arn = var.create_kms_key ? aws_kms_key.secrets[0].arn : var.kms_key_arn

  # ── aws-auth / Access Entries ──────────────────────────────────────────────
  # Collect IAM role ARNs from every node group for aws-auth injection
  node_role_arns = [
    for k, v in module.node_group : v.node_group_role_arn
  ]

  aws_auth_roles_combined = concat(
    [
      for arn in local.node_role_arns : {
        rolearn  = arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups   = ["system:bootstrappers", "system:nodes"]
      }
    ],
    var.aws_auth_roles,
  )
}
