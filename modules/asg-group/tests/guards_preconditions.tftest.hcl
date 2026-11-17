# Every precondition, with the input that trips it. Several share aws_launch_template.this, and
# expect_failures cannot name one of them: each run trips one by construction.
# expect_failures names the exact address: var.x for a validation, the
# resource for a precondition, check.x for a check. The baseline is fully
# configured, so each run changes only what it needs to trip one guard.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0fedcba9876543210" }
  }
}

variables {
  name               = "orders"
  ami                = "ami-0123456789abcdef0"
  subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  min_size           = 2
  max_size           = 4
  kms_key_arn        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  sns_topic_arn      = "arn:aws:sns:eu-west-2:111122223333:alerts"
  tags               = { CostCenter = "cc-1", Environment = "test" }
}

run "a_missing_required_tag_fails_the_plan" {
  command = plan

  variables {
    required_tag_keys = ["Owner"]
  }

  expect_failures = [aws_launch_template.this]
}

run "a_weight_for_a_type_not_in_the_fleet_fails_the_plan" {
  command = plan

  variables {
    instance_weights = { "m7i.xlarge" = 2 }
  }

  expect_failures = [aws_launch_template.this]
}

run "a_warm_pool_on_a_spot_fleet_fails_the_plan" {
  command = plan

  variables {
    warm_pool        = { enabled = true }
    instance_types   = ["m7i.large", "m6i.large"]
    purchase_options = { on_demand_base_capacity = 1, on_demand_percentage_above_base_capacity = 0 }
  }

  expect_failures = [aws_launch_template.this]
}

run "scaling_on_a_terraform_owned_count_fails_the_plan" {
  command = plan

  variables {
    ignore_desired_capacity_changes = false
    target_tracking_policies        = { cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 50 } }
  }

  expect_failures = [aws_launch_template.this]
}
