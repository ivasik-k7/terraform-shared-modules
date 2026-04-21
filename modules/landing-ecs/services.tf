resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "${var.cluster_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn
  container_definitions    = local.container_definitions[each.key]

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = each.value.cpu_architecture
  }

  dynamic "ephemeral_storage" {
    for_each = each.value.ephemeral_storage_gib > 21 ? [1] : []

    content {
      size_in_gib = each.value.ephemeral_storage_gib
    }
  }

  dynamic "volume" {
    for_each = each.value.volumes

    content {
      name = volume.value.name

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs_volume_configuration != null ? [volume.value.efs_volume_configuration] : []

        content {
          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.access_point_id != null ? "/" : efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = 2049

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.access_point_id != null ? [1] : []

            content {
              access_point_id = efs_volume_configuration.value.access_point_id
              iam             = "ENABLED"
            }
          }
        }
      }
    }
  }

  tags = each.value.tags

  lifecycle {
    create_before_destroy = true
  }
}

# Autoscaled services are a separate resource so we can ignore_changes on
# desired_count. Without that, Terraform and App Autoscaling keep fighting
# each other on every apply.
resource "aws_ecs_service" "autoscaled" {
  for_each = local.services_autoscaled

  name                               = "${var.cluster_name}-${each.key}"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this[each.key].arn
  desired_count                      = each.value.desired_count
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds
  enable_execute_command             = each.value.enable_exec
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent
  propagate_tags                     = var.propagate_tags == "NONE" ? null : var.propagate_tags

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_strategies[each.value.capacity_strategy]

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets = each.value.subnets
    security_groups = concat(
      each.value.security_groups,
      each.value.create_security_group ? [aws_security_group.service[each.key].id] : []
    )
    assign_public_ip = each.value.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancer != null ? [each.value.load_balancer] : []

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = coalesce(load_balancer.value.container_name, each.key)
      container_port   = load_balancer.value.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = each.value.enable_circuit_breaker
    rollback = each.value.enable_rollback
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect_enabled ? [1] : []

    content {
      enabled   = true
      namespace = var.service_connect_namespace

      dynamic "service" {
        for_each = each.value.port != null ? [1] : []

        content {
          port_name = each.key

          client_alias {
            dns_name = each.key
            port     = each.value.port
          }
        }
      }
    }
  }

  tags = each.value.tags

  depends_on = [aws_iam_role_policy_attachment.task_execution_managed]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Services without autoscaling — Terraform owns desired_count directly.
resource "aws_ecs_service" "static" {
  for_each = local.services_not_autoscaled

  name                               = "${var.cluster_name}-${each.key}"
  cluster                            = aws_ecs_cluster.this.id
  task_definition                    = aws_ecs_task_definition.this[each.key].arn
  desired_count                      = each.value.desired_count
  health_check_grace_period_seconds  = each.value.health_check_grace_period_seconds
  enable_execute_command             = each.value.enable_exec
  deployment_minimum_healthy_percent = each.value.deployment_minimum_healthy_percent
  deployment_maximum_percent         = each.value.deployment_maximum_percent
  propagate_tags                     = var.propagate_tags == "NONE" ? null : var.propagate_tags

  dynamic "capacity_provider_strategy" {
    for_each = local.capacity_strategies[each.value.capacity_strategy]

    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets = each.value.subnets
    security_groups = concat(
      each.value.security_groups,
      each.value.create_security_group ? [aws_security_group.service[each.key].id] : []
    )
    assign_public_ip = each.value.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancer != null ? [each.value.load_balancer] : []

    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = coalesce(load_balancer.value.container_name, each.key)
      container_port   = load_balancer.value.container_port
    }
  }

  deployment_circuit_breaker {
    enable   = each.value.enable_circuit_breaker
    rollback = each.value.enable_rollback
  }

  dynamic "service_connect_configuration" {
    for_each = each.value.service_connect_enabled ? [1] : []

    content {
      enabled   = true
      namespace = var.service_connect_namespace

      dynamic "service" {
        for_each = each.value.port != null ? [1] : []

        content {
          port_name = each.key

          client_alias {
            dns_name = each.key
            port     = each.value.port
          }
        }
      }
    }
  }

  tags = each.value.tags

  depends_on = [aws_iam_role_policy_attachment.task_execution_managed]
}
