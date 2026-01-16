# ============================================================================
# AWS ECS Terraform Module
# ============================================================================
# This module provisions ECS clusters, services, task definitions, capacity
# providers, auto-scaling, and CloudWatch monitoring.
# ============================================================================

# -----------------------------------------------------------------------------
# ECS Cluster
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  dynamic "configuration" {
    for_each = var.cluster_configuration != null ? [var.cluster_configuration] : []
    content {
      dynamic "execute_command_configuration" {
        for_each = configuration.value.enable_execute_command ? [1] : []
        content {
          kms_key_id = configuration.value.kms_key_id

          dynamic "log_configuration" {
            for_each = configuration.value.log_configuration != null ? [configuration.value.log_configuration] : []
            content {
              cloud_watch_log_group_name     = log_configuration.value.cloud_watch_log_group_name
              cloud_watch_encryption_enabled = log_configuration.value.cloud_watch_encryption_enabled
              s3_bucket_name                 = log_configuration.value.s3_bucket_name
              s3_bucket_encryption_enabled   = log_configuration.value.s3_bucket_encryption_enabled
              s3_key_prefix                  = log_configuration.value.s3_key_prefix
            }
          }
        }
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = var.cluster_name
    }
  )
}

# -----------------------------------------------------------------------------
# Capacity Providers (EC2)
# -----------------------------------------------------------------------------
resource "aws_ecs_capacity_provider" "this" {
  for_each = {
    for k, v in var.capacity_providers : k => v
    if v.type == "EC2" && v.auto_scaling_group_arn != null
  }

  name = "${var.cluster_name}-${each.key}"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = each.value.auto_scaling_group_arn
    managed_termination_protection = each.value.managed_termination_protection

    dynamic "managed_scaling" {
      for_each = each.value.managed_scaling != null ? [each.value.managed_scaling] : []
      content {
        maximum_scaling_step_size = managed_scaling.value.maximum_scaling_step_size
        minimum_scaling_step_size = managed_scaling.value.minimum_scaling_step_size
        status                    = managed_scaling.value.status
        target_capacity           = managed_scaling.value.target_capacity
        instance_warmup_period    = managed_scaling.value.instance_warmup_period
      }
    }
  }

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-${each.key}"
    }
  )
}

# -----------------------------------------------------------------------------
# Cluster Capacity Providers Association
# -----------------------------------------------------------------------------
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = concat(
    [for k, v in var.capacity_providers : k if v.type == "FARGATE" || v.type == "FARGATE_SPOT"],
    [for k, v in aws_ecs_capacity_provider.this : v.name]
  )

  dynamic "default_capacity_provider_strategy" {
    for_each = var.capacity_providers
    content {
      capacity_provider = default_capacity_provider_strategy.value.type == "EC2" ? aws_ecs_capacity_provider.this[default_capacity_provider_strategy.key].name : default_capacity_provider_strategy.key
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}

# -----------------------------------------------------------------------------
# IAM Role - Task Execution
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task_execution" {
  count = var.create_task_execution_role && var.task_execution_role_arn == null ? 1 : 0

  name = "${var.cluster_name}-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_default" {
  count = var.create_task_execution_role && var.task_execution_role_arn == null ? 1 : 0

  role       = aws_iam_role.task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy_attachment" "task_execution_additional" {
  for_each = var.create_task_execution_role && var.task_execution_role_arn == null ? toset(var.task_execution_role_policies) : []

  role       = aws_iam_role.task_execution[0].name
  policy_arn = each.value
}

# -----------------------------------------------------------------------------
# IAM Role - Task Role (per service)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "task" {
  for_each = var.services

  name = "${var.cluster_name}-${each.key}-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = merge(
    var.tags,
    each.value.tags
  )
}

resource "aws_iam_role_policy_attachment" "task" {
  for_each = merge([
    for service_name, policies in var.task_role_policies : {
      for policy in policies : "${service_name}-${policy}" => {
        role       = service_name
        policy_arn = policy
      }
    }
  ]...)

  role       = aws_iam_role.task[each.value.role].name
  policy_arn = each.value.policy_arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Groups
# -----------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "this" {
  for_each = var.create_cloudwatch_log_groups ? var.services : {}

  name              = "/ecs/${var.cluster_name}/${each.key}"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_id

  tags = merge(
    var.tags,
    each.value.tags
  )
}

