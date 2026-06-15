locals {
  create_dlm_role = var.create_lifecycle_policy && var.create_dlm_role
  dlm_role_arn = var.create_lifecycle_policy ? (
    var.create_dlm_role ? aws_iam_role.dlm[0].arn : var.dlm_role_arn
  ) : null
}

data "aws_iam_policy_document" "dlm_assume_role" {
  count = local.create_dlm_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "dlm_permissions" {
  count = local.create_dlm_role ? 1 : 0

  statement {
    sid    = "ManageSnapshots"
    effect = "Allow"
    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateSnapshots",
      "ec2:DeleteSnapshot",
      "ec2:DescribeVolumes",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots"
    ]
    resources = ["*"]
  }

  statement {
    sid       = "TagSnapshots"
    effect    = "Allow"
    actions   = ["ec2:CreateTags", "ec2:DeleteTags"]
    resources = ["arn:aws:ec2:*::snapshot/*"]
  }

  # Required so DLM can snapshot/copy ENCRYPTED volumes — including volumes
  # encrypted with the customer-managed CMK this module can create, and the
  # default aws/ebs key. Mirrors the AWS-managed AWSDataLifecycleManagerServiceRole.
  statement {
    sid    = "KmsKeyUsage"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "KmsCreateGrant"
    effect    = "Allow"
    actions   = ["kms:CreateGrant"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = ["true"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  count = local.create_dlm_role ? 1 : 0

  name_prefix        = "${var.name}-dlm-"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role[0].json

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-dlm"
    }
  )
}

resource "aws_iam_role_policy" "dlm" {
  count = local.create_dlm_role ? 1 : 0

  name_prefix = "${var.name}-dlm-"
  role        = aws_iam_role.dlm[0].id
  policy      = data.aws_iam_policy_document.dlm_permissions[0].json
}

resource "aws_dlm_lifecycle_policy" "this" {
  count = var.create_lifecycle_policy ? 1 : 0

  description        = local.lifecycle_policy_description
  execution_role_arn = local.dlm_role_arn
  state              = var.lifecycle_policy_state

  policy_details {
    resource_types = ["VOLUME"]

    target_tags = {
      (local.dlm_target_tag_key) = local.dlm_target_tag_value
    }

    dynamic "schedule" {
      for_each = var.snapshot_schedules
      content {
        name = schedule.key

        create_rule {
          interval      = schedule.value.interval
          interval_unit = schedule.value.interval_unit
          times         = schedule.value.times
        }

        retain_rule {
          count = schedule.value.retain_count
        }

        copy_tags = schedule.value.copy_tags

        tags_to_add = merge(
          {
            SnapshotCreator = "DLM"
            Schedule        = schedule.key
          },
          schedule.value.tags_to_add
        )

        dynamic "cross_region_copy_rule" {
          for_each = schedule.value.cross_region_copy
          content {
            target    = cross_region_copy_rule.value.target
            encrypted = cross_region_copy_rule.value.encrypted
            cmk_arn   = cross_region_copy_rule.value.cmk_arn

            retain_rule {
              interval      = cross_region_copy_rule.value.retain_count
              interval_unit = "DAYS"
            }
          }
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-dlm"
    }
  )

  lifecycle {
    precondition {
      condition     = local.dlm_role_arn != null
      error_message = "create_lifecycle_policy is true but no DLM role is available. Set create_dlm_role = true (default) or provide dlm_role_arn."
    }
    precondition {
      condition     = length(var.snapshot_schedules) >= 1 && length(var.snapshot_schedules) <= 4
      error_message = "A DLM lifecycle policy requires between 1 and 4 snapshot_schedules (got ${length(var.snapshot_schedules)})."
    }
  }
}
