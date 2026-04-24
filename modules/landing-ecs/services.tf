resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "${var.cluster_name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = each.value.cpu
  memory                   = each.value.memory
  execution_role_arn       = local.service_execution_role_arns[each.key]
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

# ignore_changes on desired_count because App Autoscaling owns it post-apply.
# Otherwise every plan diffs the count and flaps it back.
resource "aws_ecs_service" "autoscaled" {
  for_each = local.services_autoscaled

  name                               = local.service_common_args[each.key].name
  cluster                            = local.service_common_args[each.key].cluster
  task_definition                    = local.service_common_args[each.key].task_definition
  desired_count                      = local.service_common_args[each.key].desired_count
  health_check_grace_period_seconds  = local.service_common_args[each.key].health_check_grace_period_seconds
  enable_execute_command             = local.service_common_args[each.key].enable_execute_command
  deployment_minimum_healthy_percent = local.service_common_args[each.key].deployment_minimum_healthy_percent
  deployment_maximum_percent         = local.service_common_args[each.key].deployment_maximum_percent
  propagate_tags                     = local.service_common_args[each.key].propagate_tags

  deployment_controller {
    type = each.value.deployment_controller
  }

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
    for_each = concat(
      each.value.load_balancer != null ? [each.value.load_balancer] : [],
      each.value.additional_load_balancers,
    )
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
            dns_name = each.value.service_connect_alias
            port     = each.value.port
          }
        }
      }
    }
  }

  tags = each.value.tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_shared_managed,
    aws_iam_role_policy_attachment.task_execution_service_managed,
  ]

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Mirror of the autoscaled resource, minus the ignore_changes. Terraform
# owns desired_count for these.
resource "aws_ecs_service" "static" {
  for_each = local.services_not_autoscaled

  name                               = local.service_common_args[each.key].name
  cluster                            = local.service_common_args[each.key].cluster
  task_definition                    = local.service_common_args[each.key].task_definition
  desired_count                      = local.service_common_args[each.key].desired_count
  health_check_grace_period_seconds  = local.service_common_args[each.key].health_check_grace_period_seconds
  enable_execute_command             = local.service_common_args[each.key].enable_execute_command
  deployment_minimum_healthy_percent = local.service_common_args[each.key].deployment_minimum_healthy_percent
  deployment_maximum_percent         = local.service_common_args[each.key].deployment_maximum_percent
  propagate_tags                     = local.service_common_args[each.key].propagate_tags

  deployment_controller {
    type = each.value.deployment_controller
  }

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
    for_each = concat(
      each.value.load_balancer != null ? [each.value.load_balancer] : [],
      each.value.additional_load_balancers,
    )
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
            dns_name = each.value.service_connect_alias
            port     = each.value.port
          }
        }
      }
    }
  }

  tags = each.value.tags

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_shared_managed,
    aws_iam_role_policy_attachment.task_execution_service_managed,
  ]
}
