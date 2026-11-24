# Plan properties of keel-team.
#
# What a mock cannot show: AWS Budgets running a lock, Bedrock creating a
# profile from the model, the token metrics carrying these ModelIds, Bedrock
# logging metadata with every data type off, or Systems Manager resolving the
# tag targets.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111111111111" }
  }
  mock_data "aws_servicequotas_service_quota" {
    defaults = { quota_code = "L-AAAAAAAA", quota_name = "Tokens per minute", value = 200000 }
  }
  mock_resource "aws_sns_topic" {
    override_during = plan
    defaults        = { arn = "arn:aws:sns:eu-west-2:111111111111:lending-mock" }
  }
  mock_resource "aws_iam_role" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:role/mock" }
  }
  mock_resource "aws_iam_policy" {
    override_during = plan
    defaults        = { arn = "arn:aws:iam::111111111111:policy/mock" }
  }
  mock_resource "aws_sqs_queue" {
    override_during = plan
    defaults        = { arn = "arn:aws:sqs:eu-west-2:111111111111:mock", url = "https://sqs.eu-west-2.amazonaws.com/111111111111/mock" }
  }
}

variables {
  team        = "lending"
  cost_centre = "CC-4410"
  tier        = "sandbox"
  emails      = { high = ["leads@example.com"] }
  limits = {
    account = { amount = "8500", action = { lock_roles = ["developer"] } }
  }
  platforms = {
    payments = { amount = "4000", anomaly = {} }
  }
  ai = {
    applications = {
      assistant = { models = { sonnet = "arn:aws:bedrock:eu-west-2::foundation-model/example.model-a" }, monthly_cap = 6000, platform = "payments" }
    }
    prices          = { "example.model-a" = { input_per_million = 3, output_per_million = 15 } }
    burn_per_hour   = 40
    quotas          = { model-a-tpm = { quota_code = "L-AAAAAAAA", model_id = "example.model-a" } }
    invocation_logs = { enabled = true }
  }
  schedules = {
    office-hours = { tag_values = ["office-hours"], rds_instances = ["lending-dev"], stop = "cron(0 19 ? * MON-FRI *)", start = "cron(0 8 ? * MON-FRI *)" }
  }
  finops_access = { trusted_account_id = "444444444444" }
  signals       = { control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel" }
}

run "every_platform_gets_a_limit_on_its_tag" {
  command = plan

  assert {
    condition     = jsonencode(module.limits.governance["platform-payments"].scope) == jsonencode(["Platform = payments"])
    error_message = "the platform's limit counts the spend tagged Platform = payments."
  }

  assert {
    condition     = contains(keys(output.budget_names), "platform-payments") && contains(keys(output.budget_names), "account")
    error_message = "the account limit and the platform limit are both budgets."
  }
}

run "the_platform_tag_key_is_the_callers" {
  command = plan

  variables {
    platform_tag_key = "Workload"
  }

  assert {
    condition     = jsonencode(module.limits.governance["platform-payments"].scope) == jsonencode(["Workload = payments"])
    error_message = "the platform limit filters on platform_tag_key."
  }

  assert {
    condition     = aws_bedrock_inference_profile.this["assistant/sonnet"].tags["Workload"] == "payments"
    error_message = "the inference profile carries the platform tag under the same key."
  }
}

run "a_platform_narrows_further_with_its_own_scope" {
  command = plan

  variables {
    platforms = { payments = { amount = "4000", scope = { regions = ["eu-west-1"] } } }
  }

  assert {
    condition     = jsonencode(module.limits.governance["platform-payments"].scope) == jsonencode(["Platform = payments", "REGION = eu-west-1"])
    error_message = "a platform's own scope is ANDed with its tag."
  }
}

run "each_ai_application_gets_a_tagged_profile_and_a_cap" {
  command = plan

  assert {
    condition     = aws_bedrock_inference_profile.this["assistant/sonnet"].tags["Application"] == "assistant" && aws_bedrock_inference_profile.this["assistant/sonnet"].tags["Team"] == "lending"
    error_message = "the profile carries the tags the bill allocates by."
  }

  assert {
    condition     = jsonencode(module.limits.thresholds["ai-assistant"]) == jsonencode(["actual 50%: WARNING", "actual 80%: WARNING", "actual 90%: WARNING", "actual 100%: CRITICAL"])
    error_message = "the cap alerts at 50, 80, 90 and 100% of actual spend; in a sandbox the cap is CRITICAL."
  }
}

run "the_burn_meter_pages_critical" {
  command = plan

  assert {
    condition     = strcontains(one([for q in aws_cloudwatch_metric_alarm.ai_burn[0].metric_query : q.expression if q.id == "cost"]), "* 3 +") && aws_cloudwatch_metric_alarm.ai_burn[0].threshold == 40
    error_message = "the alarm prices input and output tokens from the rate card and fires above burn_per_hour."
  }

  assert {
    condition     = jsonencode(aws_cloudwatch_metric_alarm.ai_burn[0].alarm_actions) == jsonencode([output.topic_arns["critical"]])
    error_message = "the burn alarm notifies the critical topic."
  }
}

run "the_quota_ceiling_is_priced" {
  command = plan

  assert {
    # 200000 tokens a minute, 60 minutes, at 15 per million.
    condition     = output.ai_ceilings["model-a-tpm"].worst_case_per_hour == 180
    error_message = "the ceiling is the quota for an hour at the model's higher price."
  }
}

run "invocation_logs_carry_no_content" {
  command = plan

  assert {
    condition = alltrue([
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].text_data_delivery_enabled,
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].image_data_delivery_enabled,
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].embedding_data_delivery_enabled,
      !aws_bedrock_model_invocation_logging_configuration.this[0].logging_config[0].video_data_delivery_enabled,
    ])
    error_message = "no prompt, response, image, embedding or video is delivered."
  }

  assert {
    condition     = endswith(jsondecode(aws_iam_role_policy.invocation_logs[0].policy).Statement[0].Resource, ":log-stream:aws/bedrock/modelinvocations")
    error_message = "Bedrock may write only its own log stream."
  }
}

