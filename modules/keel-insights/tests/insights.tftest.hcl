# Plan properties of keel-insights.
#
# What a mock cannot show: the CID templates deploying, Quick Sight accepting
# the user, or data arriving in the bucket.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "333333333333" }
  }
}

variables {
  data_exports = { source_account_ids = ["444444444444"] }
  quicksight   = { user = "finops-admin", subscription_ready = true }
}

run "the_templates_are_aws_published_versions" {
  command = plan

  assert {
    condition     = aws_cloudformation_stack.data_exports_destination[0].template_url == "https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn/data-exports/0.13.0/data-exports-aggregation.yaml"
    error_message = "the data pipeline comes from AWS's published template, pinned."
  }

  assert {
    condition     = aws_cloudformation_stack.dashboards[0].parameters["CURVersion"] == "2.0" && aws_cloudformation_stack.dashboards[0].parameters["DeployCUDOSv5"] == "yes"
    error_message = "the dashboards read CUR 2.0 and CUDOS v5 is on by default."
  }

  assert {
    condition     = output.data_bucket == "cid-333333333333-data-exports"
    error_message = "the bucket name is the template's: <prefix>-<account>-data-exports."
  }
}

run "the_default_templates_carry_their_reviewed_hashes" {
  command = plan

  assert {
    condition     = output.templates.dashboards.reviewed_sha256 == "4ff3367615fe05dea571a0c4960d446a9e6f395c311b0d0fffc487b99422d455" ? strcontains(output.verify_commands.template_dashboards, "echo reviewed") : false
    error_message = "the reviewed cid-cfn 4.4.21 hash is emitted, and the check command compares against it."
  }

  assert {
    condition     = aws_cloudformation_stack.dashboards[0].parameters["LambdaLayerBucketPrefix"] == "aws-managed-cost-intelligence-dashboards"
    error_message = "the Lambda layer comes from AWS's bucket by default."
  }
}

run "a_mirror_serves_the_templates_and_the_lambda_layer" {
  # The templates run with CAPABILITY_NAMED_IAM; a mirror the estate controls
  # keeps a re-upload at AWS's path from changing what a stack update runs.
  command = plan

  variables {
    templates = { url_prefix = "https://cid-mirror.s3.eu-west-2.amazonaws.com/cfn", lambda_layer_bucket_prefix = "cid-mirror-layers" }
  }

  assert {
    condition     = aws_cloudformation_stack.dashboards[0].template_url == "https://cid-mirror.s3.eu-west-2.amazonaws.com/cfn/4.4.21/cid-cfn.yml" ? aws_cloudformation_stack.dashboards[0].parameters["LambdaLayerBucketPrefix"] == "cid-mirror-layers" : false
    error_message = "the dashboards template and its layer come from the mirror."
  }

  assert {
    condition     = output.source_requirements.template_url_prefix == "https://cid-mirror.s3.eu-west-2.amazonaws.com/cfn"
    error_message = "keel-billing is told to use the same mirror."
  }
}

run "an_unreviewed_version_has_no_hash_to_compare" {
  command = plan

  variables {
    dashboards = { version = "4.4.99" }
  }

  assert {
    condition     = output.templates.dashboards.reviewed_sha256 == null ? strcontains(output.verify_commands.template_dashboards, "unreviewed") : false
    error_message = "a version nobody reviewed says so instead of claiming a match."
  }
}

run "plugins_deploy_one_after_another_in_a_fixed_order" {
  command = plan

  variables {
    dashboards = { plugins = ["cora", "focus-dashboard", "trends-dashboard"] }
  }

  assert {
    condition     = aws_cloudformation_stack.plugin_1[0].parameters["DashboardId"] == "trends-dashboard" && aws_cloudformation_stack.plugin_3[0].parameters["DashboardId"] == "cora"
    error_message = "plugins follow AWS's order, whatever order they are listed in."
  }

  assert {
    condition     = length(aws_cloudformation_stack.plugin_4) == 0
    error_message = "only the requested plugins deploy."
  }
}

run "dashboards_without_quicksight_are_refused" {
  # cid-cfn.yml accepts only "yes" for its prerequisite parameters.
  command = plan

  variables {
    quicksight = { user = "finops-admin" }
  }

  expect_failures = [aws_cloudformation_stack.dashboards]
}

run "a_dashboard_without_its_table_warns" {
  command = plan

  variables {
    data_exports = { source_account_ids = ["444444444444"], focus = false }
  }

  expect_failures = [check.dashboards_have_their_data]
}

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_cloudformation_stack.dashboards) == 0 && output.data_bucket == null && length(output.stacks) == 0 && output.governance == null
    error_message = "create = false creates nothing."
  }
}
