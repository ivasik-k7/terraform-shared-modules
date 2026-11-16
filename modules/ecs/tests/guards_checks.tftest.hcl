# Every advisory check: the input that trips it, and the same input acknowledged.
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

run "a_service_without_rollback_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, deployment = { rollback = false } }
    }
  }

  expect_failures = [check.deployments_roll_back]
}

run "a_service_without_rollback_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, deployment = { rollback = false } }
    }
    acknowledged_checks = ["deployments_roll_back"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "deployments_roll_back")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_unpinned_image_warns" {
  command = plan

  variables {
    services = {
      api = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:latest", desired_count = 2 }
    }
  }

  expect_failures = [check.images_are_pinned]
}

run "an_unpinned_image_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:latest", desired_count = 2 }
    }
    acknowledged_checks = ["images_are_pinned"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "images_are_pinned")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "unbounded_log_retention_warns" {
  command = plan

  variables {
    log_retention_days = 0
  }

  expect_failures = [check.log_retention_is_bounded]
}

run "unbounded_log_retention_is_silent_once_acknowledged" {
  command = plan

  variables {
    log_retention_days  = 0
    acknowledged_checks = ["log_retention_is_bounded"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "log_retention_is_bounded")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "logs_without_a_customer_key_warn" {
  command = plan

  variables {
    log_kms_key_arn = ""
  }

  expect_failures = [check.logs_use_a_customer_key]
}

run "logs_without_a_customer_key_are_silent_once_acknowledged" {
  command = plan

  variables {
    log_kms_key_arn     = ""
    acknowledged_checks = ["logs_use_a_customer_key"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "logs_use_a_customer_key")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_single_task_service_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 1 }
    }
  }

  expect_failures = [check.services_survive_an_az]
}

run "a_single_task_service_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 1 }
    }
    acknowledged_checks = ["services_survive_an_az"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "services_survive_an_az")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "spot_with_no_on_demand_share_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, capacity = "spot_only" }
    }
  }

  expect_failures = [check.spot_services_keep_an_on_demand_floor]
}

run "spot_with_no_on_demand_share_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, capacity = "spot_only" }
    }
    acknowledged_checks = ["spot_services_keep_an_on_demand_floor"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "spot_services_keep_an_on_demand_floor")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "ecs_exec_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, enable_execute_command = true }
    }
  }

  expect_failures = [check.shell_access_is_intended]
}

run "ecs_exec_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, enable_execute_command = true }
    }
    acknowledged_checks = ["shell_access_is_intended"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "shell_access_is_intended")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "untagged_tasks_warn" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, propagate_tags = "NONE" }
    }
  }

  expect_failures = [check.task_costs_are_attributable]
}

run "untagged_tasks_are_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, propagate_tags = "NONE" }
    }
    acknowledged_checks = ["task_costs_are_attributable"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "task_costs_are_attributable")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "alarms_without_container_insights_warn" {
  command = plan

  variables {
    container_insights = "disabled"
  }

  expect_failures = [check.running_task_alarms_have_data]
}

run "alarms_without_container_insights_are_silent_once_acknowledged" {
  command = plan

  variables {
    container_insights  = "disabled"
    acknowledged_checks = ["running_task_alarms_have_data"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "running_task_alarms_have_data")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_topic_with_every_signal_off_warns" {
  command = plan

  variables {
    create_alarms      = false
    create_event_rules = false
  }

  expect_failures = [check.somebody_hears_a_failure]
}

run "a_topic_with_every_signal_off_is_silent_once_acknowledged" {
  command = plan

  variables {
    create_alarms       = false
    create_event_rules  = false
    acknowledged_checks = ["somebody_hears_a_failure"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "somebody_hears_a_failure")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_unrecorded_shell_warns" {
  command = plan

  variables {
    execute_command     = { logging = "NONE" }
    acknowledged_checks = ["shell_access_is_intended"]
    services = {
      api = { image = "r/a:1", desired_count = 2, enable_execute_command = true }
    }
  }

  expect_failures = [check.shell_sessions_are_recorded]
}

run "an_unrecorded_shell_is_silent_once_acknowledged" {
  command = plan

  variables {
    execute_command = { logging = "NONE" }
    services = {
      api = { image = "r/a:1", desired_count = 2, enable_execute_command = true }
    }
    acknowledged_checks = ["shell_access_is_intended", "shell_sessions_are_recorded"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "shell_sessions_are_recorded")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_privileged_daemon_warns" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      shipper = { workload = "daemon", launch = "EC2", network_mode = "bridge", containers = { s = { image = "r/a:1", privileged = true } } }
    }
  }

  expect_failures = [check.containers_stay_on_their_side]
}

run "a_privileged_daemon_is_silent_once_acknowledged" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      shipper = { workload = "daemon", launch = "EC2", network_mode = "bridge", containers = { s = { image = "r/a:1", privileged = true } } }
    }
    acknowledged_checks = ["containers_stay_on_their_side"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "containers_stay_on_their_side")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_administrator_task_role_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { managed_policies = { admin = "arn:aws:iam::aws:policy/AdministratorAccess" } } }
    }
  }

  expect_failures = [check.roles_are_not_administrators]
}

run "an_administrator_task_role_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { managed_policies = { admin = "arn:aws:iam::aws:policy/AdministratorAccess" } } }
    }
    acknowledged_checks = ["roles_are_not_administrators"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "roles_are_not_administrators")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "an_inline_wildcard_task_policy_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { policies = { all = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] }) } } }
    }
  }

  expect_failures = [check.roles_are_not_administrators]
}

run "an_inline_wildcard_task_policy_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { policies = { all = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "*", Resource = "*" }] }) } } }
    }
    acknowledged_checks = ["roles_are_not_administrators"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "roles_are_not_administrators")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_password_in_the_environment_warns" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, environment = { DB_PASSWORD = "hunter2" } }
    }
  }

  expect_failures = [check.secrets_are_not_in_environment]
}

run "a_password_in_the_environment_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, environment = { DB_PASSWORD = "hunter2" } }
    }
    acknowledged_checks = ["secrets_are_not_in_environment"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "secrets_are_not_in_environment")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}

run "a_schedule_without_a_dead_letter_queue_warns" {
  command = plan

  variables {
    services = {
      job = { image = "r/a:1", workload = "scheduled", schedule = { expression = "rate(1 day)" } }
    }
  }

  expect_failures = [check.failed_schedules_are_kept]
}

run "a_schedule_without_a_dead_letter_queue_is_silent_once_acknowledged" {
  command = plan

  variables {
    services = {
      job = { image = "r/a:1", workload = "scheduled", schedule = { expression = "rate(1 day)" } }
    }
    acknowledged_checks = ["failed_schedules_are_kept"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "failed_schedules_are_kept")
    error_message = "an acknowledged check is silent and listed in governance."
  }
}
