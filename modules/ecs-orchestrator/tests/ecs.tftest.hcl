# plan-only checks, no creds needed. `terraform test`

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Fargate single-container shortcut --------------------------------------
run "fargate_basic" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    services = {
      web = {
        image                      = "nginx:alpine"
        port                       = 80
        capacity_provider_strategy = [{ capacity_provider = "FARGATE", weight = 1, base = 1 }]
      }
    }
  }

  assert {
    condition     = aws_ecs_cluster.this[0].name == "test"
    error_message = "Cluster name should match"
  }

  assert {
    condition     = length(aws_ecs_service.static) == 1 && length(aws_ecs_service.autoscaled) == 0
    error_message = "One static service expected"
  }

  assert {
    condition     = aws_ecs_task_definition.this["web"].network_mode == "awsvpc"
    error_message = "Default network mode should be awsvpc"
  }

  assert {
    condition     = can(regex("nginx:alpine", aws_ecs_task_definition.this["web"].container_definitions))
    error_message = "Container definitions should include the image"
  }

  assert {
    condition     = length(aws_iam_role.execution) == 1
    error_message = "Shared execution role should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.service) == 1
    error_message = "A log group should be created for the service"
  }
}

# --- Fargate + Fargate Spot registered by default ----------------------------
run "fargate_capacity_providers_default" {
  command = plan

  variables {
    cluster_name = "test"
    services     = {}
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "FARGATE") && contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "FARGATE_SPOT")
    error_message = "Fargate providers should be registered by default"
  }
}

# --- EC2 capacity provider created from an ASG ARN + registered --------------
run "ec2_capacity_provider" {
  command = plan

  variables {
    cluster_name = "test"
    ec2_capacity_providers = {
      ec2-od = {
        auto_scaling_group_arn = "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:uuid:autoScalingGroupName/my-asg"
      }
    }
    services = {}
  }

  assert {
    condition     = length(aws_ecs_capacity_provider.ec2) == 1
    error_message = "One EC2 capacity provider should be created"
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "ec2-od")
    error_message = "The EC2 provider should be registered on the cluster"
  }
}

# --- Mixed Fargate + EC2 strategy on one service ----------------------------
run "mixed_launch_types" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    ec2_capacity_providers = {
      ec2-od = { auto_scaling_group_arn = "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:uuid:autoScalingGroupName/my-asg" }
    }
    services = {
      web = {
        image                    = "nginx:alpine"
        port                     = 80
        requires_compatibilities = ["FARGATE", "EC2"]
        capacity_provider_strategy = [
          { capacity_provider = "FARGATE", weight = 1, base = 1 },
          { capacity_provider = "ec2-od", weight = 3, base = 0 },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.static["web"].capacity_provider_strategy) == 2
    error_message = "Service should carry a two-provider strategy"
  }
}

# --- EC2 provider without EC2 compatibility is rejected ---------------------
run "ec2_provider_without_ec2_compat_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image                      = "nginx:alpine"
        capacity_provider_strategy = [{ capacity_provider = "ec2-od", weight = 1 }]
        # requires_compatibilities defaults to ["FARGATE"] -> invalid for EC2
      }
    }
  }
  expect_failures = [var.services]
}

# --- Multi-container task ----------------------------------------------------
run "multi_container" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      app = {
        cpu    = 512
        memory = 1024
        containers = {
          app = { image = "myapp:1", port_mappings = [{ container_port = 8080 }] }
          xray = {
            image         = "amazon/aws-xray-daemon"
            essential     = false
            port_mappings = [{ container_port = 2000, protocol = "udp" }]
          }
        }
      }
    }
  }

  assert {
    condition     = can(regex("aws-xray-daemon", aws_ecs_task_definition.this["app"].container_definitions))
    error_message = "Both containers should be in the task definition"
  }
}

# --- Secrets produce a scoped execution-role read policy --------------------
run "secrets_policy" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image   = "nginx:alpine"
        secrets = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-abc" }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.execution_secrets) == 1
    error_message = "A scoped secrets read policy should be attached to the execution role"
  }
}

