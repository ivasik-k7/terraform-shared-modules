# Every advisory check: the input that trips it, and the same input acknowledged.
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

run "no_topic_warns_that_nobody_hears_a_failure" {
  command = plan

  variables {
    sns_topic_arn = ""
  }

  expect_failures = [check.somebody_hears_a_failure]
}

run "no_topic_is_silent_once_acknowledged_that_nobody_hears_a_failure" {
  command = plan

  variables {
    sns_topic_arn       = ""
    acknowledged_checks = ["somebody_hears_a_failure"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "somebody_hears_a_failure")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_single_subnet_warns" {
  command = plan

  variables {
    subnet_ids = ["subnet-0a1b2c3d4e5f60001"]
  }

  expect_failures = [check.fleet_survives_an_az]
}

run "a_single_subnet_is_silent_once_acknowledged" {
  command = plan

  variables {
    subnet_ids          = ["subnet-0a1b2c3d4e5f60001"]
    acknowledged_checks = ["fleet_survives_an_az"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "fleet_survives_an_az")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_all_spot_fleet_warns" {
  command = plan

  variables {
    instance_types   = ["m7i.large", "m6i.large"]
    purchase_options = { on_demand_percentage_above_base_capacity = 0 }
  }

  expect_failures = [check.spot_fleets_keep_an_on_demand_floor]
}

run "an_all_spot_fleet_is_silent_once_acknowledged" {
  command = plan

  variables {
    instance_types      = ["m7i.large", "m6i.large"]
    purchase_options    = { on_demand_percentage_above_base_capacity = 0 }
    acknowledged_checks = ["spot_fleets_keep_an_on_demand_floor"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "spot_fleets_keep_an_on_demand_floor")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "volumes_on_the_account_key_warn" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [check.volumes_use_a_customer_key]
}

run "volumes_on_the_account_key_are_silent_once_acknowledged" {
  command = plan

  variables {
    kms_key_arn         = ""
    acknowledged_checks = ["volumes_use_a_customer_key"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "volumes_use_a_customer_key")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "unlimited_credits_warn" {
  command = plan

  variables {
    cpu_credits = "unlimited"
  }

  expect_failures = [check.burstable_credits_are_bounded]
}

run "unlimited_credits_are_silent_once_acknowledged" {
  command = plan

  variables {
    cpu_credits         = "unlimited"
    acknowledged_checks = ["burstable_credits_are_bounded"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "burstable_credits_are_bounded")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_ssh_key_warns" {
  command = plan

  variables {
    key_name = "ops"
  }

  expect_failures = [check.instances_are_reached_without_ssh_keys]
}

run "an_ssh_key_is_silent_once_acknowledged" {
  command = plan

  variables {
    key_name            = "ops"
    acknowledged_checks = ["instances_are_reached_without_ssh_keys"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "instances_are_reached_without_ssh_keys")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_public_ip_warns" {
  command = plan

  variables {
    public_ip = "assign"
  }

  expect_failures = [check.instances_have_no_public_ip]
}

run "a_public_ip_is_silent_once_acknowledged" {
  command = plan

  variables {
    public_ip           = "assign"
    acknowledged_checks = ["instances_have_no_public_ip"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "instances_have_no_public_ip")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "refresh_off_warns" {
  command = plan

  variables {
    instance_refresh = { enabled = false }
  }

  expect_failures = [check.launch_template_changes_reach_the_fleet]
}

run "refresh_off_is_silent_once_acknowledged" {
  command = plan

  variables {
    instance_refresh    = { enabled = false }
    acknowledged_checks = ["launch_template_changes_reach_the_fleet"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "launch_template_changes_reach_the_fleet")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_hop_limit_of_two_warns" {
  command = plan

  variables {
    metadata_hop_limit = 2
  }

  expect_failures = [check.containers_cannot_reach_instance_credentials]
}

run "a_hop_limit_of_two_is_silent_once_acknowledged" {
  command = plan

  variables {
    metadata_hop_limit  = 2
    acknowledged_checks = ["containers_cannot_reach_instance_credentials"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "containers_cannot_reach_instance_credentials")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_ami_from_ssm_warns" {
  command = plan

  variables {
    ami               = ""
    ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  }

  expect_failures = [check.ami_is_pinned]
}

run "an_ami_from_ssm_is_silent_once_acknowledged" {
  command = plan

  variables {
    ami                 = ""
    ami_ssm_parameter   = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    acknowledged_checks = ["ami_is_pinned"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "ami_is_pinned")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "retaining_abandoned_instances_warns" {
  command = plan

  variables {
    terminate_hook_abandon = "retain"
    lifecycle_hooks        = { drain = { transition = "TERMINATING" } }
  }

  expect_failures = [check.retained_instances_are_cleaned_up]
}

run "retaining_abandoned_instances_is_silent_once_acknowledged" {
  command = plan

  variables {
    terminate_hook_abandon = "retain"
    lifecycle_hooks        = { drain = { transition = "TERMINATING" } }
    acknowledged_checks    = ["retained_instances_are_cleaned_up"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "retained_instances_are_cleaned_up")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}
