# Properties of the rendered configuration, one run per property. The baseline
# is a fully configured module, so its own advisory checks pass.
#
# What a mock cannot show: replacement (mock_provider never reports
# RequiresReplace), AWS accepting a request, or ECS's answer to a container
# definition. Where a property rests on those, the run says so.

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
    api = {
      image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
      port          = 8080
      desired_count = 2
    }
  }
}

# ---------------------------------------------------------------------------
# Containers
# ---------------------------------------------------------------------------

run "the_image_shortcut_is_one_container_named_after_the_service" {
  command = plan

  assert {
    condition     = length(jsondecode(aws_ecs_task_definition.this["api"].container_definitions)) == 1
    error_message = "the shortcut renders exactly one container."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].name == "api"
    error_message = "the shortcut container is named after the service key."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].portMappings == [{ containerPort = 8080, protocol = "tcp", name = "api" }]
    error_message = "the shortcut port is one tcp mapping named after the service, so Service Connect and load balancers can find it."
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].logConfiguration == {
      logDriver = "awslogs"
      options   = { "awslogs-group" = "/ecs/orders/api", "awslogs-region" = "eu-west-2", "awslogs-stream-prefix" = "api" }
    }
    error_message = "containers log to the module's log group for the service, in the cluster's region."
  }
}

# ECS leaves empty and zero values out of DescribeTaskDefinition, and the
# provider compares the two; anything sent empty would diff on every plan.
run "empty_and_zero_container_fields_are_not_sent" {
  command = plan

  variables {
    services = {
      api = {
        desired_count = 2
        containers = {
          app = {
            image        = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
            health_check = { command = ["CMD-SHELL", "true"] }
          }
        }
      }
    }
  }

  assert {
    condition = length(setintersection(keys(jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0]), [
      "cpu", "memory", "memoryReservation", "command", "entryPoint", "workingDirectory", "user", "environment", "secrets",
      "environmentFiles", "portMappings", "mountPoints", "volumesFrom", "dependsOn", "linuxParameters", "ulimits",
      "dockerLabels", "startTimeout", "stopTimeout", "repositoryCredentials", "firelensConfiguration", "privileged",
    ])) == 0
    error_message = "a container with only an image and a health check sends no empty or zero fields."
  }

  assert {
    condition     = !contains(keys(jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].healthCheck), "startPeriod")
    error_message = "a zero start_period is left out of the health check."
  }
}

run "global_environment_and_secrets_reach_every_container_and_lose_a_clash" {
  command = plan

  variables {
    global_environment = { APP_ENV = "test", REGION = "eu-west-2" }
    global_secrets     = { DB = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-AbCdEf" }
    services = {
      api = {
        desired_count = 2
        containers = {
          app     = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0", environment = { APP_ENV = "override" } }
          sidecar = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/proxy:1.0.0", essential = false }
        }
      }
    }
  }

  assert {
    condition = [for c in jsondecode(aws_ecs_task_definition.this["api"].container_definitions) : c.environment] == [
      [{ name = "APP_ENV", value = "override" }, { name = "REGION", value = "eu-west-2" }],
      [{ name = "APP_ENV", value = "test" }, { name = "REGION", value = "eu-west-2" }],
    ]
    error_message = "every container gets global_environment, and a container's own value wins."
  }

  assert {
    condition     = alltrue([for c in jsondecode(aws_ecs_task_definition.this["api"].container_definitions) : c.secrets == [{ name = "DB", valueFrom = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-AbCdEf" }]])
    error_message = "every container gets global_secrets."
  }
}

run "a_full_container_renders_every_field_ecs_expects" {
  command = plan

  variables {
    services = {
      api = {
        desired_count = 2
        containers = {
          app = {
            image                    = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
            cpu                      = 256
            memory                   = 512
            memory_reservation       = 256
            command                  = ["serve"]
            entrypoint               = ["/init"]
            working_directory        = "/srv"
            user                     = "1000"
            port_mappings            = [{ container_port = 8080, name = "http", app_protocol = "http" }]
            depends_on               = { router = "START" }
            health_check             = { command = ["CMD", "true"], start_period = 10 }
            readonly_root_filesystem = true
            init_process_enabled     = true
            capabilities_drop        = ["ALL"]
            ulimits                  = { nofile = { soft = 1024, hard = 2048 } }
            docker_labels            = { team = "orders" }
            start_timeout            = 30
            stop_timeout             = 20
            log_driver               = "awsfirelens"
            log_options              = { Name = "cloudwatch" }
          }
          router = {
            image     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:2.32.0"
            essential = false
            firelens  = { type = "fluentbit" }
          }
        }
      }
    }
    acknowledged_checks = []
  }

  assert {
    condition = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0] == {
      name                   = "app"
      image                  = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
      essential              = true
      readonlyRootFilesystem = true
      cpu                    = 256
      memory                 = 512
      memoryReservation      = 256
      command                = ["serve"]
      entryPoint             = ["/init"]
      workingDirectory       = "/srv"
      user                   = "1000"
      portMappings           = [{ containerPort = 8080, protocol = "tcp", name = "http", appProtocol = "http" }]
      dependsOn              = [{ containerName = "router", condition = "START" }]
      healthCheck            = { command = ["CMD", "true"], interval = 30, timeout = 5, retries = 3, startPeriod = 10 }
      linuxParameters        = { initProcessEnabled = true, capabilities = { drop = ["ALL"] } }
      ulimits                = [{ name = "nofile", softLimit = 1024, hardLimit = 2048 }]
      dockerLabels           = { team = "orders" }
      startTimeout           = 30
      stopTimeout            = 20
      logConfiguration       = { logDriver = "awsfirelens", options = { Name = "cloudwatch" } }
    }
    error_message = "a fully specified container renders exactly the ECS container definition fields, in ECS's names."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[1].firelensConfiguration == { type = "fluentbit" }
    error_message = "the log router carries its firelens configuration."
  }
}

# ---------------------------------------------------------------------------
# Task definitions
# ---------------------------------------------------------------------------

run "task_definitions_are_named_sized_and_kept" {
  command = plan

  assert {
    condition     = aws_ecs_task_definition.this["api"].family == "orders-api"
    error_message = "the family is <name>-<key>."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].cpu == "256" && aws_ecs_task_definition.this["api"].memory == "512"
    error_message = "cpu and memory default to the smallest Fargate size."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].skip_destroy == true
    error_message = "superseded revisions stay ACTIVE by default, so a manual rollback has something to roll back to."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].requires_compatibilities == toset(["FARGATE"]) && aws_ecs_task_definition.this["api"].network_mode == "awsvpc"
    error_message = "a default workload is an awsvpc Fargate task."
  }
}

run "efs_volumes_encrypt_in_transit_and_authorise_with_the_task_role" {
  command = plan

  variables {
    services = {
      api = {
        desired_count = 2
        containers = {
          app = {
            image        = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
            mount_points = [{ source_volume = "shared", container_path = "/data" }, { source_volume = "config", container_path = "/etc/app", read_only = true }]
          }
        }
        volumes = {
          shared = { efs = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-0123456789abcdef0" } }
          config = { efs = { file_system_id = "fs-0fedcba9876543210" } }
        }
      }
    }
  }

  assert {
    condition = alltrue([for v in aws_ecs_task_definition.this["api"].volume : alltrue([
      v.efs_volume_configuration[0].transit_encryption == "ENABLED",
      v.efs_volume_configuration[0].authorization_config[0].iam == "ENABLED",
    ])])
    error_message = "EFS volumes default to TLS and IAM authorisation."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.task_module["api"].policy).Statement == [
      {
        Sid      = "EfsMount0"
        Effect   = "Allow"
        Action   = ["elasticfilesystem:ClientMount"]
        Resource = "arn:aws:elasticfilesystem:eu-west-2:111122223333:file-system/fs-0fedcba9876543210"
      },
      {
        Sid       = "EfsMount1"
        Effect    = "Allow"
        Action    = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
        Resource  = "arn:aws:elasticfilesystem:eu-west-2:111122223333:file-system/fs-0123456789abcdef0"
        Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = "arn:aws:elasticfilesystem:eu-west-2:111122223333:access-point/fsap-0123456789abcdef0" } }
      },
    ]
    error_message = "the task role may mount each IAM-authorised file system, write only where a mount is read-write, and only through its access point."
  }
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