run "schedules_stop_and_start_by_tag_and_by_instance" {
  command = plan

  assert {
    condition     = length(aws_scheduler_schedule.this) == 4
    error_message = "a stop and a start for the tagged EC2 instances, and for the RDS instance."
  }

  assert {
    condition     = jsondecode(aws_scheduler_schedule.this["office-hours/ec2/stop"].target[0].input).Targets[0].Key == "tag:Schedule" && jsondecode(aws_scheduler_schedule.this["office-hours/ec2/stop"].target[0].input).DocumentName == "AWS-StopEC2Instance"
    error_message = "EC2 instances are selected by their tag and stopped by the AWS runbook."
  }

  assert {
    condition     = jsonencode(jsondecode(aws_scheduler_schedule.this["office-hours/rds/lending-dev/stop"].target[0].input).Parameters.InstanceId) == jsonencode(["lending-dev"])
    error_message = "an RDS instance is stopped by its identifier."
  }

  assert {
    condition     = aws_scheduler_schedule.this["office-hours/ec2/stop"].schedule_expression_timezone == "Europe/London"
    error_message = "schedules run in the team's time zone."
  }
}

run "schedules_that_differ_only_in_where_a_hyphen_falls_stay_apart" {
  # dev + db-orders and dev-db + orders once produced one key, and one of the
  # instances was silently never stopped.
  command = plan

  variables {
    schedules = {
      dev    = { rds_instances = ["db-orders"], stop = "cron(0 19 ? * MON-FRI *)", start = "cron(0 8 ? * MON-FRI *)" }
      dev-db = { rds_instances = ["orders"], stop = "cron(0 19 ? * MON-FRI *)", start = "cron(0 8 ? * MON-FRI *)" }
    }
  }

  assert {
    condition     = length(aws_scheduler_schedule.this) == 4 ? length(distinct([for x in aws_scheduler_schedule.this : x.name])) == 4 : false
    error_message = "each instance keeps its own stop and start schedule."
  }
}

run "the_automation_role_stops_only_tagged_instances" {
  command = plan

  assert {
    condition     = jsonencode(one([for s in jsondecode(aws_iam_role_policy.automation[0].policy).Statement : s.Condition if s.Sid == "Ec2OfficeHours"])) == jsonencode({ StringEquals = { "aws:ResourceTag/Schedule" = ["office-hours"] } })
    error_message = "StopInstances and StartInstances are limited to instances carrying the schedule's tag."
  }
}

