data "aws_caller_identity" "current" {
  count = var.create_kms_key && var.kms_key_policy == null ? 1 : 0
}

# Default CMK policy follows the AWS-recommended structure for keys used by EBS:
#   1. Full control to the account root (so IAM policies can delegate).
#   2. Optional key-usage grant to additional principals (e.g. the ECS instance
#      role or the Auto Scaling service-linked role that launches ECS capacity).
#   3. Optional CreateGrant for those principals, scoped to AWS resources, which
#      is what lets EBS/Auto Scaling attach encrypted volumes on their behalf.
data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key && var.kms_key_policy == null ? 1 : 0

  statement {
    sid       = "EnableRootAccount"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current[0].account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_additional_principals) > 0 ? [1] : []
    content {
      sid    = "AllowKeyUsage"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.kms_key_additional_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_key_additional_principals) > 0 ? [1] : []
    content {
      sid       = "AllowGrantsForAWSResources"
      effect    = "Allow"
      actions   = ["kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.kms_key_additional_principals
      }
      condition {
        test     = "Bool"
        variable = "kms:GrantIsForAWSResource"
        values   = ["true"]
      }
    }
  }
}

resource "aws_kms_key" "ebs" {
  count = var.create_kms_key ? 1 : 0

  description             = "CMK for EBS volumes managed by ${var.name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = var.kms_key_enable_rotation
  policy                  = var.kms_key_policy != null ? var.kms_key_policy : data.aws_iam_policy_document.kms[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-ebs"
    }
  )
}

resource "aws_kms_alias" "ebs" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/${var.name}-ebs"
  target_key_id = aws_kms_key.ebs[0].key_id
}
