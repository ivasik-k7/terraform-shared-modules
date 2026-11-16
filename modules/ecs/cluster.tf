resource "aws_ecs_cluster" "this" {
  count = local.create ? 1 : 0

  name = var.name

  setting {
    name  = "containerInsights"
    value = var.container_insights
  }

  dynamic "configuration" {
    for_each = local.cluster_configuration ? [1] : []
    content {
      dynamic "execute_command_configuration" {
        for_each = local.exec_configuration ? [var.execute_command] : []
        content {
          kms_key_id = execute_command_configuration.value.kms_key_arn != "" ? execute_command_configuration.value.kms_key_arn : null
          logging    = execute_command_configuration.value.logging

          dynamic "log_configuration" {
            for_each = execute_command_configuration.value.logging == "OVERRIDE" ? [execute_command_configuration.value] : []
            content {
              cloud_watch_log_group_name     = log_configuration.value.log_group_name != "" ? log_configuration.value.log_group_name : null
              cloud_watch_encryption_enabled = log_configuration.value.log_group_name != "" ? log_configuration.value.encrypt_logs : null
              s3_bucket_name                 = log_configuration.value.s3_bucket_name != "" ? log_configuration.value.s3_bucket_name : null
              s3_bucket_encryption_enabled   = log_configuration.value.s3_bucket_name != "" ? log_configuration.value.encrypt_logs : null
              s3_key_prefix                  = log_configuration.value.s3_key_prefix != "" ? log_configuration.value.s3_key_prefix : null
            }
          }
        }
      }

      dynamic "managed_storage_configuration" {
        for_each = local.storage_configuration ? [1] : []
        content {
          fargate_ephemeral_storage_kms_key_id = var.fargate_ephemeral_storage_kms_key_arn != "" ? var.fargate_ephemeral_storage_kms_key_arn : null
          kms_key_id                           = var.managed_storage_kms_key_arn != "" ? var.managed_storage_kms_key_arn : null
        }
      }
    }
  }

  dynamic "service_connect_defaults" {
    for_each = var.service_connect_namespace_arn != "" ? [var.service_connect_namespace_arn] : []
    content {
      namespace = service_connect_defaults.value
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = length(local.missing_required_tag_keys) == 0
      error_message = "tags is missing ${join(", ", local.missing_required_tag_keys)}, which required_tag_keys makes mandatory. Without them the cluster's tasks are unattributable in Cost Explorer and invisible to tag-based SCPs."
    }

    precondition {
      condition     = local.default_is_preset ? true : contains(keys(var.ec2_capacity_providers), var.default_capacity)
      error_message = "default_capacity is \"${var.default_capacity}\", which is neither a preset (on_demand, balanced, spot_preferred, spot_only) nor an ec2_capacity_providers key."
    }

    precondition {
      condition     = alltrue([for k, s in local.services : s.network_mode != "awsvpc" ? true : length(local.subnets[k]) > 0])
      error_message = "An awsvpc workload has no subnets: set subnet_ids on the module or on the service (${join(", ", [for k, s in local.services : k if s.network_mode == "awsvpc" ? length(local.subnets[k]) == 0 : false])})."
    }

    precondition {
      condition     = alltrue([for k, s in local.services : s.workload != "daemon" ? true : (s.capacity == "" ? length(s.capacity_provider_strategy) == 0 : false)])
      error_message = "A daemon runs one task on every container instance of the cluster, so capacity and capacity_provider_strategy do not apply to it (${join(", ", [for k, s in local.services : k if s.workload == "daemon" ? (s.capacity != "" ? true : length(s.capacity_provider_strategy) > 0) : false])})."
    }

    precondition {
      condition     = alltrue([for k, s in local.services : length(s.containers) > 0 ? true : length(s.volumes) == 0])
      error_message = "The image shortcut has no mount points, so volumes on it are never mounted. Use containers with mount_points (${join(", ", [for k, s in local.services : k if length(s.containers) == 0 ? length(s.volumes) > 0 : false])})."
    }

    precondition {
      condition     = alltrue([for k, s in local.exec_services : alltrue([for c in values(local.containers[k]) : !c.readonly_root_filesystem])])
      error_message = "ECS Exec cannot run in a container with a read-only root file system; the SSM agent writes to it. Turn off enable_execute_command or readonly_root_filesystem on: ${join(", ", [for k, s in local.exec_services : k if anytrue([for c in values(local.containers[k]) : c.readonly_root_filesystem])])}."
    }
  }
}

resource "aws_ecs_capacity_provider" "ec2" {
  for_each = local.create ? var.ec2_capacity_providers : {}

  name = local.ec2_provider_name[each.key]

  auto_scaling_group_provider {
    auto_scaling_group_arn         = each.value.auto_scaling_group_arn
    managed_termination_protection = each.value.managed_termination_protection
    managed_draining               = each.value.managed_draining

    managed_scaling {
      status                    = each.value.managed_scaling.status
      target_capacity           = each.value.managed_scaling.target_capacity
      minimum_scaling_step_size = each.value.managed_scaling.minimum_scaling_step_size
      maximum_scaling_step_size = each.value.managed_scaling.maximum_scaling_step_size
      instance_warmup_period    = each.value.managed_scaling.instance_warmup_period
    }
  }

  tags = local.common_tags
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = local.create ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = concat(["FARGATE", "FARGATE_SPOT"], [for k, p in aws_ecs_capacity_provider.ec2 : p.name])

  dynamic "default_capacity_provider_strategy" {
    for_each = local.cluster_default_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}
