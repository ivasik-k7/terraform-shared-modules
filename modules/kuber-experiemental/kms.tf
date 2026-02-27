# ─────────────────────────────────────────────────────────────────────────────
# kms.tf – Dedicated KMS key for Kubernetes secrets encryption
# ─────────────────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key ? 1 : 0

  # Root account retains full key administration rights
  statement {
    sid     = "EnableRootAdministration"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  statement {
    sid = "AllowEKSControlPlane"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "secrets" {
  count                   = var.create_kms_key ? 1 : 0
  description             = "EKS secrets encryption – cluster: ${local.name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = merge(local.common_tags, { Name = "${local.name}-secrets" })
}

resource "aws_kms_alias" "secrets" {
  count         = var.create_kms_key ? 1 : 0
  name          = "alias/${local.name}-secrets"
  target_key_id = aws_kms_key.secrets[0].key_id
}
