# Every validation of capacity, purchase options, replacement, scaling and signals, with the input that trips it.
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

run "a_negative_min_size_is_rejected" {
  command = plan

  variables {
    min_size = -1
  }

  expect_failures = [var.min_size]
}

run "max_below_min_is_rejected" {
  command = plan

  variables {
    min_size = 4
    max_size = 2
  }

  expect_failures = [var.max_size]
}

run "desired_above_max_is_rejected" {
  command = plan

  variables {
    desired_capacity = 9
  }

  expect_failures = [var.desired_capacity]
}

run "an_instance_lifetime_under_a_day_is_rejected" {
  command = plan

  variables {
    max_instance_lifetime = 3600
  }

  expect_failures = [var.max_instance_lifetime]
}

run "an_unknown_health_check_type_is_rejected" {
  command = plan

  variables {
    health_check_type = "HTTP"
  }

  expect_failures = [var.health_check_type]
}

run "a_negative_grace_period_is_rejected" {
  command = plan

  variables {
    health_check_grace_period = -5
  }

  expect_failures = [var.health_check_grace_period]
}

run "a_warmup_below_minus_one_is_rejected" {
  command = plan

  variables {
    default_instance_warmup = -2
  }

  expect_failures = [var.default_instance_warmup]
}

run "an_unknown_termination_policy_is_rejected" {
  command = plan

  variables {
    termination_policies = ["Random"]
  }

  expect_failures = [var.termination_policies]
}

run "an_unknown_suspended_process_is_rejected" {
  command = plan

  variables {
    suspended_processes = ["Rebalance"]
  }

  expect_failures = [var.suspended_processes]
}

run "a_target_group_that_is_not_an_arn_is_rejected" {
  command = plan

  variables {
    target_group_arns = ["web"]
  }

  expect_failures = [var.target_group_arns]
}

run "a_capacity_timeout_that_is_not_a_duration_is_rejected" {
  command = plan

  variables {
    wait_for_capacity_timeout = "ten minutes"
  }

  expect_failures = [var.wait_for_capacity_timeout]
}

run "half_a_maintenance_policy_is_rejected" {
  command = plan

  variables {
    instance_maintenance_policy = { min_healthy_percentage = 100 }
  }

  expect_failures = [var.instance_maintenance_policy]
}

run "a_maintenance_max_below_100_is_rejected" {
  command = plan

  variables {
    instance_maintenance_policy = { min_healthy_percentage = 50, max_healthy_percentage = 90 }
  }

  expect_failures = [var.instance_maintenance_policy]
}

run "an_on_demand_base_above_max_is_rejected" {
  command = plan

  variables {
    purchase_options = { on_demand_base_capacity = 9 }
  }

  expect_failures = [var.purchase_options]
}

run "spot_pools_without_lowest_price_are_rejected" {
  command = plan

  variables {
    purchase_options = { on_demand_percentage_above_base_capacity = 0, spot_instance_pools = 4 }
  }

  expect_failures = [var.purchase_options]
}

run "an_unknown_spot_strategy_is_rejected" {
  command = plan

  variables {
    purchase_options = { spot_allocation_strategy = "cheapest" }
  }

  expect_failures = [var.purchase_options]
}

run "refresh_checkpoints_out_of_order_are_rejected" {
  command = plan

  variables {
    instance_refresh = { checkpoint_percentages = [50, 25, 100] }
  }

  expect_failures = [var.instance_refresh]
}

run "refresh_checkpoints_not_ending_at_100_are_rejected" {
  command = plan

  variables {
    instance_refresh = { checkpoint_percentages = [25, 50] }
  }

  expect_failures = [var.instance_refresh]
}

run "refresh_alarms_without_rollback_are_rejected" {
  command = plan

  variables {
    instance_refresh = { auto_rollback = false, alarm_names = ["web-5xx"] }
  }

  expect_failures = [var.instance_refresh]
}

run "launch_template_as_a_refresh_trigger_is_rejected" {
  command = plan

  variables {
    instance_refresh = { triggers = ["launch_template"] }
  }

  expect_failures = [var.instance_refresh]
}

run "an_unknown_warm_pool_state_is_rejected" {
  command = plan

  variables {
    warm_pool = { enabled = true, pool_state = "Paused" }
  }

  expect_failures = [var.warm_pool]
}

run "an_initial_terminating_hook_is_rejected" {
  command = plan

  variables {
    lifecycle_hooks = { drain = { transition = "TERMINATING", initial = true } }
  }

  expect_failures = [var.lifecycle_hooks]
}