# --- Autoscaling: service goes to the autoscaled set + target/policy ---------
run "autoscaling" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image       = "nginx:alpine"
        autoscaling = { min_capacity = 2, max_capacity = 10, cpu_target = 60 }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.autoscaled) == 1 && length(aws_ecs_service.static) == 0
    error_message = "Service should be in the autoscaled set"
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1 && length(aws_appautoscaling_policy.cpu) == 1
    error_message = "Autoscaling target + CPU policy should be planned"
  }
}

# --- custom-metric autoscaling (e.g. SQS queue depth for a worker) -----------
run "autoscaling_custom_metric" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      worker = {
        image = "myworker:1"
        autoscaling = {
          min_capacity = 1
          max_capacity = 50
          custom_metric = {
            namespace    = "AWS/SQS"
            metric_name  = "ApproximateNumberOfMessagesVisible"
            dimensions   = { QueueName = "orders" }
            target_value = 100
          }
        }
      }
    }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.custom) == 1 && length(aws_appautoscaling_policy.cpu) == 0
    error_message = "A custom-metric scaling policy (only) should be planned"
  }

  assert {
    condition     = aws_appautoscaling_policy.custom["worker"].target_tracking_scaling_policy_configuration[0].customized_metric_specification[0].metric_name == "ApproximateNumberOfMessagesVisible"
    error_message = "Custom metric name should flow into the policy"
  }
}

# --- deployment auto-rollback on external CloudWatch alarms -------------------
run "deployment_alarms" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image = "nginx:alpine"
        deployment_alarms = {
          alarm_names = ["web-5xx-high"]
          rollback    = true
        }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.static["web"].alarms) == 1
    error_message = "The service should carry a deployment alarms block"
  }
}

# --- Cloud Map service discovery --------------------------------------------
run "service_discovery" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image             = "nginx:alpine"
        service_discovery = { namespace_id = "ns-abc123" }
      }
    }
  }

  assert {
    condition     = length(aws_service_discovery_service.this) == 1
    error_message = "A Cloud Map service should be created"
  }
}

# --- CloudWatch alarms per service ------------------------------------------
run "cloudwatch_alarms" {
  command = plan

  variables {
    cluster_name              = "test"
    default_subnets           = ["subnet-aaaa1111"]
    create_cloudwatch_alarms  = true
    enable_container_insights = true
    services = {
      web = { image = "nginx:alpine" }
    }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1 && length(aws_cloudwatch_metric_alarm.memory_high) == 1
    error_message = "CPU + memory alarms should be created per service"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.running_tasks_low) == 1
    error_message = "RunningTaskCount alarm should be created when Container Insights is on"
  }
}

# --- RunningTaskCount alarm requires Container Insights ----------------------
run "alarms_without_insights_skip_running_count" {
  command = plan

  variables {
    cluster_name             = "test"
    default_subnets          = ["subnet-aaaa1111"]
    create_cloudwatch_alarms = true
    services                 = { web = { image = "nginx:alpine" } }
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1 && length(aws_cloudwatch_metric_alarm.running_tasks_low) == 0
    error_message = "Running-task alarm needs Container Insights; CPU alarm still created"
  }
}

# --- Per-service managed security group -------------------------------------
run "service_security_group" {
  command = plan

  variables {
    cluster_name    = "test"
    vpc_id          = "vpc-12345678"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image                 = "nginx:alpine"
        create_security_group = true
      }
    }
  }

  assert {
    condition     = length(aws_security_group.service) == 1
    error_message = "A service security group should be created"
  }
}

# --- create = false builds nothing ------------------------------------------
run "create_false" {
  command = plan

  variables {
    create          = false
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services        = { web = { image = "nginx:alpine" } }
  }

  assert {
    condition     = length(aws_ecs_cluster.this) == 0 && length(aws_ecs_service.static) == 0 && length(aws_ecs_task_definition.this) == 0
    error_message = "create=false should build nothing"
  }
}

# --- No strategy + no cluster default still gets a launch type (Fargate) -----
run "default_fargate_strategy" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = { image = "nginx:alpine" } # no capacity_provider_strategy at all
    }
  }

  assert {
    condition     = length(aws_ecs_service.static["web"].capacity_provider_strategy) == 1
    error_message = "A service with no strategy should default to Fargate so it has a launch type"
  }
}

