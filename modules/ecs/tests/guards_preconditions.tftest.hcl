# Every precondition, with the input that trips it.
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

run "a_missing_required_tag_fails_the_plan" {
  command = plan

  variables {
    required_tag_keys = ["Owner"]
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "an_external_default_capacity_that_is_not_registered_fails_the_plan" {
  command = plan

  variables {
    default_capacity = "managed"
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "an_empty_required_tag_fails_the_plan" {
  command = plan

  variables {
    required_tag_keys = ["Owner"]
    tags              = { CostCenter = "cc-1", Environment = "test", Owner = "" }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "a_default_capacity_that_is_neither_preset_nor_provider_fails_the_plan" {
  command = plan

  variables {
    default_capacity = "general"
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "an_awsvpc_workload_with_no_subnets_fails_the_plan" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "capacity_on_a_daemon_fails_the_plan" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      shipper = { image = "r/a:1", workload = "daemon", launch = "EC2", network_mode = "bridge", capacity = "general" }
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "volumes_on_the_image_shortcut_fail_the_plan" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, volumes = { v = {} } }
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "exec_into_a_read_only_root_fails_the_plan" {
  command = plan

  variables {
    acknowledged_checks = ["shell_access_is_intended"]
    services = {
      api = { desired_count = 2, enable_execute_command = true, containers = { app = { image = "r/a:1", readonly_root_filesystem = true } } }
    }
  }

  expect_failures = [aws_ecs_cluster.this]
}

run "a_scheduled_strategy_over_six_entries_fails_the_plan" {
  command = plan

  variables {
    services = {
      job = { image = "r/a:1", workload = "scheduled", schedule = { expression = "rate(1 day)", dead_letter_queue_arn = "arn:aws:sqs:eu-west-2:111122223333:dlq" }, capacity_provider_strategy = [{ capacity_provider = "FARGATE" }, { capacity_provider = "FARGATE" }, { capacity_provider = "FARGATE" }, { capacity_provider = "FARGATE" }, { capacity_provider = "FARGATE_SPOT" }, { capacity_provider = "FARGATE_SPOT" }, { capacity_provider = "FARGATE_SPOT" }] }
    }
  }

  expect_failures = [aws_scheduler_schedule.this["job"]]
}
