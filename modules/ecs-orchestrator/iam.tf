# execution role = how ECS pulls images, writes logs, reads secrets (the agent's
# identity). task role = what the app code runs as. keep them separate.

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# --- shared task execution role ---------------------------------------------

resource "aws_iam_role" "execution" {
  count = local.create_execution_role ? 1 : 0

  name_prefix          = substr("${var.cluster_name}-exec-", 0, 38)
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = var.iam_permissions_boundary

  tags = merge(local.common_tags, { "Name" = "${var.cluster_name}-execution" })
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  count = local.create_execution_role ? 1 : 0

  role       = aws_iam_role.execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "execution_extra" {
  for_each = local.create_execution_role ? var.task_execution_role_policies : {}

  role       = aws_iam_role.execution[0].name
  policy_arn = each.value
}

# Least-privilege read on exactly the referenced secret/parameter ARNs.
data "aws_iam_policy_document" "execution_secrets" {
  count = local.create_execution_role && length(local.all_secret_arns) > 0 ? 1 : 0

  statement {
    sid       = "ReadReferencedSecrets"
    actions   = ["secretsmanager:GetSecretValue", "ssm:GetParameters"]
    resources = local.all_secret_arns
  }

  # CMK-encrypted secrets/parameters also need Decrypt on the key.
  dynamic "statement" {
    for_each = length(var.secrets_kms_key_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptSecretKeys"
      actions   = ["kms:Decrypt"]
      resources = var.secrets_kms_key_arns
    }
  }
}

resource "aws_iam_role_policy" "execution_secrets" {
  count = local.create_execution_role && length(local.all_secret_arns) > 0 ? 1 : 0

  name   = "${var.cluster_name}-secrets-read"
  role   = aws_iam_role.execution[0].id
  policy = data.aws_iam_policy_document.execution_secrets[0].json
}

# --- per-service task roles --------------------------------------------------

locals {
  task_role_policy_attachments = merge([
    for sk, s in local.services_with_task_role : {
      for pk, arn in s.task_role_policies : "${sk}/${pk}" => { service = sk, arn = arn }
    }
  ]...)
}

resource "aws_iam_role" "task" {
  for_each = local.services_with_task_role

  name_prefix          = substr("${var.cluster_name}-${each.key}-", 0, 38)
  assume_role_policy   = data.aws_iam_policy_document.ecs_assume.json
  permissions_boundary = var.iam_permissions_boundary

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}-task" })
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = local.task_role_policy_attachments

  role       = aws_iam_role.task[each.value.service].name
  policy_arn = each.value.arn
}

resource "aws_iam_role_policy" "task_inline" {
  for_each = { for k, s in local.services_with_task_role : k => s if s.task_role_inline_policy != null }

  name   = "${var.cluster_name}-${each.key}-inline"
  role   = aws_iam_role.task[each.key].id
  policy = each.value.task_role_inline_policy
}

# ECS Exec needs the SSM messages channel on the TASK role. Without it,
# enable_execute_command is a no-op at runtime.
resource "aws_iam_role_policy" "task_exec" {
  for_each = { for k, s in local.services_with_task_role : k => s if s.enable_execute_command }

  name = "${var.cluster_name}-${each.key}-ecs-exec"
  role = aws_iam_role.task[each.key].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}