# --- ECS Exec grants the task role the SSM messages channel -----------------
run "exec_task_role_policy" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = { image = "nginx:alpine", enable_execute_command = true }
    }
  }

  assert {
    condition     = length(aws_iam_role_policy.task_exec) == 1
    error_message = "Enabling ECS Exec should attach the ssmmessages policy to the task role"
  }
}

# --- launch_type = EC2 (standalone instances, no capacity provider) ---------
run "launch_type_ec2" {
  command = plan

  variables {
    cluster_name = "test"
    services = {
      worker = {
        launch_type              = "EC2"
        requires_compatibilities = ["EC2"]
        network_mode             = "bridge"
        image                    = "busybox"
      }
    }
  }

  assert {
    condition     = aws_ecs_service.static["worker"].launch_type == "EC2"
    error_message = "launch_type should be set on the service"
  }

  assert {
    condition     = length(aws_ecs_service.static["worker"].capacity_provider_strategy) == 0
    error_message = "No capacity provider strategy should be emitted with a plain launch_type"
  }
}

# --- Fargate Spot strategy + scheduled autoscaling --------------------------
run "fargate_spot_scheduled_autoscaling" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        cpu    = 512
        memory = 1024
        image  = "nginx:alpine"
        port   = 8080
        capacity_provider_strategy = [
          { capacity_provider = "FARGATE", weight = 1, base = 1 },
          { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 },
        ]
        autoscaling = {
          min_capacity = 2
          max_capacity = 20
          cpu_target   = 60
          scheduled = {
            night = { schedule = "cron(0 2 * * ? *)", min_capacity = 1, max_capacity = 4 }
            day   = { schedule = "cron(0 7 * * ? *)", min_capacity = 2, max_capacity = 20 }
          }
        }
      }
    }
  }

  assert {
    condition     = length([for s in aws_ecs_service.autoscaled["web"].capacity_provider_strategy : s if s.capacity_provider == "FARGATE_SPOT"]) == 1
    error_message = "FARGATE_SPOT should be one of the two capacity providers on the service"
  }

  assert {
    condition     = length(aws_appautoscaling_scheduled_action.this) == 2
    error_message = "Two scheduled scaling actions (day + night) should be planned"
  }
}

# --- Multi-service Service Connect mesh over the cluster namespace -----------
run "service_connect_mesh" {
  command = plan

  variables {
    cluster_name              = "test"
    default_subnets           = ["subnet-aaaa1111"]
    service_connect_namespace = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-mesh"
    services = {
      edge = {
        image           = "nginx:alpine"
        port            = 8080
        service_connect = { services = [{ port_name = "edge", client_alias = { dns_name = "edge", port = 8080 } }] }
      }
      api = {
        cpu    = 512
        memory = 1024
        containers = {
          api = { image = "myapp:1", port_mappings = [{ container_port = 8080, name = "api" }] }
        }
        service_connect = { services = [{ port_name = "api", discovery_name = "api", client_alias = { dns_name = "api", port = 8080 } }] }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.static) == 2
    error_message = "Both mesh services should be planned"
  }

  assert {
    condition     = length(aws_ecs_service.static["edge"].service_connect_configuration) == 1 && length(aws_ecs_service.static["api"].service_connect_configuration) == 1
    error_message = "Every mesh service should carry a service_connect_configuration block"
  }
}

# --- awsvpc service falls back to default_security_group_ids -----------------
run "default_security_group_fallback" {
  command = plan

  variables {
    cluster_name               = "test"
    default_subnets            = ["subnet-aaaa1111"]
    default_security_group_ids = ["sg-default01"]
    services = {
      web = { image = "nginx:alpine" } # no per-service security_groups
    }
  }

  assert {
    condition     = contains(aws_ecs_service.static["web"].network_configuration[0].security_groups, "sg-default01")
    error_message = "awsvpc service with no SG of its own should use default_security_group_ids"
  }
}

# --- Managed EBS volume attached at launch ----------------------------------
run "managed_ebs_volume" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      db = {
        cpu    = 512
        memory = 1024
        image  = "postgres:16"
        volumes = {
          data = { configure_at_launch = true }
        }
        managed_ebs_volume = {
          name       = "data"
          role_arn   = "arn:aws:iam::123456789012:role/ecs-infra"
          size_in_gb = 20
        }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_service.static["db"].volume_configuration) == 1
    error_message = "A managed EBS volume_configuration should be emitted on the service"
  }
}