# -----------------------------------------------------------------------------
# Task Definitions
# -----------------------------------------------------------------------------
resource "aws_ecs_task_definition" "this" {
  for_each = var.services

  family                   = each.value.task_definition_family
  network_mode             = each.value.network_mode
  requires_compatibilities = each.value.requires_compatibilities
  cpu                      = each.value.task_cpu
  memory                   = each.value.task_memory
  execution_role_arn       = var.task_execution_role_arn != null ? var.task_execution_role_arn : (var.create_task_execution_role ? aws_iam_role.task_execution[0].arn : null)
  task_role_arn            = aws_iam_role.task[each.key].arn

  container_definitions = jsonencode([
    for container in each.value.container_definitions : merge(
      {
        name      = container.name
        image     = container.image
        cpu       = container.cpu
        memory    = container.memory
        essential = container.essential
      },
      length(container.port_mappings) > 0 ? {
        portMappings = [
          for pm in container.port_mappings : {
            containerPort = pm.container_port
            hostPort      = pm.host_port != null ? pm.host_port : pm.container_port
            protocol      = pm.protocol
            appProtocol   = pm.app_protocol
          }
        ]
      } : {},
      length(container.environment) > 0 ? {
        environment = container.environment
      } : {},
      length(container.secrets) > 0 ? {
        secrets = container.secrets
      } : {},
      length(container.mount_points) > 0 ? {
        mountPoints = container.mount_points
      } : {},
      length(container.volumes_from) > 0 ? {
        volumesFrom = container.volumes_from
      } : {},
      container.log_configuration != null ? {
        logConfiguration = merge(
          {
            logDriver = container.log_configuration.log_driver
            options   = container.log_configuration.options
          },
          length(container.log_configuration.secret_options) > 0 ? {
            secretOptions = container.log_configuration.secret_options
          } : {}
        )
        } : var.create_cloudwatch_log_groups ? {
        logConfiguration = {
          logDriver = "awslogs"
          options = {
            "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
            "awslogs-region"        = data.aws_region.current.name
            "awslogs-stream-prefix" = container.name
          }
        }
      } : {},
      container.health_check != null ? {
        healthCheck = {
          command     = container.health_check.command
          interval    = container.health_check.interval
          timeout     = container.health_check.timeout
          retries     = container.health_check.retries
          startPeriod = container.health_check.start_period
        }
      } : {},
      length(container.depends_on) > 0 ? {
        dependsOn = container.depends_on
      } : {}
    )
  ])

  dynamic "volume" {
    for_each = each.value.volumes
    content {
      name      = volume.value.name
      host_path = volume.value.host_path

      dynamic "docker_volume_configuration" {
        for_each = volume.value.docker_volume_configuration != null ? [volume.value.docker_volume_configuration] : []
        content {
          scope         = docker_volume_configuration.value.scope
          autoprovision = docker_volume_configuration.value.autoprovision
          driver        = docker_volume_configuration.value.driver
          driver_opts   = docker_volume_configuration.value.driver_opts
          labels        = docker_volume_configuration.value.labels
        }
      }

      dynamic "efs_volume_configuration" {
        for_each = volume.value.efs_volume_configuration != null ? [volume.value.efs_volume_configuration] : []
        content {
          file_system_id          = efs_volume_configuration.value.file_system_id
          root_directory          = efs_volume_configuration.value.root_directory
          transit_encryption      = efs_volume_configuration.value.transit_encryption
          transit_encryption_port = efs_volume_configuration.value.transit_encryption_port

          dynamic "authorization_config" {
            for_each = efs_volume_configuration.value.authorization_config != null ? [efs_volume_configuration.value.authorization_config] : []
            content {
              access_point_id = authorization_config.value.access_point_id
              iam             = authorization_config.value.iam
            }
          }
        }
      }
    }
  }

  tags = merge(
    var.tags,
    each.value.tags
  )
}

# -----------------------------------------------------------------------------
# ECS Services
# -----------------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  for_each = var.services

  name             = each.key
  cluster          = aws_ecs_cluster.this.id
  task_definition  = aws_ecs_task_definition.this[each.key].arn
  desired_count    = each.value.desired_count
  launch_type      = each.value.capacity_provider_strategy == null ? each.value.launch_type : null
  platform_version = contains(each.value.requires_compatibilities, "FARGATE") ? each.value.platform_version : null

  dynamic "capacity_provider_strategy" {
    for_each = each.value.capacity_provider_strategy != null ? each.value.capacity_provider_strategy : []
    content {
      capacity_provider = capacity_provider_strategy.value.capacity_provider
      weight            = capacity_provider_strategy.value.weight
      base              = capacity_provider_strategy.value.base
    }
  }

  network_configuration {
    subnets          = each.value.network_configuration.subnets
    security_groups  = each.value.network_configuration.security_groups
    assign_public_ip = each.value.network_configuration.assign_public_ip
  }

  dynamic "load_balancer" {
    for_each = each.value.load_balancers
    content {
      target_group_arn = load_balancer.value.target_group_arn
      container_name   = load_balancer.value.container_name
      container_port   = load_balancer.value.container_port
    }
  }

  dynamic "service_registries" {
    for_each = each.value.service_registries
    content {
      registry_arn   = service_registries.value.registry_arn
      port           = service_registries.value.port
      container_name = service_registries.value.container_name
      container_port = service_registries.value.container_port
    }
  }

  deployment_maximum_percent         = each.value.deployment_configuration != null ? each.value.deployment_configuration.maximum_percent : null
  deployment_minimum_healthy_percent = each.value.deployment_configuration != null ? each.value.deployment_configuration.minimum_healthy_percent : null

  dynamic "deployment_circuit_breaker" {
    for_each = each.value.deployment_configuration != null && each.value.deployment_configuration.deployment_circuit_breaker != null ? [each.value.deployment_configuration.deployment_circuit_breaker] : []
    content {
      enable   = deployment_circuit_breaker.value.enable
      rollback = deployment_circuit_breaker.value.rollback
    }
  }

  health_check_grace_period_seconds = each.value.health_check_grace_period_seconds
  scheduling_strategy               = each.value.scheduling_strategy
  enable_execute_command            = each.value.enable_execute_command
  propagate_tags                    = each.value.propagate_tags
  force_new_deployment              = each.value.force_new_deployment
  wait_for_steady_state             = each.value.wait_for_steady_state

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

  tags = merge(
    var.tags,
    each.value.tags
  )

  depends_on = [
    aws_iam_role_policy_attachment.task_execution_default,
    aws_iam_role_policy_attachment.task_execution_additional
  ]
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------
data "aws_region" "current" {}
