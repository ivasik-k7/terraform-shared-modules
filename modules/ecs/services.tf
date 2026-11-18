# Four resources with one body, because lifecycle.ignore_changes cannot be
# conditional: an autoscaled service must not have desired_count reset by every
# apply, and a service deployed by an external pipeline must not have its
# running revision reset. tests/service_parity.py fails when the bodies drift.
#
# force_new_deployment is always true: the provider refuses a change of
# capacity_provider_strategy without it. With it, every update of the service
# starts a deployment.
# https://github.com/hashicorp/terraform-provider-aws/blob/v6.57.1/internal/service/ecs/service.go

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
  sigint_rollback                    = each.value.workload == "service" ? each.value.deployment.sigint_rollback : null

  deployment_controller {
    type = "ECS"
  }

  # Sent for every service: an omitted block keeps the strategy last applied.
  dynamic "deployment_configuration" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.strategy == "ROLLING" ? null : deployment_configuration.value.bake_time_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.strategy == "CANARY" ? [deployment_configuration.value] : []
        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.strategy == "LINEAR" ? [deployment_configuration.value] : []
        content {
          step_percent              = linear_configuration.value.linear_step_percent
          step_bake_time_in_minutes = linear_configuration.value.linear_step_bake_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks
        content {
          hook_target_arn  = lifecycle_hook.value.function_arn
          role_arn         = local.infrastructure_role_in_use
          lifecycle_stages = lifecycle_hook.value.stages
          hook_details     = lifecycle_hook.value.details != "" ? lifecycle_hook.value.details : null
        }
      }
    }
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

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.alternate_target_group_arn != "" ? [load_balancer.value] : []
        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule_arn != "" ? advanced_configuration.value.test_listener_rule_arn : null
          role_arn                   = local.infrastructure_role_in_use
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = contains(keys(local.service_registry), each.key) ? [local.service_registry[each.key]] : []
    content {
      registry_arn   = service_registries.value.registry_arn
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
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

      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_logs != null ? [service_connect_configuration.value.access_logs] : []
        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters ? "ENABLED" : "DISABLED"
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

            dynamic "test_traffic_rules" {
              for_each = service.value.test_traffic_header != null ? [service.value.test_traffic_header] : []
              content {
                header {
                  name = test_traffic_rules.value.name
                  value {
                    exact = test_traffic_rules.value.value
                  }
                }
              }
            }
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
        role_arn         = local.infrastructure_role_in_use
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
    aws_iam_role_policy.infrastructure_module,
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
  sigint_rollback                    = each.value.workload == "service" ? each.value.deployment.sigint_rollback : null

  deployment_controller {
    type = "ECS"
  }

  # Sent for every service: an omitted block keeps the strategy last applied.
  dynamic "deployment_configuration" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.strategy == "ROLLING" ? null : deployment_configuration.value.bake_time_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.strategy == "CANARY" ? [deployment_configuration.value] : []
        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.strategy == "LINEAR" ? [deployment_configuration.value] : []
        content {
          step_percent              = linear_configuration.value.linear_step_percent
          step_bake_time_in_minutes = linear_configuration.value.linear_step_bake_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks
        content {
          hook_target_arn  = lifecycle_hook.value.function_arn
          role_arn         = local.infrastructure_role_in_use
          lifecycle_stages = lifecycle_hook.value.stages
          hook_details     = lifecycle_hook.value.details != "" ? lifecycle_hook.value.details : null
        }
      }
    }
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

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.alternate_target_group_arn != "" ? [load_balancer.value] : []
        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule_arn != "" ? advanced_configuration.value.test_listener_rule_arn : null
          role_arn                   = local.infrastructure_role_in_use
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = contains(keys(local.service_registry), each.key) ? [local.service_registry[each.key]] : []
    content {
      registry_arn   = service_registries.value.registry_arn
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
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

      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_logs != null ? [service_connect_configuration.value.access_logs] : []
        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters ? "ENABLED" : "DISABLED"
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

            dynamic "test_traffic_rules" {
              for_each = service.value.test_traffic_header != null ? [service.value.test_traffic_header] : []
              content {
                header {
                  name = test_traffic_rules.value.name
                  value {
                    exact = test_traffic_rules.value.value
                  }
                }
              }
            }
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
        role_arn         = local.infrastructure_role_in_use
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
    aws_iam_role_policy.infrastructure_module,
    aws_cloudwatch_log_group.this,
  ]
  # END SERVICE BODY

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "static_ignored" {
  for_each = local.static_ignored

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
  sigint_rollback                    = each.value.workload == "service" ? each.value.deployment.sigint_rollback : null

  deployment_controller {
    type = "ECS"
  }

  # Sent for every service: an omitted block keeps the strategy last applied.
  dynamic "deployment_configuration" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.strategy == "ROLLING" ? null : deployment_configuration.value.bake_time_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.strategy == "CANARY" ? [deployment_configuration.value] : []
        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.strategy == "LINEAR" ? [deployment_configuration.value] : []
        content {
          step_percent              = linear_configuration.value.linear_step_percent
          step_bake_time_in_minutes = linear_configuration.value.linear_step_bake_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks
        content {
          hook_target_arn  = lifecycle_hook.value.function_arn
          role_arn         = local.infrastructure_role_in_use
          lifecycle_stages = lifecycle_hook.value.stages
          hook_details     = lifecycle_hook.value.details != "" ? lifecycle_hook.value.details : null
        }
      }
    }
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

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.alternate_target_group_arn != "" ? [load_balancer.value] : []
        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule_arn != "" ? advanced_configuration.value.test_listener_rule_arn : null
          role_arn                   = local.infrastructure_role_in_use
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = contains(keys(local.service_registry), each.key) ? [local.service_registry[each.key]] : []
    content {
      registry_arn   = service_registries.value.registry_arn
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
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

      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_logs != null ? [service_connect_configuration.value.access_logs] : []
        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters ? "ENABLED" : "DISABLED"
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

            dynamic "test_traffic_rules" {
              for_each = service.value.test_traffic_header != null ? [service.value.test_traffic_header] : []
              content {
                header {
                  name = test_traffic_rules.value.name
                  value {
                    exact = test_traffic_rules.value.value
                  }
                }
              }
            }
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
        role_arn         = local.infrastructure_role_in_use
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
    aws_iam_role_policy.infrastructure_module,
    aws_cloudwatch_log_group.this,
  ]
  # END SERVICE BODY

  lifecycle {
    ignore_changes = [task_definition]
  }
}