# --- Memory-target autoscaling + ALB-request target -------------------------
run "autoscaling_memory_and_requests" {
  command = plan

  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image = "nginx:alpine"
        autoscaling = {
          min_capacity       = 2
          max_capacity       = 10
          memory_target      = 70
          alb_request_target = 1000
          alb_resource_label = "app/my-alb/abc/targetgroup/tg/def"
        }
      }
    }
  }

  assert {
    condition     = length(aws_appautoscaling_policy.memory) == 1 && length(aws_appautoscaling_policy.alb_requests) == 1
    error_message = "Memory and ALB-request scaling policies should both be planned"
  }
}

# --- BYO execution role: no shared role created -----------------------------
run "byo_execution_role" {
  command = plan

  variables {
    cluster_name            = "test"
    default_subnets         = ["subnet-aaaa1111"]
    task_execution_role_arn = "arn:aws:iam::123456789012:role/my-exec-role"
    services                = { web = { image = "nginx:alpine" } }
  }

  assert {
    condition     = length(aws_iam_role.execution) == 0
    error_message = "No shared execution role should be created when one is supplied"
  }
}

# --- CMK-encrypted secrets add kms:Decrypt to the exec policy ---------------
run "secrets_kms_decrypt" {
  command = plan

  variables {
    cluster_name         = "test"
    default_subnets      = ["subnet-aaaa1111"]
    secrets_kms_key_arns = ["arn:aws:kms:us-east-1:123456789012:key/abcd-ef01"]
    services = {
      web = {
        image   = "nginx:alpine"
        secrets = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-abc" }
      }
    }
  }

  assert {
    condition     = can(regex("kms:Decrypt", aws_iam_role_policy.execution_secrets[0].policy))
    error_message = "kms:Decrypt should be present when secrets_kms_key_arns is set"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "mount_point_unknown_volume_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        cpu    = 256
        memory = 512
        containers = {
          web = { image = "nginx", mount_points = [{ source_volume = "missing", container_path = "/data" }] }
        }
      }
    }
  }
  expect_failures = [var.services]
}

run "lb_container_mismatch_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        cpu    = 256
        memory = 512
        containers = {
          web = { image = "nginx", port_mappings = [{ container_port = 80 }] }
        }
        load_balancers = [{ target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/tg/abc", container_name = "nope", container_port = 80 }]
      }
    }
  }
  expect_failures = [var.services]
}

run "managed_ebs_without_volume_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      db = {
        cpu                = 256
        memory             = 512
        image              = "postgres:16"
        managed_ebs_volume = { name = "data", role_arn = "arn:aws:iam::123456789012:role/r" }
        # no volumes { data = { configure_at_launch = true } } -> invalid
      }
    }
  }
  expect_failures = [var.services]
}

run "awsvpc_without_subnets_fails" {
  command = plan
  variables {
    cluster_name = "test"
    # no default_subnets, service is awsvpc by default
    services = { web = { image = "nginx" } }
  }
  expect_failures = [var.services]
}

run "launch_type_ec2_without_compat_fails" {
  command = plan
  variables {
    cluster_name = "test"
    services = {
      web = {
        launch_type  = "EC2"
        network_mode = "bridge"
        image        = "nginx"
        # requires_compatibilities defaults to ["FARGATE"] -> invalid for EC2 launch_type
      }
    }
  }
  expect_failures = [var.services]
}

run "invalid_launch_type_fails" {
  command = plan
  variables {
    cluster_name = "test"
    services     = { web = { image = "nginx", launch_type = "SPOT" } }
  }
  expect_failures = [var.services]
}

run "invalid_exec_logging_fails" {
  command = plan
  variables {
    cluster_name                  = "test"
    execute_command_configuration = { logging = "VERBOSE" }
    services                      = {}
  }
  expect_failures = [var.execute_command_configuration]
}

run "service_connect_without_namespace_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    # no cluster service_connect_namespace, and none per-service
    services = {
      web = {
        image           = "nginx:alpine"
        service_connect = { services = [] }
      }
    }
  }
  expect_failures = [var.services]
}

