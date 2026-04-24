# Services with run_schedule set keep desired_count = 0. EventBridge calls
# RunTask against the task definition on the cadence. Works because the
# validation rule on enable_autoscaling prevents mixing with App Autoscaling.
data "aws_iam_policy_document" "eventbridge_assume" {
  count = length(local.services_scheduled_run) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eventbridge_ecs" {
  count = length(local.services_scheduled_run) > 0 ? 1 : 0

  name               = "${var.cluster_name}-eventbridge-ecs"
  description        = "Allows EventBridge to launch scheduled ECS tasks in ${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.eventbridge_assume[0].json

  tags = local.cluster_tags
}

resource "aws_iam_role_policy_attachment" "eventbridge_ecs" {
  count = length(local.services_scheduled_run) > 0 ? 1 : 0

  role       = aws_iam_role.eventbridge_ecs[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonEC2ContainerServiceEventsRole"
}

# iam:PassRole on both the execution + task roles; RunTask fails at start
# otherwise. Shape depends on per_service_execution_role.
data "aws_iam_policy_document" "eventbridge_passrole" {
  count = length(local.services_scheduled_run) > 0 ? 1 : 0

  statement {
    sid     = "PassTaskRoles"
    effect  = "Allow"
    actions = ["iam:PassRole"]
    resources = concat(
      var.per_service_execution_role
      ? [for k in keys(local.services_scheduled_run) : aws_iam_role.task_execution_service[k].arn]
      : [aws_iam_role.task_execution_shared[0].arn],
      [for k in keys(local.services_scheduled_run) : aws_iam_role.task[k].arn],
    )
  }
}

resource "aws_iam_role_policy" "eventbridge_passrole" {
  count = length(local.services_scheduled_run) > 0 ? 1 : 0

  name   = "pass-task-roles"
  role   = aws_iam_role.eventbridge_ecs[0].id
  policy = data.aws_iam_policy_document.eventbridge_passrole[0].json
}

resource "aws_cloudwatch_event_rule" "scheduled_task" {
  for_each = local.services_scheduled_run

  name                = "${var.cluster_name}-${each.key}-schedule"
  description         = "Scheduled ECS task for ${var.cluster_name}/${each.key}"
  schedule_expression = each.value.run_schedule

  tags = each.value.tags
}

resource "aws_cloudwatch_event_target" "scheduled_task" {
  for_each = local.services_scheduled_run

  rule      = aws_cloudwatch_event_rule.scheduled_task[each.key].name
  target_id = "${var.cluster_name}-${each.key}"
  arn       = aws_ecs_cluster.this.arn
  role_arn  = aws_iam_role.eventbridge_ecs[0].arn

  ecs_target {
    task_definition_arn = aws_ecs_task_definition.this[each.key].arn
    task_count          = 1
    launch_type         = "FARGATE"
    platform_version    = "LATEST"

    network_configuration {
      subnets = each.value.subnets
      security_groups = concat(
        each.value.security_groups,
        each.value.create_security_group ? [aws_security_group.service[each.key].id] : []
      )
      assign_public_ip = each.value.assign_public_ip
    }
  }
}