run "capacity_presets_render_the_documented_strategies" {
  command = plan

  variables {
    services = {
      a = { image = "r/a:1", desired_count = 2, capacity = "on_demand" }
      b = { image = "r/b:1", desired_count = 2, capacity = "balanced" }
      c = { image = "r/c:1", desired_count = 2, capacity = "spot_preferred" }
    }
  }

  assert {
    condition     = aws_ecs_service.this["a"].capacity_provider_strategy == toset([{ capacity_provider = "FARGATE", weight = 1, base = 0 }])
    error_message = "on_demand is FARGATE only."
  }

  assert {
    condition     = aws_ecs_service.this["b"].capacity_provider_strategy == toset([{ capacity_provider = "FARGATE", weight = 1, base = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 }])
    error_message = "balanced keeps one on-demand task, then 1:3 on Spot."
  }

  assert {
    condition     = aws_ecs_service.this["c"].capacity_provider_strategy == toset([{ capacity_provider = "FARGATE", weight = 1, base = 0 }, { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }])
    error_message = "spot_preferred is 1:4 with no base."
  }

  assert {
    condition     = output.governance.spot_without_on_demand == []
    error_message = "every preset except spot_only keeps some on-demand share."
  }
}

# The proxy for "a strategy change is an update": force_new_deployment, which
# both provider majors require for an in-place strategy change. The mock
# cannot show the replacement itself.
run "every_service_can_change_strategy_in_place" {
  command = plan

  variables {
    services = {
      api    = { image = "r/a:1", desired_count = 2 }
      scaled = { image = "r/b:1", autoscaling = { min = 2, max = 4 } }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].force_new_deployment && aws_ecs_service.autoscaled["scaled"].force_new_deployment
    error_message = "force_new_deployment is on for both service resources."
  }

  assert {
    condition     = length(aws_ecs_service.this["api"].capacity_provider_strategy) > 0 && length(aws_ecs_service.autoscaled["scaled"].capacity_provider_strategy) > 0
    error_message = "a replica service always sends a strategy, so a change is never a swap from launch_type."
  }
}

run "an_ec2_capacity_key_resolves_to_the_registered_provider" {
  command = plan

  variables {
    ec2_capacity_providers = {
      general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:11111111-2222-3333-4444-555555555555:autoScalingGroupName/g" }
    }
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "general", network_mode = "awsvpc" }
    }
  }

  assert {
    condition     = aws_ecs_capacity_provider.ec2["general"].name == "orders-general"
    error_message = "EC2 capacity providers are registered as <name>-<key>."
  }

  assert {
    condition     = aws_ecs_service.this["api"].capacity_provider_strategy == toset([{ capacity_provider = "orders-general", weight = 1, base = 0 }])
    error_message = "a service's capacity key becomes the registered provider name."
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "orders-general") && contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "FARGATE_SPOT")
    error_message = "the cluster registers Fargate, Fargate Spot and every EC2 provider."
  }

  assert {
    condition     = contains(output.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ecs-agent")
    error_message = "EC2 container instances need the ecs-agent endpoint, and the contract says so."
  }
}

run "a_daemon_runs_on_ec2_without_a_strategy_or_count" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2 }
      shipper = {
        workload     = "daemon"
        launch       = "EC2"
        network_mode = "bridge"
        image        = "r/shipper:1"
      }
    }
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this["shipper"].scheduling_strategy == "DAEMON",
      aws_ecs_service.this["shipper"].launch_type == "EC2",
      length(aws_ecs_service.this["shipper"].capacity_provider_strategy) == 0,
      aws_ecs_service.this["shipper"].desired_count == null,
      length(aws_ecs_service.this["shipper"].network_configuration) == 0,
    ])
    error_message = "a daemon is DAEMON-scheduled on EC2, with no strategy, count or awsvpc configuration."
  }

  # availability_zone_rebalancing is computed on aws 6.x, so an unset value is
  # unknown at plan there; the decision is asserted where it is made.
  assert {
    condition     = output.governance.az_rebalancing == ["api"]
    error_message = "AZ rebalancing is not requested for a daemon, which does not support it."
  }
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

run "services_deploy_safely_by_default" {
  command = plan

  assert {
    condition     = aws_ecs_service.this["api"].deployment_circuit_breaker[0].enable && aws_ecs_service.this["api"].deployment_circuit_breaker[0].rollback
    error_message = "the circuit breaker and rollback are on."
  }

  assert {
    condition     = aws_ecs_service.this["api"].deployment_minimum_healthy_percent == 100 && aws_ecs_service.this["api"].deployment_maximum_percent == 200
    error_message = "a rolling deployment keeps every old task until its replacement is healthy."
  }

  assert {
    condition     = aws_ecs_service.this["api"].availability_zone_rebalancing == "ENABLED"
    error_message = "AZ rebalancing is on where ECS supports it."
  }

  assert {
    condition     = aws_ecs_service.this["api"].enable_ecs_managed_tags && aws_ecs_service.this["api"].propagate_tags == "SERVICE"
    error_message = "tasks carry the service's tags and the ECS managed tags, for cost allocation."
  }

  assert {
    condition     = aws_ecs_service.this["api"].deployment_controller[0].type == "ECS"
    error_message = "the deployment controller is sent explicitly as ECS."
  }

  assert {
    condition     = aws_ecs_service.this["api"].network_configuration[0].assign_public_ip == false
    error_message = "tasks get no public IP."
  }
}

run "a_daemon_replaces_its_tasks_in_place_by_default" {
  command = plan

  variables {
    services = {
      api     = { image = "r/a:1", desired_count = 2 }
      shipper = { workload = "daemon", launch = "EC2", network_mode = "bridge", image = "r/s:1" }
    }
  }

  assert {
    condition     = aws_ecs_service.this["shipper"].deployment_minimum_healthy_percent == 0 && aws_ecs_service.this["api"].deployment_minimum_healthy_percent == 100
    error_message = "unset minimum_healthy_percent is the API's default: 0 for a daemon (one task per instance cannot double), 100 for a service."
  }
}

run "az_rebalancing_is_off_where_ecs_cannot_rebalance" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, deployment = { maximum_percent = 100, minimum_healthy_percent = 50 } }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].availability_zone_rebalancing == "DISABLED"
    error_message = "maximumPercent 100 leaves no room to rebalance, so it is sent DISABLED."
  }
}