run "launch_type_and_strategy_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image                      = "nginx"
        launch_type                = "FARGATE"
        capacity_provider_strategy = [{ capacity_provider = "FARGATE" }]
      }
    }
  }
  expect_failures = [var.services]
}

run "no_essential_container_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        cpu    = 256
        memory = 512
        containers = {
          a = { image = "x", essential = false }
          b = { image = "y", essential = false }
        }
      }
    }
  }
  expect_failures = [var.services]
}

run "invalid_ephemeral_storage_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services        = { web = { image = "nginx", ephemeral_storage_gib = 10 } }
  }
  expect_failures = [var.services]
}

run "no_container_definition_fails" {
  command = plan
  variables {
    cluster_name = "test"
    services     = { web = { cpu = 256, memory = 512 } }
  }
  expect_failures = [var.services]
}

run "fargate_invalid_cpu_memory_fails" {
  command = plan
  variables {
    cluster_name = "test"
    services     = { web = { image = "nginx", cpu = 256, memory = 4096 } } # 256 cpu maxes at 2048
  }
  expect_failures = [var.services]
}

run "invalid_network_mode_fails" {
  command = plan
  variables {
    cluster_name = "test"
    services     = { web = { image = "nginx", network_mode = "overlay" } }
  }
  expect_failures = [var.services]
}

run "bad_asg_arn_fails" {
  command = plan
  variables {
    cluster_name           = "test"
    ec2_capacity_providers = { ec2 = { auto_scaling_group_arn = "not-an-arn" } }
    services               = {}
  }
  expect_failures = [var.ec2_capacity_providers]
}

run "invalid_cluster_name_fails" {
  command = plan
  variables {
    cluster_name = "bad name!"
    services     = {}
  }
  expect_failures = [var.cluster_name]
}

run "invalid_retention_fails" {
  command = plan
  variables {
    cluster_name       = "test"
    log_retention_days = 13
    services           = {}
  }
  expect_failures = [var.log_retention_days]
}

run "autoscaling_min_gt_max_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image       = "nginx"
        autoscaling = { min_capacity = 10, max_capacity = 5 }
      }
    }
  }
  expect_failures = [var.services]
}

run "autoscaling_scheduled_min_gt_max_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image = "nginx"
        autoscaling = {
          min_capacity = 1
          max_capacity = 10
          scheduled    = { night = { schedule = "cron(0 2 * * ? *)", min_capacity = 8, max_capacity = 4 } }
        }
      }
    }
  }
  expect_failures = [var.services]
}

run "autoscaling_alb_without_label_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image       = "nginx"
        autoscaling = { min_capacity = 1, max_capacity = 10, alb_request_target = 1000 }
      }
    }
  }
  expect_failures = [var.services]
}

# X1: shortcut + containers together
run "shortcut_and_containers_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image      = "nginx" # shortcut...
        containers = { web = { image = "nginx" } }
      }
    }
  }
  expect_failures = [var.services]
}

# X2a: strategy references an unregistered capacity provider
run "unregistered_capacity_provider_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image                    = "nginx"
        requires_compatibilities = ["EC2"]
        capacity_provider_strategy = [
          { capacity_provider = "does-not-exist", weight = 1 },
        ]
      }
    }
  }
  expect_failures = [var.services]
}

# X2b: non-Fargate task with no launch_type / strategy / cluster default
run "non_fargate_without_capacity_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      worker = {
        image                    = "busybox"
        network_mode             = "bridge"
        requires_compatibilities = ["EC2"] # no launch_type, no strategy, no cluster default
      }
    }
  }
  expect_failures = [var.services]
}

run "deployment_alarms_wrong_controller_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image                 = "nginx"
        deployment_controller = "CODE_DEPLOY"
        deployment_alarms     = { alarm_names = ["x"] }
      }
    }
  }
  expect_failures = [var.services]
}

run "deployment_alarms_empty_names_fails" {
  command = plan
  variables {
    cluster_name    = "test"
    default_subnets = ["subnet-aaaa1111"]
    services = {
      web = {
        image             = "nginx"
        deployment_alarms = { alarm_names = [] }
      }
    }
  }
  expect_failures = [var.services]
}
