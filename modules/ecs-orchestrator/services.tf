# two copies: autoscaled ignores desired_count (App Auto Scaling owns it), static
# lets terraform manage it. bodies must stay identical - tests/service_parity.py.

resource "aws_ecs_service" "autoscaled" {
  for_each = local.services_autoscaled

  name            = each.key
  cluster         = aws_ecs_cluster.this[0].id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = each.value.launch_type

  enable_execute_command             = each.value.enable_execute_command
  force_new_deployment               = each.value.force_new_deployment
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds
  propagate_tags                     = each.value.propagate_tags
  wait_for_steady_state              = each.value.wait_for_steady_state
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  deployment_controller {
    type = each.value.deployment_controller
  }

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.deployment_controller == "ECS" ? [1] : []
    content {
      enable   = each.value.enable_circuit_breaker
      rollback = each.value.enable_rollback
    }
  }

  # alarms: ECS controller only, like the circuit breaker
  dynamic "alarms" {
    for_each = each.value.deployment_controller == "ECS" && each.value.deployment_alarms != null ? [each.value.deployment_alarms] : []
    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.service_capacity_strategy[each.key]
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "network_configuration" {
    for_each = each.value.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = local.service_subnets[each.key]
      security_groups  = local.service_security_groups[each.key]
      assign_public_ip = each.value.assign_public_ip
    }
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect != null ? [each.value.service_connect] : []
    content {
      enabled   = service_connect_configuration.value.enabled
      namespace = local.service_connect_namespace[each.key]
      dynamic "service" {
        for_each = service_connect_configuration.value.services
        content {
          port_name      = service.value.port_name
          discovery_name = service.value.discovery_name
          dynamic "client_alias" {
            for_each = service.value.client_alias != null ? [service.value.client_alias] : []
            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port
            }
          }
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_discovery != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.this[each.key].arn
    }
  }

  dynamic "volume_configuration" {
    for_each = each.value.managed_ebs_volume != null ? [each.value.managed_ebs_volume] : []
    content {
      name = volume_configuration.value.name
      managed_ebs_volume {
        role_arn         = volume_configuration.value.role_arn
        size_in_gb       = volume_configuration.value.size_in_gb
        volume_type      = volume_configuration.value.volume_type
        iops             = volume_configuration.value.iops
        throughput       = volume_configuration.value.throughput
        encrypted        = volume_configuration.value.encrypted
        kms_key_id       = volume_configuration.value.kms_key_id
        snapshot_id      = volume_configuration.value.snapshot_id
        file_system_type = volume_configuration.value.file_system_type
        tag_specifications {
          resource_type = "volume"
          tags          = merge(local.common_tags, volume_configuration.value.tags)
        }
      }
    }
  }

  dynamic "placement_constraints" {
    for_each = each.value.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = each.value.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = each.key })

  lifecycle {
    ignore_changes = [desired_count]
  }
}

resource "aws_ecs_service" "static" {
  for_each = local.services_static

  name            = each.key
  cluster         = aws_ecs_cluster.this[0].id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = each.value.desired_count
  launch_type     = each.value.launch_type

  enable_execute_command             = each.value.enable_execute_command
  force_new_deployment               = each.value.force_new_deployment
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds
  propagate_tags                     = each.value.propagate_tags
  wait_for_steady_state              = each.value.wait_for_steady_state
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent

  deployment_controller {
    type = each.value.deployment_controller
  }

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.deployment_controller == "ECS" ? [1] : []
    content {
      enable   = each.value.enable_circuit_breaker
      rollback = each.value.enable_rollback
    }
  }

  # alarms: ECS controller only, like the circuit breaker
  dynamic "alarms" {
    for_each = each.value.deployment_controller == "ECS" && each.value.deployment_alarms != null ? [each.value.deployment_alarms] : []
    content {
      alarm_names = alarms.value.alarm_names
      enable      = alarms.value.enable
      rollback    = alarms.value.rollback
    }
  }

  dynamic "capacity_provider_strategy" {
    for_each = local.service_capacity_strategy[each.key]
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  dynamic "network_configuration" {
    for_each = each.value.network_mode == "awsvpc" ? [1] : []
    content {
      subnets          = local.service_subnets[each.key]
      security_groups  = local.service_security_groups[each.key]
      assign_public_ip = each.value.assign_public_ip
    }
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect != null ? [each.value.service_connect] : []
    content {
      enabled   = service_connect_configuration.value.enabled
      namespace = local.service_connect_namespace[each.key]
      dynamic "service" {
        for_each = service_connect_configuration.value.services
        content {
          port_name      = service.value.port_name
          discovery_name = service.value.discovery_name
          dynamic "client_alias" {
            for_each = service.value.client_alias != null ? [service.value.client_alias] : []
            content {
              dns_name = client_alias.value.dns_name
              port     = client_alias.value.port
            }
          }
        }
      }
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_discovery != null ? [1] : []
    content {
      registry_arn = aws_service_discovery_service.this[each.key].arn
    }
  }

  dynamic "volume_configuration" {
    for_each = each.value.managed_ebs_volume != null ? [each.value.managed_ebs_volume] : []
    content {
      name = volume_configuration.value.name
      managed_ebs_volume {
        role_arn         = volume_configuration.value.role_arn
        size_in_gb       = volume_configuration.value.size_in_gb
        volume_type      = volume_configuration.value.volume_type
        iops             = volume_configuration.value.iops
        throughput       = volume_configuration.value.throughput
        encrypted        = volume_configuration.value.encrypted
        kms_key_id       = volume_configuration.value.kms_key_id
        snapshot_id      = volume_configuration.value.snapshot_id
        file_system_type = volume_configuration.value.file_system_type
        tag_specifications {
          resource_type = "volume"
          tags          = merge(local.common_tags, volume_configuration.value.tags)
        }
      }
    }
  }

  dynamic "placement_constraints" {
    for_each = each.value.placement_constraints
    content {
      type       = placement_constraints.value.type
      expression = placement_constraints.value.expression
    }
  }

  dynamic "ordered_placement_strategy" {
    for_each = each.value.ordered_placement_strategy
    content {
      type  = ordered_placement_strategy.value.type
      field = ordered_placement_strategy.value.field
    }
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = each.key })
}