run "a_load_balanced_shortcut_defaults_its_container_port_and_grace" {
  command = plan

  variables {
    services = {
      api = {
        image          = "r/a:1"
        port           = 8080
        desired_count  = 2
        load_balancers = [{ target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api/0123456789abcdef" }]
      }
    }
  }

  assert {
    condition     = [for lb in aws_ecs_service.this["api"].load_balancer : [lb.target_group_arn, lb.container_name, lb.container_port]] == [["arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api/0123456789abcdef", "api", 8080]]
    error_message = "the load balancer targets the shortcut container on its port."
  }

  assert {
    condition     = aws_ecs_service.this["api"].health_check_grace_period_seconds == 60
    error_message = "a load-balanced service gets 60 seconds before health checks count."
  }
}

run "service_connect_publishes_the_shortcut_port_under_the_service_name" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-abcdef0123456789"
    services = {
      api = { image = "r/a:1", port = 8080, desired_count = 2, service_connect = {} }
      client = {
        desired_count   = 2
        containers      = { app = { image = "r/c:1" } }
        service_connect = {}
      }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].service[0].port_name == "api" && aws_ecs_service.this["api"].service_connect_configuration[0].service[0].client_alias[0].port == 8080
    error_message = "with the shortcut, service_connect = {} publishes its port as the service name."
  }

  assert {
    condition     = length(aws_ecs_service.this["client"].service_connect_configuration[0].service) == 0
    error_message = "with containers and no expose, the service is a Service Connect client only."
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].namespace == "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-abcdef0123456789"
    error_message = "the cluster's namespace is used when the service names none."
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].log_configuration[0].options["awslogs-stream-prefix"] == "service-connect"
    error_message = "the Service Connect proxy logs to the service's log group."
  }
}

run "a_managed_ebs_volume_is_encrypted_tagged_and_attached_by_a_scoped_role" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2 }
      db = {
        desired_count      = 2
        containers         = { db = { image = "r/db:1", mount_points = [{ source_volume = "data", container_path = "/data" }] } }
        volumes            = { data = { configure_at_launch = true } }
        managed_ebs_volume = { volume_name = "data", size_in_gb = 50 }
      }
    }
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this["db"].volume_configuration[0].managed_ebs_volume[0].encrypted,
      aws_ecs_service.this["db"].volume_configuration[0].managed_ebs_volume[0].volume_type == "gp3",
      aws_ecs_service.this["db"].volume_configuration[0].managed_ebs_volume[0].tag_specifications[0].tags["CostCenter"] == "cc-1",
    ])
    error_message = "a task's EBS volume is encrypted gp3 and carries the cost allocation tags."
  }

  assert {
    condition     = alltrue([length(aws_iam_role.infrastructure) == 1, aws_iam_role_policy_attachment.infrastructure["volumes"].policy_arn == "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes"])
    error_message = "the infrastructure role exists, with the AWS volumes policy, only because a service needs it."
  }
}

run "no_infrastructure_role_without_a_managed_volume" {
  command = plan

  assert {
    condition     = length(aws_iam_role.infrastructure) == 0 && output.infrastructure_role_arn == null
    error_message = "the infrastructure role is not created for nothing."
  }
}

run "a_pipeline_owned_service_is_its_own_resource" {
  command = plan

  variables {
    services = {
      api    = { image = "r/a:1", desired_count = 2, deployment = { ignore_task_definition_changes = true } }
      scaled = { image = "r/b:1", autoscaling = { min = 2, max = 4 }, deployment = { ignore_task_definition_changes = true } }
      plain  = { image = "r/c:1", desired_count = 2 }
    }
  }

  # The proxy for "the pipeline owns the revision": which resource holds the
  # service. tests/service_parity.py proves each resource's ignore_changes.
  assert {
    condition = alltrue([
      keys(aws_ecs_service.static_ignored) == ["api"], keys(aws_ecs_service.autoscaled_ignored) == ["scaled"],
      keys(aws_ecs_service.this) == ["plain"], length(aws_ecs_service.autoscaled) == 0,
    ])
    error_message = "ignore_task_definition_changes moves a service to the resource that ignores task_definition."
  }

  assert {
    condition     = alltrue([jsonencode(output.governance.externally_deployed) == jsonencode(["api", "scaled"]), aws_appautoscaling_target.this["scaled"].resource_id == "service/orders/scaled"])
    error_message = "pipeline-owned services are listed in governance, and still autoscale."
  }

  assert {
    condition     = toset(keys(output.service_arns)) == toset(["api", "scaled", "plain"])
    error_message = "every service resource reaches the outputs."
  }
}

run "cloud_map_registers_a_records_or_srv_with_a_port" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", port = 8080, desired_count = 2, service_discovery = { namespace_id = "ns-abcdef0123456789" } }
      legacy = {
        desired_count     = 2
        containers        = { app = { image = "r/l:1", port_mappings = [{ container_port = 7000 }] } }
        service_discovery = { namespace_id = "ns-abcdef0123456789", name = "legacy-api", dns_record_type = "SRV", container_name = "app", container_port = 7000 }
      }
      existing = { image = "r/e:1", desired_count = 2, service_discovery = { registry_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:service/srv-abcdef0123456789" } }
    }
  }

  assert {
    condition     = aws_service_discovery_service.this["api"].name == "api" && aws_service_discovery_service.this["api"].dns_config[0].dns_records[0].type == "A"
    error_message = "an A record is registered under the workload's name by default."
  }

  assert {
    condition     = aws_service_discovery_service.this["legacy"].name == "legacy-api" && one(aws_ecs_service.this["legacy"].service_registries).container_port == 7000 && one(aws_ecs_service.this["legacy"].service_registries).container_name == "app"
    error_message = "an SRV registration names the container and port ECS publishes."
  }

  assert {
    condition     = alltrue([!contains(keys(aws_service_discovery_service.this), "existing"), one(aws_ecs_service.this["existing"].service_registries).registry_arn == "arn:aws:servicediscovery:eu-west-2:111122223333:service/srv-abcdef0123456789"])
    error_message = "an existing Cloud Map service is used, not created."
  }
}

run "a_workload_can_log_to_a_shared_group_or_keep_its_own_retention" {
  command = plan

  variables {
    services = {
      api   = { image = "r/a:1", desired_count = 2, log_group = { create = false, name = "/shared/siem-forwarded" } }
      audit = { image = "r/b:1", desired_count = 2, log_group = { retention_days = 2557 } }
      plain = { image = "r/c:1", desired_count = 2 }
    }
  }

  assert {
    condition     = alltrue([!contains(keys(aws_cloudwatch_log_group.this), "api"), jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].logConfiguration.options["awslogs-group"] == "/shared/siem-forwarded"])
    error_message = "a workload pointed at an existing group writes there, and the module does not create or own it."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["audit"].retention_in_days == 2557 && aws_cloudwatch_log_group.this["plain"].retention_in_days == 30
    error_message = "a workload's retention overrides the module's."
  }

  assert {
    condition     = one([for r in output.kms_key_policy_requirements : r.conditions[0].values if r.sid == "ServiceLogGroups0"]) == tolist(["arn:aws:logs:eu-west-2:111122223333:log-group:/ecs/orders/audit", "arn:aws:logs:eu-west-2:111122223333:log-group:/ecs/orders/plain"])
    error_message = "the Logs grant names exactly the groups the module creates."
  }

  assert {
    condition     = jsonencode(output.governance.log_groups_not_managed) == jsonencode(["api"])
    error_message = "a reviewer sees which workloads log to a group the module does not manage."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.execution_module["audit"].policy, "orders-api") && !contains(keys(aws_iam_role_policy.execution_module), "api")
    error_message = "a workload writing to an existing group without a key gets no log-key grant; the module key goes only to writers of its groups."
  }
}

