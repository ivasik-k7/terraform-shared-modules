# Every validation of a workload's capacity, service, roles, scaling, schedule and signals, with the input that trips it.
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

run "an_unknown_capacity_preset_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, capacity = "cheap" }
    }
  }

  expect_failures = [var.services]
}

run "a_strategy_mixing_fargate_and_ec2_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", desired_count = 2, capacity_provider_strategy = [{ capacity_provider = "FARGATE" }, { capacity_provider = "general" }] }
    }
  }

  expect_failures = [var.services]
}

run "a_strategy_with_two_bases_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, capacity_provider_strategy = [{ capacity_provider = "FARGATE", base = 1 }, { capacity_provider = "FARGATE_SPOT", base = 1 }] }
    }
  }

  expect_failures = [var.services]
}

run "an_ec2_service_without_capacity_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2" }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_propagate_tags_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, propagate_tags = "ALL" }
    }
  }

  expect_failures = [var.services]
}

run "a_public_ip_without_allow_public_ip_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, assign_public_ip = true }
    }
  }

  expect_failures = [var.services]
}

run "rollback_without_a_circuit_breaker_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, deployment = { circuit_breaker = false } }
    }
  }

  expect_failures = [var.services]
}

run "a_negative_grace_period_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, health_check_grace_period_seconds = -1 }
    }
  }

  expect_failures = [var.services]
}

run "a_classic_load_balancer_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", port = 80, desired_count = 2, load_balancers = [{ target_group_arn = "my-elb" }] }
    }
  }

  expect_failures = [var.services]
}

run "a_load_balancer_on_an_unknown_container_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", port_mappings = [{ container_port = 80 }] } }, load_balancers = [{ target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/a/0123456789abcdef", container_name = "web" }] }
    }
  }

  expect_failures = [var.services]
}

run "service_connect_without_a_namespace_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", port = 80, desired_count = 2, service_connect = {} }
    }
  }

  expect_failures = [var.services]
}

run "service_connect_exposing_an_unknown_port_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", port = 80, desired_count = 2, service_connect = { namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-abcdef0123456789", expose = { grpc = {} } } }
    }
  }

  expect_failures = [var.services]
}

run "a_registry_that_is_not_a_cloud_map_service_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, service_discovery = { registry_arn = "orders" } }
    }
  }

  expect_failures = [var.services]
}

run "discovery_with_both_a_namespace_and_a_registry_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, service_discovery = { namespace_id = "ns-abcdef0123456789", registry_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:service/srv-abcdef0123456789" } }
    }
  }

  expect_failures = [var.services]
}

run "a_records_on_bridge_networking_are_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", port = 80, desired_count = 2, launch = "EC2", capacity = "general", network_mode = "bridge", service_discovery = { namespace_id = "ns-abcdef0123456789" } }
    }
  }

  expect_failures = [var.services]
}

run "srv_records_without_a_port_are_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, service_discovery = { namespace_id = "ns-abcdef0123456789", dns_record_type = "SRV" } }
    }
  }

  expect_failures = [var.services]
}

run "an_existing_log_group_without_a_name_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, log_group = { create = false } }
    }
  }

  expect_failures = [var.services]
}

run "retention_on_a_log_group_the_module_does_not_own_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, log_group = { create = false, name = "/shared/apps", retention_days = 30 } }
    }
  }

  expect_failures = [var.services]
}

run "a_retention_cloudwatch_does_not_offer_on_a_workload_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, log_group = { retention_days = 45 } }
    }
  }

  expect_failures = [var.services]
}

run "two_workloads_creating_one_log_group_are_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, log_group = { name = "/shared/apps" } }
      web = { image = "r/a:1", desired_count = 2, log_group = { name = "/shared/apps" } }
    }
  }

  expect_failures = [var.services]
}

run "a_workload_log_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, log_group = { kms_key_arn = "alias/logs" } }
    }
  }

  expect_failures = [var.services]
}

run "a_negative_running_task_floor_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, alarms = { min_running_tasks = -1 } }
    }
  }

  expect_failures = [var.services]
}

run "ignoring_task_definition_changes_on_a_task_workload_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", workload = "task", deployment = { ignore_task_definition_changes = true } }
    }
  }

  expect_failures = [var.services]
}

run "a_capacity_naming_an_unregistered_provider_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "managed" }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_placement_strategy_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "general", ordered_placement_strategy = [{ type = "pack" }] }
    }
  }

  expect_failures = [var.services]
}

run "a_role_arn_without_create_false_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { arn = "arn:aws:iam::111122223333:role/app" } }
    }
  }

  expect_failures = [var.services]
}

run "an_inline_policy_without_statements_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { policies = { read = "{}" } } }
    }
  }

  expect_failures = [var.services]
}

run "autoscaling_with_min_above_max_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", autoscaling = { min = 5, max = 2 } }
    }
  }

  expect_failures = [var.services]
}

run "autoscaling_with_nothing_to_scale_on_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", autoscaling = { min = 2, max = 4, cpu_target = 0 } }
    }
  }

  expect_failures = [var.services]
}

run "a_scaling_schedule_that_is_not_an_expression_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", autoscaling = { min = 2, max = 4, schedules = { night = { schedule = "0 20 * * *", min = 1, max = 2 } } } }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_custom_metric_statistic_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", autoscaling = { min = 2, max = 4, custom = { q = { target_value = 1, namespace = "N", metric_name = "M", statistic = "p99" } } } }
    }
  }

  expect_failures = [var.services]
}

run "a_schedule_with_eleven_tasks_is_rejected" {
  command = plan

  variables {
    services = {
      job = { image = "r/a:1", workload = "scheduled", schedule = { expression = "rate(1 day)", task_count = 11 } }
    }
  }

  expect_failures = [var.services]
}

run "a_dead_letter_key_without_a_queue_is_rejected" {
  command = plan

  variables {
    services = {
      job = { image = "r/a:1", workload = "scheduled", schedule = { expression = "rate(1 day)", dead_letter_queue_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555" } }
    }
  }

  expect_failures = [var.services]
}

run "an_inline_policy_named_like_the_modules_own_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, task_role = { policies = { ecs-module = "{\"Statement\":[]}" } } }
    }
  }

  expect_failures = [var.services]
}

run "a_service_alarm_over_100_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, alarms = { cpu_percent = 101 } }
    }
  }

  expect_failures = [var.services]
}