run "a_hook_target_without_a_role_is_rejected" {
  command = plan

  variables {
    lifecycle_hooks = { drain = { transition = "TERMINATING", notification_target_arn = "arn:aws:sqs:eu-west-2:111122223333:drain" } }
  }

  expect_failures = [var.lifecycle_hooks]
}

run "a_heartbeat_over_two_hours_is_rejected" {
  command = plan

  variables {
    lifecycle_hooks = { drain = { transition = "TERMINATING", heartbeat_timeout = 9000 } }
  }

  expect_failures = [var.lifecycle_hooks]
}

run "an_unknown_abandon_action_is_rejected" {
  command = plan

  variables {
    terminate_hook_abandon = "keep"
    lifecycle_hooks        = { drain = { transition = "TERMINATING" } }
  }

  expect_failures = [var.terminate_hook_abandon]
}

run "an_abandon_action_without_a_terminating_hook_is_rejected" {
  command = plan

  variables {
    terminate_hook_abandon = "retain"
  }

  expect_failures = [var.terminate_hook_abandon]
}

run "a_policy_with_both_metric_kinds_is_rejected" {
  command = plan

  variables {
    target_tracking_policies = { cpu = { target_value = 50, predefined_metric_type = "ASGAverageCPUUtilization", customized = { namespace = "N", metric_name = "M" } } }
  }

  expect_failures = [var.target_tracking_policies]
}

run "alb_request_tracking_without_a_label_is_rejected" {
  command = plan

  variables {
    target_tracking_policies = { req = { target_value = 500, predefined_metric_type = "ALBRequestCountPerTarget" } }
  }

  expect_failures = [var.target_tracking_policies]
}

run "predictive_scaling_on_alb_requests_without_a_label_is_rejected" {
  command = plan

  variables {
    predictive_scaling = { enabled = true, metric = "alb_requests" }
  }

  expect_failures = [var.predictive_scaling]
}

run "a_capacity_buffer_while_honoring_max_is_rejected" {
  command = plan

  variables {
    predictive_scaling = { enabled = true, max_capacity_buffer = 10 }
  }

  expect_failures = [var.predictive_scaling]
}

run "a_scheduled_action_that_changes_nothing_is_rejected" {
  command = plan

  variables {
    scheduled_actions = { noop = { recurrence = "0 7 * * *" } }
  }

  expect_failures = [var.scheduled_actions]
}

run "a_scheduled_action_with_no_time_is_rejected" {
  command = plan

  variables {
    scheduled_actions = { up = { min_size = 3 } }
  }

  expect_failures = [var.scheduled_actions]
}

run "a_time_zone_on_a_one_off_action_is_rejected" {
  command = plan

  variables {
    scheduled_actions = { up = { min_size = 3, start_time = "2026-12-01T08:00:00Z", time_zone = "Europe/London" } }
  }

  expect_failures = [var.scheduled_actions]
}

run "a_topic_that_is_not_an_arn_is_rejected" {
  command = plan

  variables {
    sns_topic_arn = "alerts"
  }

  expect_failures = [var.sns_topic_arn]
}

run "a_topic_key_that_is_not_a_key_is_rejected" {
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

run "an_in_service_floor_below_minus_one_is_rejected" {
  command = plan

  variables {
    alarm_min_in_service = -2
  }

  expect_failures = [var.alarm_min_in_service]
}

run "an_alarm_period_not_in_minutes_is_rejected" {
  command = plan

  variables {
    alarm_period = 90
  }

  expect_failures = [var.alarm_period]
}

run "zero_evaluation_periods_are_rejected" {
  command = plan

  variables {
    alarm_evaluation_periods = 0
  }

  expect_failures = [var.alarm_evaluation_periods]
}

run "an_alarm_action_that_is_not_an_arn_is_rejected" {
  command = plan

  variables {
    alarm_actions = ["ops"]
  }

  expect_failures = [var.alarm_actions]
}

run "six_ok_actions_are_rejected" {
  command = plan

  variables {
    ok_actions = ["arn:aws:sns:eu-west-2:111122223333:a", "arn:aws:sns:eu-west-2:111122223333:b", "arn:aws:sns:eu-west-2:111122223333:c", "arn:aws:sns:eu-west-2:111122223333:d", "arn:aws:sns:eu-west-2:111122223333:e", "arn:aws:sns:eu-west-2:111122223333:f"]
  }

  expect_failures = [var.ok_actions]
}
