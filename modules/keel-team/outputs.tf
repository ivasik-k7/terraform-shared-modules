# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

output "topic_arns" {
  description = "This Region's severity topics, by severity. Point the team's own alarms at them; they reach the owners and the control plane."
  value       = local.topic_arns
}

output "budget_names" {
  description = "The account's limits as budget names, by limit: the caller's, platform-<name> and ai-<application>. Empty outside the account part."
  value       = module.limits.budget_names
}

output "lock_policy_arns" {
  description = "The deny policies AWS Budgets attaches when a limit's action runs, by limit. Detach one, or raise the limit, to unlock."
  value       = module.limits.lock_policy_arns
}

output "inference_profile_arns" {
  description = "Application inference profile ARNs in this Region, by application and model alias. Applications call Bedrock with these, so their cost carries the Team, Application and platform tags."
  value = {
    for app in keys(local.applications) : app => {
      for k, p in aws_bedrock_inference_profile.this : local.profiles[k].alias => p.arn if local.profiles[k].application == app
    }
  }
}

output "ai_ceilings" {
  description = "The quotas read in this Region, with the most a priced model can cost in an hour at its quota: every token per minute for 60 minutes at the model's higher price. An upper bound, not a forecast."
  value = { for k, q in data.aws_servicequotas_service_quota.ai : k => {
    quota_code          = q.quota_code
    quota_name          = q.quota_name
    value               = q.value
    model_id            = local.quotas[k].model_id
    worst_case_per_hour = local.quotas[k].model_id == "" ? null : q.value * 60 * max(var.ai.prices[local.quotas[k].model_id].input_per_million, var.ai.prices[local.quotas[k].model_id].output_per_million) / 1000000
    unit                = var.ai.unit
  } }
}

output "finops_read_role_arn" {
  description = "The FinOps read-only role in this account, when finops_access.trusted_account_id is set."
  value       = one(aws_iam_role.finops_read[*].arn)
}

output "schedules" {
  description = "The running-hours schedules in this Region, by name: what they stop and start, and when."
  value = { for k, s in local.schedules : k => {
    stop      = "${s.stop} ${s.timezone}"
    start     = "${s.start} ${s.timezone}"
    ec2       = length(s.tag_values) > 0 ? "${s.tag_key} = ${join(" | ", s.tag_values)}" : null
    rds       = s.rds_instances
    schedules = sort([for r, x in aws_scheduler_schedule.this : x.name if local.runs[r].schedule == k])
  } }
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

output "plan_gate" {
  description = "What the HCP Terraform cost gate (policies/cost-gate.sentinel) compares a run against: the team and its account limit. Null without a monthly account limit."
  value = !local.account || local.account_limit == null ? null : (try(local.account_limit.period, "MONTHLY") != "MONTHLY" ? null : {
    team           = var.team
    tier           = local.account_limit.tier
    monthly_budget = tonumber(local.account_limit.amount)
    unit           = try(local.account_limit.unit, "USD")
  })
}

output "controls" {
  description = "The Keel controls this call implements for the team, as register entries: FC-01, FC-04 and FC-06 and every limit (LIMIT-<name>)."
  value = !local.create ? null : merge(
    !local.account || length(local.account_limits) == 0 ? {} : {
      "FC-01" = {
        statement      = "Every account is created with an owner and a budget"
        type           = "Prevent"
        threshold      = "Owner ${var.team}, cost centre ${var.cost_centre}, ${local.account_limit.amount} ${try(local.account_limit.unit, "USD")} ${lower(try(local.account_limit.period, "MONTHLY"))}"
        evidence       = "This configuration; the budget ${module.limits.budget_names[local.account_limits[0]]}"
        implemented_by = [module.limits.budget_names[local.account_limits[0]]]
      }
      "FC-04" = {
        statement      = "A forecast overrun alerts the owner"
        type           = "Detect"
        threshold      = join("; ", module.limits.thresholds[local.account_limits[0]])
        evidence       = "Budget notification history; the warning topic and the control plane"
        implemented_by = [module.limits.budget_names[local.account_limits[0]]]
      }
    },
    length(var.ai.applications) == 0 ? {} : {
      "FC-06" = {
        statement = "AI spend per application stays under its cap"
        type      = "Detect"
        threshold = join("; ", concat(
          [for k, a in var.ai.applications : "${k}: ${a.monthly_cap} ${var.ai.unit} a month"],
          local.burn_alarm ? ["burn above ${var.ai.burn_per_hour} ${var.ai.unit} an hour in ${local.region}"] : [],
        ))
        evidence = "AI budgets' notification history${local.burn_alarm ? "; the ai-burn alarm's history" : ""}${local.invocation_logs ? "; ${local.log_group_name}" : ""}"
        implemented_by = concat(
          sort([for k in keys(var.ai.applications) : module.limits.budget_names["ai-${k}"] if local.account]),
          aws_cloudwatch_metric_alarm.ai_burn[*].alarm_name,
        )
      }
    },
    [for c in [module.limits.controls] : c if c != null]...
  )
}

output "kms_key_policy_requirements" {
  description = "What the customer managed key in signals.kms_key_arn must allow, in contract version 2: the severity topics and queue (keel-signals) and the invocation log group."
  value = !local.create || var.signals.kms_key_arn == "" ? null : concat(
    module.signals.kms_key_policy_requirements,
    !local.invocation_logs ? [] : [{
      key        = var.signals.kms_key_arn
      sid        = "${replace(title(replace(var.team, "-", " ")), " ", "")}LogsInvocations"
      principals = { services = ["logs.${local.region}.amazonaws.com"], arns = [], roles = [] }
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.log_group_name}"] }]
      purpose    = "CloudWatch Logs encrypts ${var.team}'s Bedrock invocation log group."
    }],
  )
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs in the team's account for this call."
  value = !local.create ? null : {
    actions = distinct(concat(
      ["sns:CreateTopic", "sns:DeleteTopic", "sns:SetTopicAttributes", "sns:GetTopicAttributes", "sns:Subscribe", "sns:Unsubscribe", "sns:TagResource"],
      var.signals.control_plane_bus_arn == "" ? [] : [
        "sqs:CreateQueue", "sqs:DeleteQueue", "sqs:SetQueueAttributes", "sqs:GetQueueAttributes", "sqs:TagQueue",
        "pipes:CreatePipe", "pipes:DeletePipe", "pipes:UpdatePipe", "pipes:DescribePipe", "pipes:TagResource",
        "events:PutRule", "events:DeleteRule", "events:PutTargets", "events:RemoveTargets", "events:DescribeRule",
      ],
      !local.account ? [] : ["budgets:ModifyBudget", "budgets:ViewBudget", "budgets:TagResource", "budgets:ListTagsForResource", "ce:CreateAnomalyMonitor", "ce:UpdateAnomalyMonitor", "ce:DeleteAnomalyMonitor", "ce:GetAnomalyMonitors", "ce:CreateAnomalySubscription", "ce:UpdateAnomalySubscription", "ce:DeleteAnomalySubscription", "ce:GetAnomalySubscriptions", "ce:TagResource"],
      length(local.actions) == 0 ? [] : ["budgets:CreateBudgetAction", "budgets:UpdateBudgetAction", "budgets:DeleteBudgetAction", "budgets:DescribeBudgetAction", "iam:CreatePolicy", "iam:DeletePolicy"],
      ["iam:CreateRole", "iam:DeleteRole", "iam:GetRole", "iam:TagRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:PassRole"],
      length(local.profiles) == 0 ? [] : ["bedrock:CreateInferenceProfile", "bedrock:DeleteInferenceProfile", "bedrock:GetInferenceProfile", "bedrock:TagResource"],
      !local.burn_alarm ? [] : ["cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms", "cloudwatch:TagResource"],
      length(local.quotas) == 0 ? [] : ["servicequotas:GetServiceQuota"],
      !local.invocation_logs ? [] : ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:AssociateKmsKey", "logs:TagResource", "bedrock:PutModelInvocationLoggingConfiguration", "bedrock:GetModelInvocationLoggingConfiguration", "bedrock:DeleteModelInvocationLoggingConfiguration"],
      !local.scheduled ? [] : ["scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule", "scheduler:GetSchedule", "scheduler:CreateScheduleGroup", "scheduler:DeleteScheduleGroup", "scheduler:TagResource"],
    ))
  }
}

