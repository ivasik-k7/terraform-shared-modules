# per_service_execution_role:
#   true  (default) one role per service, sees only its own secrets
#   false           one shared role, sees every declared secret
#
# The aws:SourceArn condition on the assume-role policy blocks the confused
# deputy pattern flagged in AWS Trusted Advisor (the "ecs-tasks.amazonaws.com"
# principal would otherwise be globally assumable).
data "aws_iam_policy_document" "task_execution_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:ecs:${local.region}:${local.account_id}:*"]
    }
  }
}

# Shared execution role. Only exists when per_service_execution_role = false.
resource "aws_iam_role" "task_execution_shared" {
  count = var.per_service_execution_role ? 0 : 1

  name               = "${var.cluster_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  description        = "Shared ECS task execution role for cluster ${var.cluster_name}"

  tags = local.cluster_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_shared_managed" {
  count = var.per_service_execution_role ? 0 : 1

  role       = aws_iam_role.task_execution_shared[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Shared-role secrets policy. Union of every declared secret — acceptable
# blast radius only for small clusters (hence the opt-in).
data "aws_iam_policy_document" "task_execution_shared_secrets" {
  count = !var.per_service_execution_role && length(local.all_secret_refs) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = length(local.sm_arns) > 0 ? [1] : []
    content {
      sid    = "SecretsManagerAccess"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = local.sm_arns
    }
  }

  dynamic "statement" {
    for_each = length(local.ssm_paths) > 0 ? [1] : []
    content {
      sid    = "SSMParameterAccess"
      effect = "Allow"
      actions = [
        "ssm:GetParameters",
        "ssm:GetParameter",
        "ssm:GetParametersByPath",
      ]
      resources = [
        for path in local.ssm_paths :
        startswith(path, "arn:") ? path : "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${path}"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "KMSDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_shared_secrets" {
  count = !var.per_service_execution_role && length(local.all_secret_refs) > 0 ? 1 : 0

  name   = "secrets-access"
  role   = aws_iam_role.task_execution_shared[0].id
  policy = data.aws_iam_policy_document.task_execution_shared_secrets[0].json
}

# Per-service execution roles. Each one sees only that service's secrets.
resource "aws_iam_role" "task_execution_service" {
  for_each = var.per_service_execution_role ? local.services : {}

  name               = "${var.cluster_name}-${each.key}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  description        = "ECS task execution role for ${var.cluster_name}/${each.key}"

  tags = each.value.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_service_managed" {
  for_each = var.per_service_execution_role ? local.services : {}

  role       = aws_iam_role.task_execution_service[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_service_secrets" {
  for_each = var.per_service_execution_role ? {
    for k, refs in local.service_secret_refs : k => refs if length(refs) > 0
  } : {}

  dynamic "statement" {
    for_each = length(local.service_sm_arns[each.key]) > 0 ? [1] : []
    content {
      sid    = "SecretsManagerAccess"
      effect = "Allow"
      actions = [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret",
      ]
      resources = local.service_sm_arns[each.key]
    }
  }

  dynamic "statement" {
    for_each = length(local.service_ssm_paths[each.key]) > 0 ? [1] : []
    content {
      sid    = "SSMParameterAccess"
      effect = "Allow"
      actions = [
        "ssm:GetParameters",
        "ssm:GetParameter",
        "ssm:GetParametersByPath",
      ]
      resources = [
        for path in local.service_ssm_paths[each.key] :
        startswith(path, "arn:") ? path : "arn:${local.partition}:ssm:${local.region}:${local.account_id}:parameter${path}"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid       = "KMSDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}

resource "aws_iam_role_policy" "task_execution_service_secrets" {
  for_each = var.per_service_execution_role ? {
    for k, refs in local.service_secret_refs : k => refs if length(refs) > 0
  } : {}

  name   = "secrets-access"
  role   = aws_iam_role.task_execution_service[each.key].id
  policy = data.aws_iam_policy_document.task_execution_service_secrets[each.key].json
}

# Task role: identity the application runs under. Separate from execution
# role, which is only used by the ECS agent (pull images, write logs, fetch
# secrets) before the container starts.
resource "aws_iam_role" "task" {
  for_each = local.services

  name               = "${var.cluster_name}-${each.key}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  description        = "ECS task role for ${var.cluster_name}/${each.key}"

  tags = each.value.tags
}

# ECS Exec rides SSM Session Manager. These messages actions on the task
# role (not the execution role) are what enables `aws ecs execute-command`.
data "aws_iam_policy_document" "task_exec_permissions" {
  for_each = local.services_with_exec

  statement {
    sid    = "ECSExec"
    effect = "Allow"
    actions = [
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_exec_permissions" {
  for_each = local.services_with_exec

  name   = "ecs-exec"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.task_exec_permissions[each.key].json
}

# Per-service custom IAM (whatever the app actually needs).
data "aws_iam_policy_document" "task_custom" {
  for_each = { for k, v in local.services : k => v if length(v.task_role_statements) > 0 }

  dynamic "statement" {
    for_each = each.value.task_role_statements

    content {
      sid       = statement.value.sid != "" ? statement.value.sid : null
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      # condition shape is map<test, map<var, list<value>>> (mirrors IAM
      # JSON). One aws_iam_policy_document condition block per (test, var).
      dynamic "condition" {
        for_each = statement.value.condition == null ? [] : flatten([
          for test_name, vars in statement.value.condition : [
            for var_name, values in vars : {
              test     = test_name
              variable = var_name
              values   = values
            }
          ]
        ])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_iam_role_policy" "task_custom" {
  for_each = { for k, v in local.services : k => v if length(v.task_role_statements) > 0 }

  name   = "custom-permissions"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.task_custom[each.key].json
}