run "each_log_group_is_encrypted_and_granted_with_its_own_key" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2 }
      siem = {
        image         = "r/b:1"
        desired_count = 2
        log_group     = { create = false, name = "/platform/siem", kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555" }
      }
    }
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.execution_module["siem"].policy).Statement : s.Resource if s.Sid == "WriteEncryptedLogs"]) == "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555"
    error_message = "a workload writing to an existing encrypted group is granted that group's key, through CloudWatch Logs."
  }

  assert {
    condition = jsonencode([for r in output.kms_key_policy_requirements : [r.sid, r.principals.arns] if startswith(r.sid, "LogWriters")]) == jsonencode([
      ["LogWriters0", ["arn:aws:iam::111122223333:role/orders-api-exec"]],
      ["LogWriters1", ["arn:aws:iam::111122223333:role/orders-siem-exec"]],
    ])
    error_message = "each key's owner is asked to allow exactly the execution roles that write under that key."
  }

  assert {
    condition     = !contains([for r in output.kms_key_policy_requirements : r.sid], "ServiceLogGroups1")
    error_message = "the module asks the Logs service grant only for groups it creates; the existing group's owner already has it."
  }
}

run "alarm_actions_windows_and_floors_are_the_callers" {
  command = plan

  variables {
    alarm_actions            = ["arn:aws:sns:eu-west-2:111122223333:pager", "arn:aws:lambda:eu-west-2:111122223333:function:opsgenie"]
    alarm_period             = 120
    alarm_evaluation_periods = 5
    services = {
      api = { image = "r/a:1", desired_count = 4, alarms = { min_running_tasks = 3 } }
    }
  }

  assert {
    condition = alltrue([
      aws_cloudwatch_metric_alarm.cpu["api"].alarm_actions == toset(["arn:aws:sns:eu-west-2:111122223333:pager", "arn:aws:lambda:eu-west-2:111122223333:function:opsgenie"]),
      aws_cloudwatch_metric_alarm.cpu["api"].ok_actions == aws_cloudwatch_metric_alarm.cpu["api"].alarm_actions,
      aws_cloudwatch_metric_alarm.cpu["api"].period == 120,
      aws_cloudwatch_metric_alarm.running_tasks["api"].evaluation_periods == 5,
    ])
    error_message = "alarm targets, OK targets (defaulting to the same), period and evaluation periods come from the caller."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.running_tasks["api"].threshold == 3
    error_message = "min_running_tasks overrides the derived floor."
  }

  assert {
    condition     = length(output.notification_requirements.topic_policy_statements) == 1
    error_message = "with alarm actions elsewhere, the topic contract no longer claims the alarms publish to sns_topic_arn."
  }
}

run "external_capacity_providers_are_registered_and_usable" {
  command = plan

  variables {
    external_capacity_providers = ["managed-instances"]
    services = {
      api = { image = "r/a:1", desired_count = 2, launch = "EC2", capacity = "managed-instances" }
    }
  }

  assert {
    condition     = contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "managed-instances")
    error_message = "an external provider is registered on the cluster, which only this module can do."
  }

  assert {
    condition     = aws_ecs_service.this["api"].capacity_provider_strategy == toset([{ capacity_provider = "managed-instances", weight = 1, base = 0 }])
    error_message = "a service can run on an external provider by name."
  }
}

# ---------------------------------------------------------------------------
# Autoscaling
# ---------------------------------------------------------------------------

