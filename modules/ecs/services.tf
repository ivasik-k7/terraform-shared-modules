# Two resources with one body: lifecycle.ignore_changes cannot be conditional,
# and an autoscaled service must not have its desired_count reset by every
# apply. tests/service_parity.py fails when the bodies drift apart.
#
# force_new_deployment is always true: without it, changing
# capacity_provider_strategy replaces the service on aws 5.x and is refused
# at plan on 6.x. With it, every update of the service starts a deployment.

resource "aws_ecs_service" "this" {
  for_each = local.static

  # BEGIN SERVICE BODY
  name                               = each.key
  cluster                            = aws_ecs_cluster.this[0].arn
  task_definition                    = aws_ecs_task_definition.this[each.key].arn
  desired_count                      = each.value.workload == "daemon" ? null : local.initial_desired_count[each.key]
  scheduling_strategy                = each.value.workload == "daemon" ? "DAEMON" : "REPLICA"
  launch_type                        = each.value.workload == "daemon" ? "EC2" : null
  platform_version                   = each.value.launch == "FARGATE" ? each.value.platform_version : null
  force_new_deployment               = true
  enable_execute_command             = each.value.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = each.value.propagate_tags
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds > 0 ? each.value.health_check_grace_period_seconds : (length(local.load_balancers[each.key]) > 0 ? 60 : null)
  wait_for_steady_state              = each.value.deployment.wait_for_steady_state
  force_delete                       = each.value.force_delete
  availability_zone_rebalancing      = each.value.workload == "daemon" ? null : (local.az_rebalancing[each.key] ? "ENABLED" : "DISABLED")
  deployment_maximum_percent         = each.value.workload == "daemon" ? null : each.value.deployment.maximum_percent
  deployment_minimum_healthy_percent = each.value.deployment.minimum_healthy_percent != null ? each.value.deployment.minimum_healthy_percent : (each.value.workload == "daemon" ? 0 : 100)

  deployment_controller {
    type = "ECS"
  }

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      enable   = deployment_circuit_breaker.value.circuit_breaker
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "alarms" {
    for_each = length(each.value.deployment.alarm_names) > 0 ? [each.value.deployment] : []
    content {
      alarm_names = alarms.value.alarm_names
      enable      = true
      rollback    = alarms.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.strategy[each.key]
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "network_configuration" {
    for_each = each.value.network_mode == "awsvpc" ? [each.value] : []
    content {
      subnets          = local.subnets[each.key]
      security_groups  = local.security_groups[each.key]
      assign_public_ip = network_configuration.value.assign_public_ip
    }
  }

  dynamic "load_balancer" {
    for_each = local.load_balancers[each.key]
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_registry_arn != "" ? [each.value.service_registry_arn] : []
    content {
      registry_arn = service_registries.value
    }
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect != null ? [each.value.service_connect] : []
    content {
      enabled   = true
      namespace = local.service_connect_namespace[each.key]

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_proxy ? [1] : []
        content {
          log_driver = "awslogs"
          options = {
            "awslogs-group"         = local.log_group_name[each.key]
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = "service-connect"
          }
        }
      }

      dynamic "service" {
        for_each = local.service_connect_expose[each.key]
        content {
          port_name             = service.key
          discovery_name        = service.value.discovery_name != "" ? service.value.discovery_name : service.key
          ingress_port_override = service.value.ingress_port_override > 0 ? service.value.ingress_port_override : null

          client_alias {
            port     = service.value.port > 0 ? service.value.port : local.port_by_name[each.key][service.key]
            dns_name = service.value.dns_name != "" ? service.value.dns_name : null
          }

          dynamic "timeout" {
            for_each = service.value.idle_timeout_seconds + service.value.per_request_timeout_seconds > 0 ? [service.value] : []
            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds > 0 ? timeout.value.idle_timeout_seconds : null
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds > 0 ? timeout.value.per_request_timeout_seconds : null
            }
          }
        }
      }
    }
  }

  dynamic "volume_configuration" {
    for_each = each.value.managed_ebs_volume != null ? [each.value.managed_ebs_volume] : []
    content {
      name = volume_configuration.value.volume_name

      managed_ebs_volume {
        role_arn         = local.create_infra_role ? aws_iam_role.infrastructure[0].arn : local.infrastructure_arn
        encrypted        = true
        kms_key_id       = volume_configuration.value.kms_key_arn != "" ? volume_configuration.value.kms_key_arn : null
        size_in_gb       = volume_configuration.value.size_in_gb > 0 ? volume_configuration.value.size_in_gb : null
        snapshot_id      = volume_configuration.value.snapshot_id != "" ? volume_configuration.value.snapshot_id : null
        volume_type      = volume_configuration.value.volume_type
        iops             = volume_configuration.value.iops > 0 ? volume_configuration.value.iops : null
        throughput       = volume_configuration.value.throughput > 0 ? volume_configuration.value.throughput : null
        file_system_type = volume_configuration.value.file_system_type

        tag_specifications {
          resource_type  = "volume"
          propagate_tags = "SERVICE"
          tags           = local.workload_tags[each.key]
        }
      }
    }
  }

  dynamic "placement_constraints" {
    for_each = each.value.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression != "" ? placement_constraints.value.expression : null
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = each.value.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field != "" ? ordered_placement_strategy.value.field : null
    }
  }

  tags = local.workload_tags[each.key]

  # The task starts as soon as the service exists; its roles must be complete.
  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_module,
    aws_iam_role_policy_attachment.execution_managed,
    aws_iam_role_policy.task_module,
    aws_iam_role_policy.task_custom,
    aws_iam_role_policy_attachment.task_managed,
    aws_iam_role_policy_attachment.infrastructure,
    aws_cloudwatch_log_group.this,
  ]
  # END SERVICE BODY
}


