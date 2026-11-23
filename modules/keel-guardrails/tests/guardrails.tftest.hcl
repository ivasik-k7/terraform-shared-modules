# Plan properties of keel-guardrails.
#
# What a mock cannot show: AWS Organizations accepting the policy syntax, or
# an SCP refusing a real call.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "444444444444" }
  }
}

variables {
  targets = ["ou-ab12-pilotou1"]
  required_tags = {
    Team        = { report_for = ["ec2:instance"] }
    Environment = { values = ["production", "sandbox"], enforce_for = ["ec2:instance"] }
  }
  deny_untagged       = { enabled = true, tags = ["Team"], exempt_principals = ["arn:aws:iam::*:role/break-glass"] }
  bedrock_models      = { enabled = true, allowed_models = ["example.model-a"], allowed_regions = ["eu-west-2"], exempt_principals = ["arn:aws:iam::*:role/break-glass"] }
  ai_services_opt_out = { enabled = true }
}

run "the_tag_policy_uses_the_documented_operators" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.this["tags"].content).tags.team.tag_key["@@assign"] == "Team" && jsondecode(aws_organizations_policy.this["tags"].content).tags.team.report_required_tag_for["@@assign"] == ["ec2:instance"]
    error_message = "a required tag is a tag_key with report_required_tag_for, in the exact case."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["tags"].content).tags.environment.enforced_for["@@assign"] == ["ec2:instance"]
    error_message = "enforce_for becomes enforced_for."
  }
}

run "untagged_creation_is_denied_except_for_break_glass" {
  command = plan

  assert {
    condition     = jsondecode(aws_organizations_policy.this["untagged"].content).Statement[0].Condition.Null["aws:RequestTag/Team"] == "true"
    error_message = "a create without the tag in the request is denied."
  }

  assert {
    condition     = jsondecode(aws_organizations_policy.this["untagged"].content).Statement[0].Condition.ArnNotLike["aws:PrincipalArn"] == ["arn:aws:iam::*:role/break-glass"]
    error_message = "break-glass roles are exempt."
  }
}

run "only_approved_models_in_approved_regions_are_called" {
  command = plan

  assert {
    condition     = contains(jsondecode(aws_organizations_policy.this["models"].content).Statement[0].NotResource, "arn:aws:bedrock:eu-west-2::foundation-model/example.model-a")
    error_message = "the approved model in the approved region is not denied."
  }
}

run "ai_services_are_opted_out_by_default_key" {
  command = plan

  assert {
    condition     = aws_organizations_policy.this["ai-opt-out"].type == "AISERVICES_OPT_OUT_POLICY" && jsondecode(aws_organizations_policy.this["ai-opt-out"].content).services.default.opt_out_policy["@@assign"] == "optOut"
    error_message = "the default key opts every AI service out."
  }
}

run "every_policy_is_attached_to_every_target" {
  command = plan

  assert {
    condition     = length(aws_organizations_policy_attachment.this) == 4
    error_message = "four policies on one target."
  }
}

run "an_scp_without_break_glass_warns" {
  command = plan

  variables {
    deny_untagged = { enabled = true, tags = ["Team"] }
  }

  expect_failures = [check.someone_can_break_glass]
}

run "a_model_list_without_regions_is_rejected" {
  command = plan

  variables {
    bedrock_models = { enabled = true, allowed_models = ["example.model-a"] }
  }

  expect_failures = [var.bedrock_models]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_organizations_policy.this) == 0 && length(aws_organizations_policy_attachment.this) == 0 && output.controls == null
    error_message = "create = false creates nothing."
  }
}