run "an_autoscaled_service_starts_inside_its_bounds_and_scales_on_its_targets" {
  command = plan

  variables {
    services = {
      api = {
        image         = "r/a:1"
        desired_count = 1
        autoscaling = {
          min                 = 3
          max                 = 9
          requests_per_target = 400
          alb_resource_label  = "app/lb/0123456789abcdef/targetgroup/api/0123456789abcdef"
          custom              = { queue = { target_value = 50, namespace = "AWS/SQS", metric_name = "ApproximateNumberOfMessagesVisible", dimensions = { QueueName = "q" } } }
          schedules           = { night = { schedule = "cron(0 20 * * ? *)", min = 1, max = 3, timezone = "Europe/London" } }
        }
      }
    }
  }

  assert {
    condition     = alltrue([length(aws_ecs_service.this) == 0, aws_ecs_service.autoscaled["api"].desired_count == 3])
    error_message = "an autoscaled service is the autoscaled resource, starting at autoscaling.min when desired_count is below it."
  }

  assert {
    condition     = aws_appautoscaling_target.this["api"].resource_id == "service/orders/api" && aws_appautoscaling_target.this["api"].min_capacity == 3 && aws_appautoscaling_target.this["api"].max_capacity == 9
    error_message = "the scalable target is the service, with the configured bounds."
  }

  assert {
    condition     = toset(keys(aws_appautoscaling_policy.target_tracking)) == toset(["api/cpu", "api/requests"])
    error_message = "cpu_target defaults on, memory stays off, requests_per_target adds a request policy."
  }

  assert {
    condition     = aws_appautoscaling_policy.target_tracking["api/requests"].target_tracking_scaling_policy_configuration[0].predefined_metric_specification[0].resource_label == "app/lb/0123456789abcdef/targetgroup/api/0123456789abcdef"
    error_message = "the request policy names its target group."
  }

  assert {
    condition     = aws_appautoscaling_policy.custom["api/queue"].target_tracking_scaling_policy_configuration[0].customized_metric_specification[0].dimensions == toset([{ name = "QueueName", value = "q" }])
    error_message = "a custom metric keeps its dimensions."
  }

  assert {
    condition     = aws_appautoscaling_scheduled_action.this["api/night"].timezone == "Europe/London" && aws_appautoscaling_scheduled_action.this["api/night"].scalable_target_action[0].max_capacity == "3"
    error_message = "scheduled scaling keeps its timezone and bounds."
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

run "task_roles_trust_ecs_tasks_from_this_account_only" {
  command = plan

  assert {
    condition = jsondecode(aws_iam_role.task["api"].assume_role_policy).Statement[0].Condition == {
      ArnLike      = { "aws:SourceArn" = "arn:aws:ecs:eu-west-2:111122223333:*" }
      StringEquals = { "aws:SourceAccount" = "111122223333" }
    }
    error_message = "the task role trust is scoped to ECS in this account and region."
  }

  assert {
    condition     = aws_iam_role.task["api"].name == "orders-api-task" && aws_iam_role.execution["api"].name == "orders-api-exec"
    error_message = "roles are named <name>-<key>-task and -exec."
  }

  assert {
    condition     = length(aws_iam_role_policy.task_module) == 0
    error_message = "a workload with no exec or EFS gets no task role policy from the module."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.execution_module["api"].policy).Statement == [{
      Sid       = "WriteEncryptedLogs"
      Effect    = "Allow"
      Action    = ["kms:Encrypt", "kms:ReEncrypt*", "kms:Decrypt", "kms:GenerateDataKey*", "kms:Describe*"]
      Resource  = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      Condition = { StringEquals = { "kms:ViaService" = "logs.eu-west-2.amazonaws.com" } }
    }]
    error_message = "with a log key and nothing else, the execution role may use the key only through CloudWatch Logs, to write its logs."
  }
}

run "an_execution_role_reads_only_its_own_secrets" {
  command = plan

  variables {
    secrets_kms_key_arns = ["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"]
    services = {
      api = {
        image         = "r/a:1"
        desired_count = 2
        secrets = {
          DB_PASSWORD = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-AbCdEf:password::"
          API_KEY     = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:partner"
          FLAG        = "arn:aws:ssm:eu-west-2:111122223333:parameter/orders/flag"
        }
      }
      other = { image = "r/b:1", desired_count = 2, secrets = { X = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:other-ZyXwVu" } }
    }
  }

  assert {
    condition = jsonencode(jsondecode(aws_iam_role_policy.execution_module["api"].policy).Statement) == jsonencode([
      {
        Sid    = "ReadSecrets"
        Effect = "Allow"
        Action = ["secretsmanager:GetSecretValue"]
        # db-AbCdEf may be a full ARN or a name ending in six characters: both forms.
        Resource = ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-AbCdEf", "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-AbCdEf-??????", "arn:aws:secretsmanager:eu-west-2:111122223333:secret:partner-??????"]
      },
      { Sid = "ReadParameters", Effect = "Allow", Action = ["ssm:GetParameters"], Resource = ["arn:aws:ssm:eu-west-2:111122223333:parameter/orders/flag"] },
      {
        Sid       = "DecryptSecrets"
        Effect    = "Allow"
        Action    = ["kms:Decrypt"]
        Resource  = ["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"]
        Condition = { StringEquals = { "kms:ViaService" = ["secretsmanager.eu-west-2.amazonaws.com", "ssm.eu-west-2.amazonaws.com"] } }
      },
      {
        Sid       = "WriteEncryptedLogs"
        Effect    = "Allow"
        Action    = ["kms:Encrypt", "kms:ReEncrypt*", "kms:Decrypt", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
        Condition = { StringEquals = { "kms:ViaService" = "logs.eu-west-2.amazonaws.com" } }
      },
    ])
    error_message = "the execution role reads exactly its own secrets (JSON-key suffix trimmed, partial ARN wildcarded), its parameter, and the key only through Secrets Manager or SSM."
  }

  assert {
    condition     = !strcontains(aws_iam_role_policy.execution_module["other"].policy, "db-AbCdEf")
    error_message = "one workload's execution role cannot read another workload's secret."
  }
}

run "ecs_exec_gets_its_channels_session_key_and_an_init_process" {
  command = plan

  variables {
    execute_command = { kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555" }
    services = {
      api = { image = "r/a:1", desired_count = 2, enable_execute_command = true }
    }
    acknowledged_checks = ["shell_access_is_intended"]
  }

  assert {
    condition     = [for s in jsondecode(aws_iam_role_policy.task_module["api"].policy).Statement : s.Sid] == ["EcsExecChannels", "EcsExecSessionKey"]
    error_message = "the task role gets the SSM channels and the session key, nothing else."
  }

  assert {
    condition     = jsondecode(aws_ecs_task_definition.this["api"].container_definitions)[0].linuxParameters == { initProcessEnabled = true }
    error_message = "the shortcut container runs an init process when exec is on, so sessions do not leave zombie processes."
  }

  assert {
    condition     = aws_ecs_cluster.this[0].configuration[0].execute_command_configuration[0].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
    error_message = "the cluster encrypts sessions with the key."
  }

  assert {
    condition     = contains(output.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ssmmessages")
    error_message = "exec needs the ssmmessages endpoint, and the contract says so."
  }
}

run "the_cluster_sends_no_configuration_it_does_not_need" {
  command = plan

  assert {
    condition     = length(aws_ecs_cluster.this[0].configuration) == 0
    error_message = "with exec logging at its default and no storage keys, the cluster sends no configuration block."
  }

  assert {
    condition     = one([for s in aws_ecs_cluster.this[0].setting : s.value if s.name == "containerInsights"]) == "enabled"
    error_message = "Container Insights is on by default."
  }
}

run "supplied_roles_are_used_and_none_are_created" {
  command = plan

  variables {
    services = {
      api = {
        image          = "r/a:1"
        desired_count  = 2
        task_role      = { create = false, arn = "arn:aws:iam::111122223333:role/app" }
        execution_role = { create = false, arn = "arn:aws:iam::111122223333:role/exec" }
      }
    }
  }

  assert {
    condition     = length(aws_iam_role.task) == 0 && length(aws_iam_role.execution) == 0
    error_message = "create = false creates no roles."
  }

  assert {
    condition     = aws_ecs_task_definition.this["api"].task_role_arn == "arn:aws:iam::111122223333:role/app" && aws_ecs_task_definition.this["api"].execution_role_arn == "arn:aws:iam::111122223333:role/exec"
    error_message = "the task definition uses the supplied roles."
  }
}

run "caller_policies_attach_by_name" {
  command = plan

  variables {
    services = {
      api = {
        image         = "r/a:1"
        desired_count = 2
        task_role = {
          policies         = { read = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "s3:GetObject", Resource = "*" }] }) }
          managed_policies = { xray = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess" }
        }
        execution_role = { managed_policies = { extra = "arn:aws:iam::111122223333:policy/pull-from-artifactory" } }
      }
    }
  }

  assert {
    condition     = aws_iam_role_policy.task_custom["api/read"].name == "read" && aws_iam_role_policy_attachment.task_managed["api/xray"].policy_arn == "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
    error_message = "task role policies are keyed by name, so their ARNs and documents may be unknown at plan."
  }

  assert {
    condition     = aws_iam_role_policy_attachment.execution_managed["api/extra"].policy_arn == "arn:aws:iam::111122223333:policy/pull-from-artifactory"
    error_message = "execution role managed policies attach by name."
  }
}

run "a_secret_name_that_looks_like_a_suffix_is_granted_both_ways" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, secrets = { A = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-master" } }
    }
  }

  # db-master could be the full ARN of "db" or the partial ARN of "db-master";
  # only one of them exists, and the role must be able to read it.
  assert {
    condition     = jsondecode(aws_iam_role_policy.execution_module["api"].policy).Statement[0].Resource == ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-master", "arn:aws:secretsmanager:eu-west-2:111122223333:secret:db-master-??????"]
    error_message = "an ambiguous secret ARN is granted as given and with the suffix wildcard."
  }
}

run "s3_grants_only_reach_buckets_this_account_owns" {
  command = plan

  variables {
    environment_files_kms_key_arns = ["arn:aws:kms:eu-west-2:111122223333:key/77777777-2222-3333-4444-555555555555"]
    services = {
      api = {
        desired_count = 2
        containers    = { app = { image = "r/a:1", environment_files = ["arn:aws:s3:::orders-config/prod/app.env"] } }
      }
    }
  }

  assert {
    condition = alltrue([for s in jsondecode(aws_iam_role_policy.execution_module["api"].policy).Statement :
    s.Condition == { StringEquals = { "aws:ResourceAccount" = ["111122223333"] } } if startswith(s.Sid, "ReadEnvironment") || startswith(s.Sid, "LocateEnvironment")])
    error_message = "environment-file grants carry aws:ResourceAccount, so a taken-over bucket name serves nothing."
  }

  assert {
    condition     = one([for s in jsondecode(aws_iam_role_policy.execution_module["api"].policy).Statement : s.Condition if s.Sid == "DecryptEnvironmentFiles"]) == { StringEquals = { "kms:ViaService" = "s3.eu-west-2.amazonaws.com" } }
    error_message = "the environment-file key is usable only through S3."
  }

  assert {
    condition     = contains([for r in output.kms_key_policy_requirements : r.sid], "EnvironmentFiles0")
    error_message = "the environment-file key owner is told what to allow."
  }
}

# ---------------------------------------------------------------------------
# Scheduled and run-task workloads
# ---------------------------------------------------------------------------

run "a_scheduled_workload_is_a_schedule_not_a_service" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2 }
      nightly = {
        workload = "scheduled"
        image    = "r/job:1"
        capacity = "spot_preferred"
        schedule = { expression = "cron(0 2 * * ? *)", timezone = "Europe/London", dead_letter_queue_arn = "arn:aws:sqs:eu-west-2:111122223333:dlq" }
      }
    }
  }

  assert {
    condition     = !contains(keys(aws_ecs_service.this), "nightly") && length(aws_ecs_service.autoscaled) == 0
    error_message = "a scheduled workload never runs as a service."
  }

  assert {
    condition = alltrue([
      aws_scheduler_schedule.this["nightly"].group_name == "orders",
      aws_scheduler_schedule.this["nightly"].schedule_expression_timezone == "Europe/London",
      aws_scheduler_schedule.this["nightly"].target[0].dead_letter_config[0].arn == "arn:aws:sqs:eu-west-2:111122223333:dlq",
      aws_scheduler_schedule.this["nightly"].target[0].retry_policy[0].maximum_retry_attempts == 2,
      aws_scheduler_schedule.this["nightly"].target[0].ecs_parameters[0].capacity_provider_strategy == toset([{ capacity_provider = "FARGATE", weight = 1, base = 0 }, { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }]),
      aws_scheduler_schedule.this["nightly"].target[0].ecs_parameters[0].tags["CostCenter"] == "cc-1",
    ])
    error_message = "the schedule runs in the module's group, in its timezone, with its strategy, bounded retries, a DLQ and the cost tags."
  }

  assert {
    condition = jsondecode(aws_iam_role.scheduler[0].assume_role_policy).Statement[0].Condition == {
      StringEquals = { "aws:SourceAccount" = "111122223333", "aws:SourceArn" = "arn:aws:scheduler:eu-west-2:111122223333:schedule-group/orders" }
    }
    error_message = "the scheduler role trusts only this account's schedule group."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement[0] == {
      Sid       = "RunScheduledTasks"
      Effect    = "Allow"
      Action    = ["ecs:RunTask"]
      Resource  = ["arn:aws:ecs:eu-west-2:111122223333:task-definition/orders-nightly:*"]
      Condition = { ArnEquals = { "ecs:cluster" = "arn:aws:ecs:eu-west-2:111122223333:cluster/orders" } }
    }
    error_message = "the scheduler may run only the scheduled families, only on this cluster."
  }

  assert {
    condition     = toset(jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement[1].Resource) == toset(["arn:aws:iam::111122223333:role/orders-nightly-task", "arn:aws:iam::111122223333:role/orders-nightly-exec"])
    error_message = "the scheduler may pass only the scheduled workloads' roles."
  }
}

