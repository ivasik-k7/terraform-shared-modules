data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

resource "aws_secretsmanager_secret" "managed" {
  for_each = local.managed

  name                    = local.resolved[each.key].full_path
  description             = each.value.description
  kms_key_id              = local.resolved[each.key].kms_key_id
  recovery_window_in_days = local.resolved[each.key].recovery_window_in_days
  tags                    = local.resolved[each.key].tags

  dynamic "replica" {
    for_each = each.value.replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_id
    }
  }
}

resource "aws_secretsmanager_secret" "unmanaged" {
  for_each = local.unmanaged

  name                    = local.resolved[each.key].full_path
  description             = each.value.description
  kms_key_id              = local.resolved[each.key].kms_key_id
  recovery_window_in_days = local.resolved[each.key].recovery_window_in_days
  tags                    = local.resolved[each.key].tags

  dynamic "replica" {
    for_each = each.value.replica_regions
    content {
      region     = replica.value.region
      kms_key_id = replica.value.kms_key_id
    }
  }
}

resource "aws_secretsmanager_secret_version" "managed" {
  for_each = local.has_value_managed

  secret_id     = aws_secretsmanager_secret.managed[each.key].id
  secret_string = local.resolved[each.key].resolved_string
  secret_binary = local.resolved[each.key].resolved_string == null ? each.value.secret_binary : null
}

resource "aws_secretsmanager_secret_version" "unmanaged" {
  for_each = local.has_value_unmanaged

  secret_id     = aws_secretsmanager_secret.unmanaged[each.key].id
  secret_string = local.resolved[each.key].resolved_string
  secret_binary = local.resolved[each.key].resolved_string == null ? each.value.secret_binary : null

  lifecycle {
    ignore_changes = [secret_string, secret_binary]
  }
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.rotation_keys

  secret_id           = local.all_secret_resources[each.key].id
  rotation_lambda_arn = each.value.rotation.lambda_arn
  rotate_immediately  = each.value.rotation.rotate_immediately

  rotation_rules {
    automatically_after_days = each.value.rotation.automatically_after_days
  }
}

data "aws_iam_policy_document" "this" {
  for_each = local.policy_keys

  dynamic "statement" {
    for_each = length(var.reader_arns) > 0 ? ["enabled"] : []
    content {
      sid     = "ModuleWideReaders"
      effect  = "Allow"
      actions = local.reader_actions
      principals {
        type        = "AWS"
        identifiers = var.reader_arns
      }
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(var.manager_arns) > 0 ? ["enabled"] : []
    content {
      sid     = "ModuleWideManagers"
      effect  = "Allow"
      actions = local.manager_actions
      principals {
        type        = "AWS"
        identifiers = var.manager_arns
      }
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(try(each.value.policy.reader_arns, [])) > 0 ? ["enabled"] : []
    content {
      sid     = "SecretReaders"
      effect  = "Allow"
      actions = local.reader_actions
      principals {
        type        = "AWS"
        identifiers = each.value.policy.reader_arns
      }
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = length(try(each.value.policy.manager_arns, [])) > 0 ? ["enabled"] : []
    content {
      sid     = "SecretManagers"
      effect  = "Allow"
      actions = local.manager_actions
      principals {
        type        = "AWS"
        identifiers = each.value.policy.manager_arns
      }
      resources = ["*"]
    }
  }

  dynamic "statement" {
    for_each = try(each.value.policy.additional_statements, [])
    content {
      sid           = try(statement.value.sid, null)
      effect        = try(statement.value.effect, "Allow")
      actions       = try(statement.value.actions, null)
      not_actions   = try(statement.value.not_actions, null)
      resources     = try(statement.value.resources, ["*"])
      not_resources = try(statement.value.not_resources, null)
      dynamic "principals" {
        for_each = try(statement.value.principals, [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }
      dynamic "condition" {
        for_each = try(statement.value.conditions, [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_secretsmanager_secret_policy" "this" {
  for_each = local.policy_keys

  secret_arn          = local.all_secret_resources[each.key].arn
  policy              = data.aws_iam_policy_document.this[each.key].json
  block_public_policy = true
}
