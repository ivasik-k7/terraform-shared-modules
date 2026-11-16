# Every validation of a module-level input, with the input that trips it.
# expect_failures names the exact address: var.x for a validation, the
# resource for a precondition, check.x for a check. The baseline is fully
# configured, so each run changes only what it needs to trip one guard.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

variables {
  name               = "orders"
  subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  sns_topic_arn      = "arn:aws:sns:eu-west-2:111122223333:alerts"
  log_kms_key_arn    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags               = { CostCenter = "cc-1", Environment = "test" }

  services = {
    api = { image = "r/a:1", port = 8080, desired_count = 2 }
  }
}

run "the_baseline_passes_every_guard" {
  command = plan
}

run "a_name_that_cannot_prefix_iam_roles_is_rejected" {
  command = plan

  variables {
    name = "Orders_Prod"
  }

  expect_failures = [var.name]
}

run "a_reserved_tag_prefix_is_rejected" {
  command = plan

  variables {
    tags = { "aws:owner" = "x" }
  }

  expect_failures = [var.tags]
}

run "an_unknown_acknowledged_check_is_rejected" {
  command = plan

  variables {
    acknowledged_checks = ["no_such_check"]
  }

  expect_failures = [var.acknowledged_checks]
}

run "a_subnet_that_is_not_an_id_is_rejected" {
  command = plan

  variables {
    subnet_ids = ["private-a"]
  }

  expect_failures = [var.subnet_ids]
}

run "a_security_group_that_is_not_an_id_is_rejected" {
  command = plan

  variables {
    security_group_ids = ["default"]
  }

  expect_failures = [var.security_group_ids]
}

run "an_unknown_container_insights_mode_is_rejected" {
  command = plan

  variables {
    container_insights = "on"
  }

  expect_failures = [var.container_insights]
}

run "an_unknown_exec_logging_mode_is_rejected" {
  command = plan

  variables {
    execute_command = { logging = "ALL" }
  }

  expect_failures = [var.execute_command]
}

run "exec_override_without_a_destination_is_rejected" {
  command = plan

  variables {
    execute_command = { logging = "OVERRIDE" }
  }

  expect_failures = [var.execute_command]
}

run "an_exec_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    execute_command = { kms_key_arn = "alias/exec" }
  }

  expect_failures = [var.execute_command]
}

run "a_multi_region_key_for_ephemeral_storage_is_rejected" {
  command = plan

  variables {
    fargate_ephemeral_storage_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/mrk-1234abcd12ab34cd56ef1234567890ab"
  }

  expect_failures = [var.fargate_ephemeral_storage_kms_key_arn]
}

run "a_managed_storage_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    managed_storage_kms_key_arn = "alias/ebs"
  }

  expect_failures = [var.managed_storage_kms_key_arn]
}

run "a_namespace_that_is_not_a_cloud_map_arn_is_rejected" {
  command = plan

  variables {
    service_connect_namespace_arn = "orders.local"
  }

  expect_failures = [var.service_connect_namespace_arn]
}

run "an_ec2_provider_key_with_capitals_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { General = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
  }

  expect_failures = [var.ec2_capacity_providers]
}

run "an_ec2_provider_named_like_a_preset_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { balanced = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
  }

  expect_failures = [var.ec2_capacity_providers]
}

run "an_ec2_provider_without_an_asg_arn_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "my-asg" } }
  }

  expect_failures = [var.ec2_capacity_providers]
}

run "an_ec2_provider_target_capacity_over_100_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g", managed_scaling = { target_capacity = 150 } } }
  }

  expect_failures = [var.ec2_capacity_providers]
}

run "a_retention_cloudwatch_does_not_offer_is_rejected" {
  command = plan

  variables {
    log_retention_days = 45
  }

  expect_failures = [var.log_retention_days]
}

run "a_log_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    log_kms_key_arn = "alias/logs"
  }

  expect_failures = [var.log_kms_key_arn]
}

run "a_global_secret_by_name_is_rejected" {
  command = plan

  variables {
    global_secrets = { DB = "orders/db" }
  }

  expect_failures = [var.global_secrets]
}

run "a_secrets_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    secrets_kms_key_arns = ["alias/secrets"]
  }

  expect_failures = [var.secrets_kms_key_arns]
}

run "a_boundary_that_is_not_a_policy_arn_is_rejected" {
  command = plan

  variables {
    permissions_boundary_arn = "boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}

run "an_infrastructure_role_arn_without_create_false_is_rejected" {
  command = plan

  variables {
    infrastructure_role = { arn = "arn:aws:iam::111122223333:role/infra" }
  }

  expect_failures = [var.infrastructure_role]
}

run "a_topic_that_is_not_an_sns_arn_is_rejected" {
  command = plan

  variables {
    sns_topic_arn = "alerts"
  }

  expect_failures = [var.sns_topic_arn]
}

run "a_topic_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    sns_topic_kms_key_arn = "alias/sns"
  }

  expect_failures = [var.sns_topic_kms_key_arn]
}

run "a_cpu_alarm_over_100_is_rejected" {
  command = plan

  variables {
    alarm_cpu_percent = 150
  }

  expect_failures = [var.alarm_cpu_percent]
}

run "a_memory_alarm_of_0_is_rejected" {
  command = plan

  variables {
    alarm_memory_percent = 0
  }

  expect_failures = [var.alarm_memory_percent]
}

run "an_exec_log_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    execute_command = { log_kms_key_arn = "alias/exec-logs" }
  }

  expect_failures = [var.execute_command]
}

run "an_environment_file_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    environment_files_kms_key_arns = ["alias/env"]
  }

  expect_failures = [var.environment_files_kms_key_arns]
}

run "a_trusted_bucket_account_that_is_not_an_id_is_rejected" {
  command = plan

  variables {
    trusted_s3_account_ids = ["prod"]
  }

  expect_failures = [var.trusted_s3_account_ids]
}