run "a_task_workload_is_a_definition_with_a_ready_run_task_command" {
  command = plan

  variables {
    services = {
      api     = { image = "r/a:1", desired_count = 2 }
      migrate = { workload = "task", image = "r/m:1", command = ["migrate"] }
    }
  }

  assert {
    condition     = !contains(keys(aws_ecs_service.this), "migrate") && contains(keys(aws_ecs_task_definition.this), "migrate")
    error_message = "a task workload has a task definition and no service."
  }

  assert {
    condition     = strcontains(output.run_task_commands["migrate"], "--capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=0") && strcontains(output.run_task_commands["migrate"], "subnets=[subnet-0a1b2c3d4e5f60001,subnet-0a1b2c3d4e5f60002]")
    error_message = "run_task_commands carries the workload's strategy and network."
  }

  assert {
    condition     = !contains(keys(output.run_task_commands), "api")
    error_message = "services have no run-task command."
  }

  assert {
    condition = jsondecode(output.run_task_requirements.iam_policy).Statement[0] == {
      Sid       = "RunWorkloadTasks"
      Effect    = "Allow"
      Action    = ["ecs:RunTask"]
      Resource  = ["arn:aws:ecs:eu-west-2:111122223333:task-definition/orders-migrate:*"]
      Condition = { ArnEquals = { "ecs:cluster" = "arn:aws:ecs:eu-west-2:111122223333:cluster/orders" } }
    }
    error_message = "the pipeline may run only the task workloads, only on this cluster."
  }

  assert {
    condition     = alltrue([contains(keys(aws_cloudwatch_event_rule.this), "job-exited-non-zero"), strcontains(aws_cloudwatch_event_rule.this["job-exited-non-zero"].event_pattern, "family:orders-migrate")])
    error_message = "a failed run-task workload is reported to the topic."
  }
}

run "a_dead_letter_queue_is_writable_by_the_scheduler" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2 }
      nightly = {
        workload = "scheduled"
        image    = "r/job:1"
        schedule = {
          expression                    = "rate(1 day)"
          dead_letter_queue_arn         = "arn:aws:sqs:eu-west-2:111122223333:dlq"
          dead_letter_queue_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/88888888-2222-3333-4444-555555555555"
        }
      }
    }
  }

  assert {
    condition = [for s in jsondecode(aws_iam_role_policy.scheduler[0].policy).Statement : s if s.Sid == "DeliverToDeadLetterQueues"] == [{
      Sid = "DeliverToDeadLetterQueues", Effect = "Allow", Action = ["sqs:SendMessage"], Resource = ["arn:aws:sqs:eu-west-2:111122223333:dlq"]
    }]
    error_message = "the scheduler may send to exactly the configured dead-letter queue; without it a failed invocation is lost at the DLQ too."
  }

  assert {
    condition     = jsonencode(one([for r in output.kms_key_policy_requirements : r.principals.arns if r.sid == "ScheduleDeadLetters0"])) == jsonencode(["arn:aws:iam::111122223333:role/orders-scheduler"])
    error_message = "the DLQ key owner is told to allow the scheduler role."
  }
}

run "custom_scaling_policies_cannot_take_the_modules_policy_names" {
  command = plan

  variables {
    services = {
      api = {
        image       = "r/a:1"
        autoscaling = { min = 2, max = 4, custom = { cpu = { target_value = 5, namespace = "N", metric_name = "M" } } }
      }
    }
  }

  assert {
    condition     = aws_appautoscaling_policy.custom["api/cpu"].name == "orders-api-custom-cpu" && aws_appautoscaling_policy.target_tracking["api/cpu"].name == "orders-api-cpu"
    error_message = "a custom policy named cpu does not collide with the module's CPU policy."
  }

  assert {
    condition     = anytrue([for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s.Sid == "ApplicationAutoScalingServiceLinkedRole"])
    error_message = "with autoscaling, the deployer may create the Application Auto Scaling service-linked role."
  }
}

