locals {
  schedules = local.regional ? var.schedules : {}

  ec2_runs = merge([for k, s in local.schedules : {
    for action in ["stop", "start"] : "${k}-ec2-${action}" => {
      schedule = k
      action   = action
      what     = "EC2 instances tagged ${s.tag_key} = ${join(" or ", s.tag_values)}"
      cron     = action == "stop" ? s.stop : s.start
      timezone = s.timezone
      input = {
        DocumentName        = action == "stop" ? "AWS-StopEC2Instance" : "AWS-StartEC2Instance"
        TargetParameterName = "InstanceId"
        Targets             = [{ Key = "tag:${s.tag_key}", Values = s.tag_values }]
        MaxConcurrency      = "10"
        MaxErrors           = "25%"
      }
    }
  } if length(s.tag_values) > 0]...)

  rds_runs = merge([for k, s in local.schedules : merge([for db in s.rds_instances : {
    for action in ["stop", "start"] : "${k}-${db}-${action}" => {
      schedule = k
      action   = action
      what     = "RDS instance ${db}"
      cron     = action == "stop" ? s.stop : s.start
      timezone = s.timezone
      input = {
        DocumentName = action == "stop" ? "AWS-StopRdsInstance" : "AWS-StartRdsInstance"
        Parameters   = { InstanceId = [db] }
      }
    }
  }]...)]...)

  runs      = merge(local.ec2_runs, local.rds_runs)
  scheduled = length(local.runs) > 0

  runbooks = ["AWS-StopEC2Instance", "AWS-StartEC2Instance", "AWS-StopRdsInstance", "AWS-StartRdsInstance"]
  ec2_tags = { for k, s in local.schedules : k => { key = s.tag_key, values = s.tag_values } if length(s.tag_values) > 0 }
  rds_arns = distinct(flatten([for k, s in local.schedules : [for db in s.rds_instances : "arn:${local.partition}:rds:${local.region}:${local.account_id}:db:${db}"]]))
}

resource "aws_scheduler_schedule_group" "this" {
  count = local.scheduled ? 1 : 0

  name = "${var.team}-running-hours"
  tags = local.tags
}

# EventBridge Scheduler calls StartAutomationExecution directly (a universal
# target); the input is the API request.
# https://docs.aws.amazon.com/scheduler/latest/UserGuide/managing-targets-universal.html
resource "aws_scheduler_schedule" "this" {
  for_each = local.runs

  name                         = each.key
  group_name                   = aws_scheduler_schedule_group.this[0].name
  description                  = "${var.team}, ${each.value.schedule}: ${each.value.action} ${each.value.what}"
  schedule_expression          = each.value.cron
  schedule_expression_timezone = each.value.timezone

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = "arn:${local.partition}:scheduler:::aws-sdk:ssm:startAutomationExecution"
    role_arn = aws_iam_role.scheduler[0].arn
    input = jsonencode(merge(each.value.input, {
      Parameters = merge(try(each.value.input.Parameters, {}), { AutomationAssumeRole = [aws_iam_role.automation[0].arn] })
    }))

    retry_policy {
      maximum_event_age_in_seconds = 3600
      maximum_retry_attempts       = 3
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count = local.scheduled ? 1 : 0

  name_prefix          = "${substr(var.team, 0, 20)}-hours-sched-"
  description          = "EventBridge Scheduler starts ${var.team}'s stop and start runbooks in ${local.region}"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "scheduler" {
  count = local.scheduled ? 1 : 0

  name = "start-runbooks"
  role = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartTheRunbooks"
        Effect   = "Allow"
        Action   = "ssm:StartAutomationExecution"
        Resource = [for r in local.runbooks : "arn:${local.partition}:ssm:${local.region}:*:automation-definition/${r}:*"]
      },
      {
        Sid       = "PassTheAutomationRole"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = aws_iam_role.automation[0].arn
        Condition = { StringEquals = { "iam:PassedToService" = "ssm.amazonaws.com" } }
      },
      { Sid = "ResolveTagTargets", Effect = "Allow", Action = "tag:GetResources", Resource = "*" },
    ]
  })
}

resource "aws_iam_role" "automation" {
  count = local.scheduled ? 1 : 0

  name_prefix          = "${substr(var.team, 0, 20)}-hours-run-"
  description          = "Systems Manager Automation stops and starts ${var.team}'s scheduled instances in ${local.region}"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "automation" {
  count = local.scheduled ? 1 : 0

  name = "stop-and-start"
  role = aws_iam_role.automation[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "Read"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ec2:DescribeInstanceStatus", "rds:DescribeDBInstances", "tag:GetResources"]
        Resource = "*"
      }],
      [for k, t in local.ec2_tags : {
        Sid       = "Ec2${replace(title(replace(k, "-", " ")), " ", "")}"
        Effect    = "Allow"
        Action    = ["ec2:StopInstances", "ec2:StartInstances"]
        Resource  = "arn:${local.partition}:ec2:${local.region}:${local.account_id}:instance/*"
        Condition = { StringEquals = { "aws:ResourceTag/${t.key}" = t.values } }
      }],
      length(local.rds_arns) == 0 ? [] : [{
        Sid      = "Rds"
        Effect   = "Allow"
        Action   = ["rds:StopDBInstance", "rds:StartDBInstance"]
        Resource = local.rds_arns
      }],
    )
  })
}
