# ─────────────────────────────────────────────────────────────────────────────
# IRSA – IAM Role for Service Accounts
#
# Creates an IAM role whose trust policy allows Kubernetes ServiceAccount(s) to
# assume it via the cluster's OIDC provider (no long-lived credentials).
# ─────────────────────────────────────────────────────────────────────────────

locals {
  oidc_url_stripped = replace(var.oidc_provider_url, "https://", "")

  # ── Merge legacy single-SA vars with the list-based service_accounts var ────
  # If the caller only sets namespace + service_account (original API) we
  # synthesise a one-element list so the rest of the logic is uniform.
  legacy_sa = (var.namespace != null && var.service_account != null) ? [{
    namespace       = var.namespace
    service_account = var.service_account
  }] : []

  all_service_accounts = distinct(concat(local.legacy_sa, var.service_accounts))

  oidc_subjects = [
    for sa in local.all_service_accounts :
    "system:serviceaccount:${sa.namespace}:${sa.service_account}"
  ]

  oidc_condition_test = var.use_wildcard_subject ? "StringLike" : "StringEquals"

  role_name_computed = var.role_name != null ? var.role_name : null

  role_description = coalesce(
    var.role_description,
    "IRSA role for cluster '${var.cluster_name}' – subjects: ${join(", ", local.oidc_subjects)}"
  )

  extra_trust_json = length(var.additional_trust_statements) > 0 ? jsonencode({
    Version   = "2012-10-17"
    Statement = [for s in var.additional_trust_statements : jsondecode(s)]
  }) : null

  effective_tags = merge(
    {
      "irsa:cluster"       = var.cluster_name
      "irsa:oidc-provider" = local.oidc_url_stripped
    },
    var.tags,
  )
}

data "aws_iam_policy_document" "assume_role" {
  count = var.create_role ? 1 : 0

  statement {
    sid     = "OIDCAssumeRoleWithWebIdentity"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_url_stripped}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = local.oidc_condition_test
      variable = "${local.oidc_url_stripped}:sub"
      values   = local.oidc_subjects
    }
  }
}

data "aws_iam_policy_document" "trust_combined" {
  count = var.create_role ? 1 : 0

  source_policy_documents = compact([
    data.aws_iam_policy_document.assume_role[0].json,
    local.extra_trust_json,
  ])
}

resource "aws_iam_role" "this" {
  count = var.create_role ? 1 : 0

  name        = local.role_name_computed
  name_prefix = local.role_name_computed == null ? var.role_name_prefix : null

  path                  = var.role_path
  description           = local.role_description
  assume_role_policy    = data.aws_iam_policy_document.trust_combined[0].json
  permissions_boundary  = var.role_permissions_boundary_arn
  max_session_duration  = var.max_session_duration
  force_detach_policies = var.force_detach_policies

  tags = local.effective_tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.create_role ? toset(var.policy_arns) : toset([])

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.create_role ? var.inline_policies : {}

  name   = each.key
  role   = aws_iam_role.this[0].id
  policy = each.value
}