run "the_running_task_alarm_follows_scheduled_scale_downs" {
  command = plan

  variables {
    services = {
      api   = { image = "r/a:1", autoscaling = { min = 3, max = 6, schedules = { night = { schedule = "cron(0 20 * * ? *)", min = 2, max = 2 } } } }
      batch = { image = "r/b:1", autoscaling = { min = 2, max = 6, schedules = { off = { schedule = "cron(0 20 * * ? *)", min = 0, max = 0 } } } }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.running_tasks["api"].threshold == 2
    error_message = "the alarm fires below the lowest count the schedule allows, not the daytime minimum."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.running_tasks), "batch")
    error_message = "a service scheduled down to zero has no running-task alarm: silence is normal for it."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

run "alarms_watch_each_service_and_reach_the_topic" {
  command = plan

  variables {
    services = {
      api   = { image = "r/a:1", desired_count = 2, alarms = { cpu_percent = 70 } }
      quiet = { image = "r/b:1", desired_count = 2, alarms = { enabled = false } }
    }
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu["api"].threshold == 70 && aws_cloudwatch_metric_alarm.memory["api"].threshold == 85
    error_message = "a service's own threshold overrides the module default."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu["api"].dimensions == tomap({ ClusterName = "orders", ServiceName = "api" }) && aws_cloudwatch_metric_alarm.cpu["api"].alarm_actions == toset(["arn:aws:sns:eu-west-2:111122223333:alerts"])
    error_message = "alarms read the service's metrics and notify the topic."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.running_tasks["api"].threshold == 2 && aws_cloudwatch_metric_alarm.running_tasks["api"].treat_missing_data == "breaching"
    error_message = "the running-task alarm fires below the expected count, and on silence."
  }

  assert {
    condition     = !contains(keys(aws_cloudwatch_metric_alarm.cpu), "quiet")
    error_message = "alarms.enabled = false removes a service's alarms."
  }

  assert {
    condition     = output.alarm_names["api"] == { cpu = "orders-api-cpu", memory = "orders-api-memory", running_tasks = "orders-api-running-tasks" }
    error_message = "alarm names are output for deployment alarms and dashboards."
  }
}

run "no_running_task_alarm_without_container_insights" {
  command = plan

  variables {
    container_insights  = "disabled"
    acknowledged_checks = ["running_task_alarms_have_data"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.running_tasks) == 0
    error_message = "RunningTaskCount is a Container Insights metric; without it the alarm would always be in ALARM."
  }
}

run "failed_deployments_and_impaired_services_reach_the_topic" {
  command = plan

  assert {
    condition     = toset(keys(aws_cloudwatch_event_rule.this)) == toset(["deployment-failed", "service-impaired"])
    error_message = "with only services, the deployment and service-action rules exist and the job rules do not."
  }

  assert {
    condition = jsondecode(aws_cloudwatch_event_rule.this["deployment-failed"].event_pattern) == {
      source        = ["aws.ecs"]
      "detail-type" = ["ECS Deployment State Change"]
      resources     = [{ prefix = "arn:aws:ecs:eu-west-2:111122223333:service/orders/" }]
      detail        = { eventName = ["SERVICE_DEPLOYMENT_FAILED"] }
    }
    error_message = "the deployment rule matches failed deployments of this cluster's services only."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["deployment-failed"].arn == "arn:aws:sns:eu-west-2:111122223333:alerts"
    error_message = "the rules publish to the topic."
  }
}

run "no_event_rules_without_a_topic" {
  command = plan

  variables {
    sns_topic_arn       = ""
    acknowledged_checks = ["somebody_hears_a_failure"]
  }

  assert {
    condition     = length(aws_cloudwatch_event_rule.this) == 0 && output.notification_requirements == null
    error_message = "with no topic there is nothing to publish to."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu["api"].alarm_actions) == 0
    error_message = "alarms still exist, without actions."
  }
}