resource "aws_ecs_service" "autoscaled_ignored" {
  for_each = local.autoscaled_ignored

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
  sigint_rollback                    = each.value.workload == "service" ? each.value.deployment.sigint_rollback : null

  deployment_controller {
    type = "ECS"
  }

  # Sent for every service: an omitted block keeps the strategy last applied.
  dynamic "deployment_configuration" {
    for_each = each.value.workload == "service" ? [each.value.deployment] : []
    content {
      strategy             = deployment_configuration.value.strategy
      bake_time_in_minutes = deployment_configuration.value.strategy == "ROLLING" ? null : deployment_configuration.value.bake_time_minutes

      dynamic "canary_configuration" {
        for_each = deployment_configuration.value.strategy == "CANARY" ? [deployment_configuration.value] : []
        content {
          canary_percent              = canary_configuration.value.canary_percent
          canary_bake_time_in_minutes = canary_configuration.value.canary_bake_minutes
        }
      }

      dynamic "linear_configuration" {
        for_each = deployment_configuration.value.strategy == "LINEAR" ? [deployment_configuration.value] : []
        content {
          step_percent              = linear_configuration.value.linear_step_percent
          step_bake_time_in_minutes = linear_configuration.value.linear_step_bake_minutes
        }
      }

      dynamic "lifecycle_hook" {
        for_each = deployment_configuration.value.lifecycle_hooks
        content {
          hook_target_arn  = lifecycle_hook.value.function_arn
          role_arn         = local.infrastructure_role_in_use
          lifecycle_stages = lifecycle_hook.value.stages
          hook_details     = lifecycle_hook.value.details != "" ? lifecycle_hook.value.details : null
        }
      }
    }
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

      dynamic "advanced_configuration" {
        for_each = load_balancer.value.alternate_target_group_arn != "" ? [load_balancer.value] : []
        content {
          alternate_target_group_arn = advanced_configuration.value.alternate_target_group_arn
          production_listener_rule   = advanced_configuration.value.production_listener_rule_arn
          test_listener_rule         = advanced_configuration.value.test_listener_rule_arn != "" ? advanced_configuration.value.test_listener_rule_arn : null
          role_arn                   = local.infrastructure_role_in_use
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = contains(keys(local.service_registry), each.key) ? [local.service_registry[each.key]] : []
    content {
      registry_arn   = service_registries.value.registry_arn
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
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

      dynamic "access_log_configuration" {
        for_each = service_connect_configuration.value.access_logs != null ? [service_connect_configuration.value.access_logs] : []
        content {
          format                   = access_log_configuration.value.format
          include_query_parameters = access_log_configuration.value.include_query_parameters ? "ENABLED" : "DISABLED"
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

            dynamic "test_traffic_rules" {
              for_each = service.value.test_traffic_header != null ? [service.value.test_traffic_header] : []
              content {
                header {
                  name = test_traffic_rules.value.name
                  value {
                    exact = test_traffic_rules.value.value
                  }
                }
              }
            }
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
        role_arn         = local.infrastructure_role_in_use
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
    aws_iam_role_policy.infrastructure_module,
    aws_cloudwatch_log_group.this,
  ]
  # END SERVICE BODY

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }
}