output "governance" {
  description = "The team's posture in this call, as data."
  value = !local.create ? null : {
    team             = var.team
    tier             = var.tier
    cost_centre      = var.cost_centre
    region           = local.region
    components       = [for c in ["account", "region"] : c if var.components[c]]
    platform_tag_key = var.platform_tag_key
    limits           = module.limits.governance
    account_limit    = length(local.account_limits) > 0 ? local.account_limits[0] : null
    platforms        = sort(keys(var.platforms))
    ai = {
      applications    = { for k, a in local.applications : k => { models = sort(keys(a.models)), cap = a.monthly_cap, platform = a.platform } }
      burn_per_hour   = local.burn_alarm ? var.ai.burn_per_hour : null
      invocation_logs = local.invocation_logs ? "metadata only, ${var.ai.invocation_logs.retention_days} days" : "off"
    }
    schedules        = sort(keys(local.schedules))
    finops_read_role = local.finops_access ? var.finops_access.role_name : null
    to_control_plane = var.signals.control_plane_bus_arn != ""
    acknowledged     = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "Read-only commands to run from CloudShell in the team's account and this Region."
  value = !local.create ? null : merge(
    module.signals.verify_commands,
    !local.account ? {} : {
      budgets = "aws budgets describe-budgets --account-id ${local.account_id} --query \"Budgets[?starts_with(BudgetName, '${var.team}-')].[BudgetName,BudgetLimit.Amount,CalculatedSpend.ActualSpend.Amount]\" --output table"
    },
    {
      inference_profiles = "aws bedrock list-inference-profiles --region ${local.region} --type-equals APPLICATION --query \"inferenceProfileSummaries[?starts_with(inferenceProfileName, '${var.team}-')].[inferenceProfileName,status]\" --output table"
      bedrock_models     = "aws cloudwatch list-metrics --region ${local.region} --namespace AWS/Bedrock --metric-name InputTokenCount --query 'Metrics[].Dimensions'"
    },
    !local.invocation_logs ? {} : {
      invocation_logging = "aws bedrock get-model-invocation-logging-configuration --region ${local.region}"
    },
    !local.scheduled ? {} : {
      schedules = "aws scheduler list-schedules --region ${local.region} --group-name ${var.team}-running-hours --query 'Schedules[].[Name,State]' --output table"
      runs      = "aws ssm describe-automation-executions --region ${local.region} --filters Key=DocumentNamePrefix,Values=AWS-Stop --query 'AutomationExecutionMetadataList[0:10].[DocumentName,AutomationExecutionStatus,ExecutionStartTime]' --output table"
    },
  )
}