resource "aws_ecs_service" "autoscaled" {
  for_each = local.autoscaled

  # BEGIN SERVICE BODY
  name                               = each.key
  cluster                            = aws_ecs_cluster.this[0].arn
  task_definition                    = aws_ecs_task_definition.this[each.key].arn
  desired_count                      = each.value.workload == "daemon" ? null : local.initial_desired_count[each.key]
  scheduling_strategy                = each.value.workload == "daemon" ? "DAEMON" : "REPLICA"
  launch_type                        = each.value.workload == "daemon" ? "EC2" : null
  platform_version                   = each.value.launch == "FARGATE" ? each.value.platform_version : null
  force_new_deployment               = true
  enable_execute_command             = each.value.enable_execute_command
  enable_ecs_managed_tags            = true
  propagate_tags                     = each.value.propagate_tags
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds > 0 ? each.value.health_check_grace_period_seconds : (length(local.load_balancers[each.key]) > 0 ? 60 : null)
  wait_for_steady_state              = each.value.deployment.wait_for_steady_state
  force_delete                       = each.value.force_delete
  availability_zone_rebalancing      = each.value.workload == "daemon" ? null : (local.az_rebalancing[each.key] ? "ENABLED" : "DISABLED")
  deployment_maximum_percent         = each.value.workload == "daemon" ? null : each.value.deployment.maximum_percent
  deployment_minimum_healthy_percent = each.value.deployment.minimum_healthy_percent != null ? each.value.deployment.minimum_healthy_percent : (each.value.workload == "daemon" ? 0 : 100)

  deployment_controller {
    type = "ECS"
  }

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      enable   = deployment_circuit_breaker.value.circuit_breaker
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  dynamic "alarms" {
    for_each = length(each.value.deployment.alarm_names) > 0 ? [each.value.deployment] : []
    content {
      alarm_names = alarms.value.alarm_names
      enable      = true
      rollback    = alarms.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.strategy[each.key]
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "network_configuration" {
    for_each = each.value.network_mode == "awsvpc" ? [each.value] : []
    content {
      subnets          = local.subnets[each.key]
      security_groups  = local.security_groups[each.key]
      assign_public_ip = network_configuration.value.assign_public_ip
    }
  }

  dynamic "load_balancer" {
    for_each = local.load_balancers[each.key]
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_registry_arn != "" ? [each.value.service_registry_arn] : []
    content {
      registry_arn = service_registries.value
    }
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect != null ? [each.value.service_connect] : []
    content {
      enabled   = true
      namespace = local.service_connect_namespace[each.key]

      dynamic "log_configuration" {
        for_each = service_connect_configuration.value.log_proxy ? [1] : []
        content {
          log_driver = "awslogs"
          options = {
            "awslogs-group"         = local.log_group_name[each.key]
            "awslogs-region"        = local.region
            "awslogs-stream-prefix" = "service-connect"
          }
        }
      }

      dynamic "service" {
        for_each = local.service_connect_expose[each.key]
        content {
          port_name             = service.key
          discovery_name        = service.value.discovery_name != "" ? service.value.discovery_name : service.key
          ingress_port_override = service.value.ingress_port_override > 0 ? service.value.ingress_port_override : null

          client_alias {
            port     = service.value.port > 0 ? service.value.port : local.port_by_name[each.key][service.key]
            dns_name = service.value.dns_name != "" ? service.value.dns_name : null
          }

          dynamic "timeout" {
            for_each = service.value.idle_timeout_seconds + service.value.per_request_timeout_seconds > 0 ? [service.value] : []
            content {
              idle_timeout_seconds        = timeout.value.idle_timeout_seconds > 0 ? timeout.value.idle_timeout_seconds : null
              per_request_timeout_seconds = timeout.value.per_request_timeout_seconds > 0 ? timeout.value.per_request_timeout_seconds : null
            }
          }
        }
      }
    }
  }

  dynamic "volume_configuration" {
    for_each = each.value.managed_ebs_volume != null ? [each.value.managed_ebs_volume] : []
    content {
      name = volume_configuration.value.volume_name

      managed_ebs_volume {
        role_arn         = local.create_infra_role ? aws_iam_role.infrastructure[0].arn : local.infrastructure_arn
        encrypted        = true
        kms_key_id       = volume_configuration.value.kms_key_arn != "" ? volume_configuration.value.kms_key_arn : null
        size_in_gb       = volume_configuration.value.size_in_gb > 0 ? volume_configuration.value.size_in_gb : null
        snapshot_id      = volume_configuration.value.snapshot_id != "" ? volume_configuration.value.snapshot_id : null
        volume_type      = volume_configuration.value.volume_type
        iops             = volume_configuration.value.iops > 0 ? volume_configuration.value.iops : null
        throughput       = volume_configuration.value.throughput > 0 ? volume_configuration.value.throughput : null
        file_system_type = volume_configuration.value.file_system_type

        tag_specifications {
          resource_type  = "volume"
          propagate_tags = "SERVICE"
          tags           = local.workload_tags[each.key]
        }
      }
    }
  }

  dynamic "placement_constraints" {
    for_each = each.value.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression != "" ? placement_constraints.value.expression : null
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = each.value.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field != "" ? ordered_placement_strategy.value.field : null
    }
  }

  tags = local.workload_tags[each.key]

  # The task starts as soon as the service exists; its roles must be complete.
  depends_on = [
    aws_ecs_cluster_capacity_providers.this,
    aws_iam_role_policy_attachment.execution,
    aws_iam_role_policy.execution_module,
    aws_iam_role_policy_attachment.execution_managed,
    aws_iam_role_policy.task_module,
    aws_iam_role_policy.task_custom,
    aws_iam_role_policy_attachment.task_managed,
    aws_iam_role_policy_attachment.infrastructure,
    aws_cloudwatch_log_group.this,
  ]
  # END SERVICE BODY

  lifecycle {
    ignore_changes = [desired_count]
  }
}