run "the_finops_role_is_trusted_by_the_finops_account_only" {
  command = plan

  assert {
    condition     = jsonencode(jsondecode(aws_iam_role.finops_read[0].assume_role_policy).Statement[0].Principal.AWS) == jsonencode(["arn:aws:iam::444444444444:root"])
    error_message = "the FinOps account, and nobody else, may assume the role."
  }

  assert {
    # These return object contents, user data, task environments and function
    # environment variables: secrets, in practice.
    condition = alltrue([for a in [
      "s3:GetObject", "s3:ListBucket\"", "ec2:Describe*", "ec2:DescribeInstanceAttribute", "ec2:DescribeLaunchTemplateVersions",
      "autoscaling:Describe*", "autoscaling:DescribeLaunchConfigurations", "ecs:Describe*", "ecs:DescribeTaskDefinition",
      "ecs:DescribeTasks", "lambda:", "secretsmanager:", "ssm:GetParameter", "logs:GetLogEvents", "logs:FilterLogEvents",
    ] : !strcontains(aws_iam_role_policy.finops_read[0].policy, a)])
    error_message = "the FinOps role reads no data, configuration or secrets."
  }
}

run "a_region_only_call_creates_no_limits_and_no_role" {
  command = plan

  variables {
    components = { account = false }
  }

  assert {
    condition     = length(output.budget_names) == 0 && output.finops_read_role_arn == null && output.plan_gate == null
    error_message = "budgets and the FinOps role are the account part's."
  }

  assert {
    condition     = length(output.topic_arns) == 4 && length(aws_bedrock_inference_profile.this) == 1
    error_message = "the Region part still has its topics and its AI profiles."
  }
}

run "an_account_part_without_a_region_part_is_rejected" {
  command = plan

  variables {
    components = { account = true, region = false }
  }

  expect_failures = [var.components]
}

run "a_limit_named_like_a_platform_is_rejected" {
  # A caller limit named platform-<x> would replace the platform's own.
  command = plan

  variables {
    limits = { platform-payments = { amount = "1" } }
  }

  expect_failures = [var.limits]
}

run "an_account_without_an_account_limit_warns" {
  command = plan

  variables {
    limits = {}
    tier   = "production"
  }

  expect_failures = [check.every_account_has_a_limit]
}

run "a_sandbox_without_an_action_warns" {
  command = plan

  variables {
    limits = { account = { amount = "8500" } }
  }

  expect_failures = [check.sandboxes_lock_at_their_limit]
}

run "plan_gate_takes_the_account_limit" {
  command = plan

  assert {
    condition     = output.plan_gate.max_monthly_increase == 850 ? output.plan_gate.tier == "sandbox" : false
    error_message = "one run may add 10% of the account limit: the parameter the policy reads."
  }
}

run "an_auto_adjusting_account_limit_plans_without_a_gate" {
  # The gate once read the limit's amount, which an auto-adjusting limit does
  # not have, and the plan failed.
  command = plan

  variables {
    limits = { account = { auto_adjust_months = 6, action = { lock_roles = ["developer"] } } }
  }

  assert {
    condition     = output.plan_gate == null ? contains(keys(output.controls), "FC-01") : false
    error_message = "no gate without an amount, and FC-01 still describes the limit."
  }
}

run "inference_profiles_carry_names_and_descriptions_bedrock_accepts" {
  command = plan

  assert {
    condition     = can(regex("^([0-9a-zA-Z:.][ _-]?)+$", aws_bedrock_inference_profile.this["assistant/sonnet"].description)) ? can(regex("^([0-9a-zA-Z][ _-]?)+$", aws_bedrock_inference_profile.this["assistant/sonnet"].name)) : false
    error_message = "the description and name match CreateInferenceProfile's patterns."
  }
}

run "a_profile_name_over_64_characters_is_rejected" {
  command = plan

  variables {
    ai   = { applications = { a-very-long-application-name-x = { models = { a-long-model-alias = "arn:aws:bedrock:eu-west-2::foundation-model/example.model-a" }, monthly_cap = 1 } } }
    team = "a-rather-long-team-name"
  }

  expect_failures = [var.ai]
}

run "more_than_five_priced_models_are_rejected" {
  # One alarm holds at most ten metrics, two per model.
  command = plan

  variables {
    ai = {
      prices = { a = { input_per_million = 1, output_per_million = 1 }, b = { input_per_million = 1, output_per_million = 1 }, c = { input_per_million = 1, output_per_million = 1 }, d = { input_per_million = 1, output_per_million = 1 }, e = { input_per_million = 1, output_per_million = 1 }, f = { input_per_million = 1, output_per_million = 1 } }
    }
  }

  expect_failures = [var.ai]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition = alltrue([
      length(aws_bedrock_inference_profile.this) == 0, length(aws_scheduler_schedule.this) == 0, length(aws_iam_role.finops_read) == 0,
      length(output.budget_names) == 0, length(output.topic_arns) == 0, output.controls == null, output.governance == null, output.plan_gate == null,
    ])
    error_message = "create = false creates nothing and leaves the outputs empty."
  }
}
