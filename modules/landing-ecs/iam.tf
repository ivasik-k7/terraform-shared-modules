# One execution role shared by every service in the cluster. Used by the ECS
# agent to pull images, ship logs, and resolve secrets at task launch.
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

resource "aws_iam_role" "task_execution" {
  name               = "${var.cluster_name}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  description        = "ECS task execution role for cluster ${var.cluster_name}"

  tags = local.cluster_tags
}

resource "aws_iam_role_policy_attachment" "task_execution_managed" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Secrets Manager / SSM access for the execution role. Needed so the agent
# can hydrate `secrets` env vars before the container starts.
data "aws_iam_policy_document" "task_execution_secrets" {
  count = length(local.all_secret_refs) > 0 ? 1 : 0

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
      # IAM needs full ARNs; accept either bare path or pre-built ARN.
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

resource "aws_iam_role_policy" "task_execution_secrets" {
  count = length(local.all_secret_refs) > 0 ? 1 : 0

  name   = "secrets-access"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_secrets[0].json
}

# One task role per service. This is the identity the application code runs as.
resource "aws_iam_role" "task" {
  for_each = local.services

  name               = "${var.cluster_name}-${each.key}-task-role"
  assume_role_policy = data.aws_iam_policy_document.task_execution_assume.json
  description        = "ECS task role for ${var.cluster_name}/${each.key}"

  tags = each.value.tags
}

# ECS Exec opens an SSM Session Manager channel into the container.
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

# X-Ray write permissions
data "aws_iam_policy_document" "task_xray" {
  for_each = local.services_with_xray

  statement {
    sid    = "XRayWrite"
    effect = "Allow"
    actions = [
      "xray:PutTraceSegments",
      "xray:PutTelemetryRecords",
      "xray:GetSamplingRules",
      "xray:GetSamplingTargets",
      "xray:GetSamplingStatisticSummaries",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "task_xray" {
  for_each = local.services_with_xray

  name   = "xray-write"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.task_xray[each.key].json
}

# Per-service custom IAM statements
data "aws_iam_policy_document" "task_custom" {
  for_each = { for k, v in local.services : k => v if length(v.task_role_statements) > 0 }

  dynamic "statement" {
    for_each = each.value.task_role_statements

    content {
      sid       = statement.value.sid != "" ? statement.value.sid : null
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }
}

resource "aws_iam_role_policy" "task_custom" {
  for_each = { for k, v in local.services : k => v if length(v.task_role_statements) > 0 }

  name   = "custom-permissions"
  role   = aws_iam_role.task[each.key].id
  policy = data.aws_iam_policy_document.task_custom[each.key].json
}