run "log_groups_are_named_bounded_and_encrypted" {
  command = plan

  assert {
    condition     = aws_cloudwatch_log_group.this["api"].name == "/ecs/orders/api" && aws_cloudwatch_log_group.this["api"].retention_in_days == 30
    error_message = "one log group per workload, /ecs/<name>/<key>, 30 days by default."
  }

  assert {
    condition     = aws_cloudwatch_log_group.this["api"].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
    error_message = "the log group uses the customer key."
  }
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

run "every_kms_requirement_is_contract_v2" {
  command = plan

  variables {
    fargate_ephemeral_storage_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/22222222-2222-3333-4444-555555555555"
    managed_storage_kms_key_arn           = "arn:aws:kms:eu-west-2:111122223333:key/33333333-2222-3333-4444-555555555555"
    secrets_kms_key_arns                  = ["arn:aws:kms:eu-west-2:111122223333:key/44444444-2222-3333-4444-555555555555"]
    sns_topic_kms_key_arn                 = "arn:aws:kms:eu-west-2:111122223333:key/55555555-2222-3333-4444-555555555555"
    execute_command                       = { kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/66666666-2222-3333-4444-555555555555" }
    acknowledged_checks                   = ["shell_access_is_intended"]
    services = {
      api = {
        image                  = "r/a:1"
        desired_count          = 2
        enable_execute_command = true
        secrets                = { X = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:x-AbCdEf" }
      }
      db = {
        desired_count      = 2
        containers         = { db = { image = "r/db:1", mount_points = [{ source_volume = "data", container_path = "/data" }] } }
        volumes            = { data = { configure_at_launch = true } }
        managed_ebs_volume = { volume_name = "data", size_in_gb = 20 }
      }
    }
  }

  assert {
    condition = alltrue([for r in output.kms_key_policy_requirements : alltrue([
      can(regex("^[A-Za-z0-9]+$", r.sid)),
      can(r.principals.services), can(r.principals.arns), can(r.principals.roles),
      length(r.actions) > 0, alltrue([for a in r.actions : startswith(a, "kms:")]),
      alltrue([for c in r.conditions : can(c.test) && can(c.variable) && can(c.values)]),
      length(r.purpose) > 0,
    ])])
    error_message = "every entry has sid, principals { services, arns, roles }, kms actions, conditions { test, variable, values } and purpose."
  }

  assert {
    condition     = length(distinct([for r in output.kms_key_policy_requirements : r.sid])) == length(output.kms_key_policy_requirements)
    error_message = "sids are unique within the module."
  }

  assert {
    condition     = alltrue([for r in output.kms_key_policy_requirements : length(r.principals.services) == 0 ? true : !anytrue([for c in r.conditions : c.variable == "kms:ViaService"])])
    error_message = "kms:ViaService never appears on a service-principal entry."
  }

  assert {
    condition = toset([for r in output.kms_key_policy_requirements : r.sid]) == toset([
      "ServiceLogGroups0", "LogGroupCreator0", "LogWriters0", "LogReaders0", "SecretsKey0", "EcsExecTasks", "EcsExecOperators",
      "FargateEphemeralDataKeys", "FargateEphemeralGrants", "FargateEphemeralDescribe",
      "ManagedEbsDescribe0", "ManagedEbsDataKeys0", "ManagedEbsGrants0", "SnsTopicPublishers",
    ])
    error_message = "each key-using feature hands its key owner its requirement."
  }

  assert {
    condition     = one([for r in output.kms_key_policy_requirements : r.principals.arns if r.sid == "SecretsKey0"]) == tolist(["arn:aws:iam::111122223333:role/orders-api-exec"])
    error_message = "only the execution roles of workloads with secrets are given the secrets key."
  }
}

run "the_notification_contract_scopes_each_publisher" {
  command = plan

  assert {
    condition = output.notification_requirements.topic_policy_statements[0].Condition == {
      ArnLike = { "aws:SourceArn" = "arn:aws:cloudwatch:eu-west-2:111122223333:alarm:orders-*" }
    }
    error_message = "the topic is asked to accept CloudWatch only for this module's alarms."
  }

  assert {
    condition     = output.notification_requirements.topic_policy_statements[1].Principal == { Service = "events.amazonaws.com" }
    error_message = "the topic is asked to accept EventBridge for the module's rules."
  }
}

run "the_deployer_may_pass_exactly_the_module_roles" {
  command = plan

  assert {
    condition = jsondecode(output.deployer_requirements.iam_policy).Statement[0] == {
      Sid       = "PassTaskRoles"
      Effect    = "Allow"
      Action    = "iam:PassRole"
      Resource  = ["arn:aws:iam::111122223333:role/orders-api-exec", "arn:aws:iam::111122223333:role/orders-api-task"]
      Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
    }
    error_message = "PassRole is limited to the workload roles, and only to ECS tasks."
  }
}

run "the_network_contract_follows_the_features_used" {
  command = plan

  assert {
    condition     = output.network_contract.required_interface_endpoints == tolist(["com.amazonaws.eu-west-2.ecr.api", "com.amazonaws.eu-west-2.ecr.dkr", "com.amazonaws.eu-west-2.logs"])
    error_message = "an ECR image with no secrets needs ECR and Logs, nothing else."
  }

  assert {
    condition     = output.network_contract.gateway_endpoints == tolist(["com.amazonaws.eu-west-2.s3"])
    error_message = "ECR layers come from S3."
  }
}

run "service_connect_on_fargate_needs_the_ecs_agent_endpoint" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-abcdef0123456789"
    services = {
      api = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0", port = 8080, desired_count = 2, service_connect = {} }
    }
  }

  assert {
    condition     = contains(output.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ecs-agent")
    error_message = "Service Connect's proxy is managed through ecs-agent, even on Fargate."
  }
}

run "images_outside_ecr_are_named_in_the_egress_contract" {
  command = plan

  variables {
    services = {
      api = { image = "ghcr.io/acme/api:1.0.0", desired_count = 2 }
    }
  }

  assert {
    condition     = anytrue([for e in output.network_contract.required_egress : strcontains(e, "ghcr.io")])
    error_message = "a registry with no VPC endpoint is named, because it needs a NAT or proxy path."
  }

  assert {
    condition     = !contains(output.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ecr.dkr")
    error_message = "no ECR endpoints are demanded when no image is in ECR."
  }
}

# ---------------------------------------------------------------------------
# Tags
# ---------------------------------------------------------------------------

run "module_tags_cannot_be_overridden" {
  command = plan

  variables {
    tags = { CostCenter = "cc-1", Environment = "test", ManagedBy = "someone", Module = "other" }
  }

  assert {
    condition     = aws_ecs_cluster.this[0].tags["ManagedBy"] == "Terraform" && aws_ecs_cluster.this[0].tags["Module"] == "ecs"
    error_message = "ManagedBy and Module are the module's."
  }

  assert {
    condition     = aws_ecs_service.this["api"].tags["CostCenter"] == "cc-1"
    error_message = "caller tags reach the services (and through propagate_tags, the tasks)."
  }
}

run "workload_tags_cannot_override_the_module_keys_either" {
  command = plan

  variables {
    services = {
      api = { image = "r/a:1", desired_count = 2, tags = { ManagedBy = "manual", Module = "other", Team = "orders" } }
    }
  }

  assert {
    condition = alltrue([for t in [
      aws_ecs_service.this["api"].tags, aws_ecs_task_definition.this["api"].tags, aws_iam_role.task["api"].tags,
      aws_iam_role.execution["api"].tags, aws_cloudwatch_log_group.this["api"].tags, aws_cloudwatch_metric_alarm.cpu["api"].tags,
    ] : t["ManagedBy"] == "Terraform" ? t["Module"] == "ecs" : false])
    error_message = "a workload's tags cannot replace ManagedBy or Module on any of its resources."
  }

  assert {
    condition     = aws_ecs_service.this["api"].tags["Team"] == "orders"
    error_message = "a workload's own tags are applied."
  }
}

# ---------------------------------------------------------------------------
# create = false
# ---------------------------------------------------------------------------

run "create_false_plans_nothing_and_outputs_nothing" {
  command = plan

  variables {
    create = false
    services = {
      api     = { image = "r/a:1", desired_count = 2, autoscaling = { max = 4 } }
      nightly = { workload = "scheduled", image = "r/j:1", schedule = { expression = "rate(1 day)" } }
    }
  }

  assert {
    condition = alltrue([
      length(aws_ecs_cluster.this) == 0, length(aws_ecs_cluster_capacity_providers.this) == 0, length(aws_ecs_capacity_provider.ec2) == 0,
      length(aws_ecs_task_definition.this) == 0, length(aws_ecs_service.this) == 0, length(aws_ecs_service.autoscaled) == 0,
      length(aws_ecs_service.static_ignored) == 0, length(aws_ecs_service.autoscaled_ignored) == 0,
      length(aws_service_discovery_service.this) == 0,
      length(aws_iam_role.task) == 0, length(aws_iam_role.execution) == 0, length(aws_iam_role.scheduler) == 0, length(aws_iam_role.infrastructure) == 0,
      length(aws_cloudwatch_log_group.this) == 0, length(aws_cloudwatch_metric_alarm.cpu) == 0, length(aws_cloudwatch_event_rule.this) == 0,
      length(aws_appautoscaling_target.this) == 0, length(aws_scheduler_schedule.this) == 0, length(aws_scheduler_schedule_group.this) == 0,
      length(data.aws_partition.current) == 0, length(data.aws_region.current) == 0, length(data.aws_caller_identity.current) == 0,
    ])
    error_message = "create = false plans no resources and reads no data sources."
  }

  assert {
    condition = alltrue([
      output.cluster_name == null, output.cluster_arn == null, output.governance == null, output.network_contract == null,
      output.kms_key_policy_requirements == null, output.notification_requirements == null, output.deployer_requirements == null,
      output.verify_commands == null, output.infrastructure_role_arn == null, output.run_task_requirements == null,
      length(output.service_names) == 0, length(output.task_definition_families) == 0, length(output.task_role_names) == 0, length(output.log_group_arns) == 0,
      length(output.service_arns) == 0, length(output.task_definition_arns) == 0, length(output.task_role_arns) == 0,
      length(output.execution_role_arns) == 0, length(output.log_group_names) == 0, length(output.run_task_commands) == 0,
      length(output.alarm_names) == 0, length(output.schedule_arns) == 0, length(output.capacity_provider_names) == 0,
    ])
    error_message = "create = false leaves every output null or empty."
  }
}
