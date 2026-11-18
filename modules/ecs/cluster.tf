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
      condition     = local.default_is_preset ? true : contains(concat(keys(var.ec2_capacity_providers), keys(var.managed_instances_capacity_providers), var.external_capacity_providers), var.default_capacity)
      error_message = "default_capacity is \"${var.default_capacity}\", which is neither a preset (on_demand, balanced, spot_preferred, spot_only) nor a capacity provider key or external_capacity_providers name."
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

# A Managed Instances provider belongs to the cluster it is created in, and is
# still put on the cluster's provider list to be used.
# https://docs.aws.amazon.com/AmazonECS/latest/developerguide/getting-started-managed-instances-cli.html
resource "aws_ecs_capacity_provider" "managed_instances" {
  for_each = local.managed_instances

  name    = local.mi_provider_name[each.key]
  cluster = aws_ecs_cluster.this[0].name

  managed_instances_provider {
    infrastructure_role_arn = local.infrastructure_role_in_use
    # The instances carry the tags, so their cost is attributable.
    propagate_tags = "CAPACITY_PROVIDER"

    dynamic "infrastructure_optimization" {
      for_each = each.value.scale_in_after_seconds != null ? [each.value.scale_in_after_seconds] : []
      content {
        scale_in_after = infrastructure_optimization.value
      }
    }

    instance_launch_template {
      ec2_instance_profile_arn = each.value.instance_profile_arn != "" ? each.value.instance_profile_arn : aws_iam_instance_profile.instance[0].arn
      capacity_option_type     = each.value.capacity_option_type
      monitoring               = each.value.monitoring

      network_configuration {
        subnets         = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids
        security_groups = length(each.value.security_group_ids) > 0 ? each.value.security_group_ids : var.security_group_ids
      }

      dynamic "storage_configuration" {
        for_each = each.value.storage_size_gib > 0 ? [each.value.storage_size_gib] : []
        content {
          storage_size_gib = storage_configuration.value
        }
      }

      dynamic "instance_requirements" {
        for_each = each.value.instance_requirements.vcpu_min > 0 ? [each.value.instance_requirements] : []
        content {
          vcpu_count {
            min = instance_requirements.value.vcpu_min
            max = instance_requirements.value.vcpu_max == -1 ? null : instance_requirements.value.vcpu_max
          }

          memory_mib {
            min = instance_requirements.value.memory_mib_min
            max = instance_requirements.value.memory_mib_max == -1 ? null : instance_requirements.value.memory_mib_max
          }

          dynamic "accelerator_count" {
            for_each = instance_requirements.value.accelerator_count_min + instance_requirements.value.accelerator_count_max > -2 ? [instance_requirements.value] : []
            content {
              min = accelerator_count.value.accelerator_count_min == -1 ? null : accelerator_count.value.accelerator_count_min
              max = accelerator_count.value.accelerator_count_max == -1 ? null : accelerator_count.value.accelerator_count_max
            }
          }

          cpu_manufacturers                                = length(instance_requirements.value.cpu_manufacturers) > 0 ? instance_requirements.value.cpu_manufacturers : null
          instance_generations                             = length(instance_requirements.value.instance_generations) > 0 ? instance_requirements.value.instance_generations : null
          burstable_performance                            = instance_requirements.value.burstable_performance
          bare_metal                                       = instance_requirements.value.bare_metal
          allowed_instance_types                           = length(instance_requirements.value.allowed_instance_types) > 0 ? instance_requirements.value.allowed_instance_types : null
          excluded_instance_types                          = length(instance_requirements.value.excluded_instance_types) > 0 ? instance_requirements.value.excluded_instance_types : null
          accelerator_types                                = length(instance_requirements.value.accelerator_types) > 0 ? instance_requirements.value.accelerator_types : null
          accelerator_manufacturers                        = length(instance_requirements.value.accelerator_manufacturers) > 0 ? instance_requirements.value.accelerator_manufacturers : null
          spot_max_price_percentage_over_lowest_price      = instance_requirements.value.spot_max_price_percentage_over_lowest_price == -1 ? null : instance_requirements.value.spot_max_price_percentage_over_lowest_price
          on_demand_max_price_percentage_over_lowest_price = instance_requirements.value.on_demand_max_price_percentage_over_lowest_price == -1 ? null : instance_requirements.value.on_demand_max_price_percentage_over_lowest_price
        }
      }
    }
  }

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = length(each.value.subnet_ids) + length(var.subnet_ids) > 0
      error_message = "managed_instances_capacity_providers.${each.key} has no subnets: set subnet_ids on it or on the module."
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.infrastructure,
    aws_iam_role_policy.infrastructure_module,
    aws_iam_role_policy_attachment.instance,
  ]
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = local.create ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = concat(["FARGATE", "FARGATE_SPOT"], [for k, p in aws_ecs_capacity_provider.ec2 : p.name], [for k, p in aws_ecs_capacity_provider.managed_instances : p.name], var.external_capacity_providers)

  dynamic "default_capacity_provider_strategy" {
    for_each = local.cluster_default_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}
