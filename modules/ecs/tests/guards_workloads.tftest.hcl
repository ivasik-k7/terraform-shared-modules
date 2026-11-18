# Every validation of a workload's shape, containers, size and volumes, with the input that trips it.
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

run "a_service_key_with_capitals_is_rejected" {
  command = plan

  variables {
    services = {
      Api = { image = "r/a:1", desired_count = 2 }
    }
  }

  expect_failures = [var.services]
}

run "a_service_key_too_long_for_its_role_name_is_rejected" {
  command = plan

  variables {
    name = "a-cluster-name-of-thirty-chars"
    services = {
      a-service-key-of-thirty-two-char = { image = "r/a:1", desired_count = 2 }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_workload_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, workload = "batch" }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_launch_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EXTERNAL" }
    }
  }

  expect_failures = [var.services]
}

run "a_daemon_on_fargate_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", workload = "daemon" }
    }
  }

  expect_failures = [var.services]
}

run "a_scheduled_workload_without_a_schedule_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", workload = "scheduled" }
    }
  }

  expect_failures = [var.services]
}

run "a_schedule_on_a_service_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, schedule = { expression = "rate(1 day)" } }
    }
  }

  expect_failures = [var.services]
}

run "autoscaling_on_a_task_workload_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", workload = "task", autoscaling = { max = 2 } }
    }
  }

  expect_failures = [var.services]
}

run "a_load_balancer_on_a_task_workload_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", port = 80, workload = "task", load_balancers = [{ target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/a/0123456789abcdef" }] }
    }
  }

  expect_failures = [var.services]
}

run "a_negative_desired_count_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = -1 }
    }
  }

  expect_failures = [var.services]
}

run "neither_image_nor_containers_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2 }
    }
  }

  expect_failures = [var.services]
}

run "both_image_and_containers_are_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, containers = { app = { image = "r/a:1" } } }
    }
  }

  expect_failures = [var.services]
}

run "shortcut_fields_beside_containers_are_rejected" {
  command = plan

  variables {
    services = {
      api = { port = 80, desired_count = 2, containers = { app = { image = "r/a:1" } } }
    }
  }

  expect_failures = [var.services]
}

run "a_task_with_no_essential_container_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", essential = false } } }
    }
  }

  expect_failures = [var.services]
}

run "a_container_name_with_a_dot_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { "app.v1" = { image = "r/a:1" } } }
    }
  }

  expect_failures = [var.services]
}

run "depends_on_an_unknown_container_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", depends_on = { db = "START" } } } }
    }
  }

  expect_failures = [var.services]
}

run "volumes_from_an_unknown_container_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", volumes_from = [{ source_container = "db" }] } } }
    }
  }

  expect_failures = [var.services]
}

run "a_mount_of_an_unknown_volume_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", mount_points = [{ source_volume = "data", container_path = "/d" }] } } }
    }
  }

  expect_failures = [var.services]
}

run "an_sctp_port_mapping_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", port_mappings = [{ container_port = 80, protocol = "sctp" }] } } }
    }
  }

  expect_failures = [var.services]
}

run "a_shortcut_port_over_65535_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, port = 70000 }
    }
  }

  expect_failures = [var.services]
}

run "firelens_logging_without_a_router_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", log_driver = "awsfirelens" } } }
    }
  }

  expect_failures = [var.services]
}

run "a_secret_by_name_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, secrets = { DB = "orders/db" } }
    }
  }

  expect_failures = [var.services]
}

run "an_environment_file_that_is_not_an_s3_env_object_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", environment_files = ["s3://bucket/app.env"] } } }
    }
  }

  expect_failures = [var.services]
}

run "repository_credentials_that_are_not_a_secret_are_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", repository_credentials_arn = "arn:aws:ssm:eu-west-2:111122223333:parameter/x" } } }
    }
  }

  expect_failures = [var.services]
}

run "a_fargate_size_fargate_does_not_offer_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, cpu = 256, memory = 4096 }
    }
  }

  expect_failures = [var.services]
}

run "an_ec2_task_below_128_units_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "general", cpu = 64, memory = 128 }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_cpu_architecture_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, cpu_architecture = "ARM" }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_operating_system_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, operating_system_family = "WINDOWS" }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_network_mode_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "general", network_mode = "nat" }
    }
  }

  expect_failures = [var.services]
}

run "bridge_networking_on_fargate_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, network_mode = "bridge" }
    }
  }

  expect_failures = [var.services]
}

run "a_privileged_container_on_fargate_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1", privileged = true } } }
    }
  }

  expect_failures = [var.services]
}

run "ephemeral_storage_below_21_gib_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, ephemeral_storage_gib = 10 }
    }
  }

  expect_failures = [var.services]
}

run "an_unknown_pid_mode_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, pid_mode = "container" }
    }
  }

  expect_failures = [var.services]
}

run "a_host_pid_mode_on_fargate_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, pid_mode = "host" }
    }
  }

  expect_failures = [var.services]
}

run "an_ipc_mode_on_fargate_is_rejected" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, ipc_mode = "host" }
    }
  }

  expect_failures = [var.services]
}

run "a_volume_of_two_kinds_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services = {
      api = { desired_count = 2, launch = "EC2", capacity = "general", containers = { app = { image = "r/a:1" } }, volumes = { v = { host_path = "/x", docker = {} } } }
    }
  }

  expect_failures = [var.services]
}

run "efs_iam_authorisation_without_tls_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1" } }, volumes = { v = { efs = { file_system_id = "fs-0123456789abcdef0", transit_encryption = false } } } }
    }
  }

  expect_failures = [var.services]
}

run "a_managed_ebs_volume_naming_no_launch_volume_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1" } }, volumes = { v = {} }, managed_ebs_volume = { volume_name = "v", size_in_gb = 10 } }
    }
  }

  expect_failures = [var.services]
}

run "a_launch_volume_without_a_managed_ebs_volume_is_rejected" {
  command = plan

  variables {
    services = {
      api = { desired_count = 2, containers = { app = { image = "r/a:1" } }, volumes = { v = { configure_at_launch = true } } }
    }
  }

  expect_failures = [var.services]
}
