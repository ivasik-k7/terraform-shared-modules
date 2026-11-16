# ---------------------------------------------------------------------------
# Task roles: what the application may do. One per workload.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "task" {
  for_each = local.task_roles_created

  name                 = local.task_role_name[each.key]
  description          = "Task role for ${each.key} on ECS cluster ${var.name}."
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  # ECS does not support a cluster-specific aws:SourceArn here; the account
  # wildcard is the documented form.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:*" }
        StringEquals = { "aws:SourceAccount" = local.account_id }
      }
    }]
  })

  tags = local.workload_tags[each.key]
}

resource "aws_iam_role_policy" "task_module" {
  for_each = local.task_module_policy

  name   = "ecs-module"
  role   = aws_iam_role.task[each.key].id
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[${join(",", local.task_module_statements[each.key])}]}"
}

resource "aws_iam_role_policy" "task_custom" {
  for_each = merge([
    for k, s in local.task_roles_created : { for n, doc in s.task_role.policies : "${k}/${n}" => { service = k, name = n, policy = doc } }
  ]...)

  name   = each.value.name
  role   = aws_iam_role.task[each.value.service].id
  policy = each.value.policy
}

resource "aws_iam_role_policy_attachment" "task_managed" {
  for_each = merge([
    for k, s in local.task_roles_created : { for n, arn in s.task_role.managed_policies : "${k}/${n}" => { service = k, arn = arn } }
  ]...)

  role       = aws_iam_role.task[each.value.service].name
  policy_arn = each.value.arn
}

# ---------------------------------------------------------------------------
# Execution roles: what ECS needs to start the task (pull, logs, secrets).
# One per workload, so a workload can read only its own secrets.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "execution" {
  for_each = local.execution_roles_created

  name                 = local.execution_role_name[each.key]
  description          = "Task execution role for ${each.key} on ECS cluster ${var.name}."
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.workload_tags[each.key]
}

resource "aws_iam_role_policy_attachment" "execution" {
  for_each = local.execution_roles_created

  role       = aws_iam_role.execution[each.key].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "execution_module" {
  for_each = local.execution_module_policy

  name   = "ecs-module"
  role   = aws_iam_role.execution[each.key].id
  policy = "{\"Version\":\"2012-10-17\",\"Statement\":[${join(",", local.execution_module_statements[each.key])}]}"
}

resource "aws_iam_role_policy_attachment" "execution_managed" {
  for_each = merge([
    for k, s in local.execution_roles_created : { for n, arn in s.execution_role.managed_policies : "${k}/${n}" => { service = k, arn = arn } }
  ]...)

  role       = aws_iam_role.execution[each.value.service].name
  policy_arn = each.value.arn
}

# ---------------------------------------------------------------------------
# Infrastructure role: ECS creates and attaches managed EBS volumes with it.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/infrastructure_IAM_role.html
# ---------------------------------------------------------------------------

resource "aws_iam_role" "infrastructure" {
  count = local.create_infra_role ? 1 : 0

  name                 = "${var.name}-ecs-infrastructure"
  description          = "ECS infrastructure role for managed EBS volumes on cluster ${var.name}."
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  count = local.create_infra_role ? 1 : 0

  role       = aws_iam_role.infrastructure[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"
}

# ---------------------------------------------------------------------------
# Scheduler role: EventBridge Scheduler runs scheduled workloads with it.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "scheduler" {
  count = length(local.scheduled) > 0 ? 1 : 0

  name                 = "${var.name}-scheduler"
  description          = "EventBridge Scheduler role that runs scheduled tasks on ECS cluster ${var.name}."
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  # Scoped to the module's schedule group, the narrowest SourceArn Scheduler supports.
  # https://docs.aws.amazon.com/scheduler/latest/UserGuide/cross-service-confused-deputy-prevention.html
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = {
          "aws:SourceAccount" = local.account_id
          "aws:SourceArn"     = local.schedule_group_arn
        }
      }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = length(local.scheduled) > 0 ? 1 : 0

  name = "run-scheduled-tasks"
  role = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "RunScheduledTasks"
        Effect    = "Allow"
        Action    = ["ecs:RunTask"]
        Resource  = [for k, s in local.scheduled : "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.name}-${k}:*"]
        Condition = { ArnEquals = { "ecs:cluster" = local.cluster_arn } }
      },
      {
        Sid       = "PassTaskRoles"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = distinct(concat([for k, s in local.scheduled : local.task_role_arn[k]], [for k, s in local.scheduled : local.execution_role_arn[k]]))
        Condition = { StringLike = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
      {
        Sid       = "TagScheduledTasks"
        Effect    = "Allow"
        Action    = ["ecs:TagResource"]
        Resource  = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${var.name}/*"
        Condition = { StringEquals = { "ecs:CreateAction" = ["RunTask"] } }
      },
      ],
      # Without it a failed invocation is denied at the DLQ too, and lost.
      # https://docs.aws.amazon.com/scheduler/latest/UserGuide/configuring-schedule-dlq.html
      length(local.dead_letter_queues) == 0 ? [] : [{
        Sid      = "DeliverToDeadLetterQueues"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = local.dead_letter_queues
      }],
      length(local.dead_letter_keys) == 0 ? [] : [{
        Sid       = "EncryptDeadLetters"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = local.dead_letter_keys
        Condition = { StringEquals = { "kms:ViaService" = "sqs.${local.region}.amazonaws.com" } }
      }],
    )
  })
}
