# ---------------------------------------------------------------------------
# Launch template
# ---------------------------------------------------------------------------

resource "aws_launch_template" "this" {
  count = local.create ? 1 : 0

  name_prefix            = "${var.name}-"
  description            = "Launch template of Auto Scaling group ${var.name}."
  update_default_version = true

  image_id      = local.ami
  instance_type = local.mixed ? null : local.instance_types[0]
  key_name      = var.key_name != "" ? var.key_name : null
  user_data     = local.user_data
  ebs_optimized = var.ebs_optimized != "" ? var.ebs_optimized : null

  # Security groups sit on the template unless the public IP is forced, which
  # needs a network interface that carries them instead.
  vpc_security_group_ids = var.public_ip == "" ? var.security_group_ids : null

  dynamic "network_interfaces" {
    for_each = var.public_ip != "" ? [var.public_ip] : []
    content {
      device_index                = 0
      associate_public_ip_address = network_interfaces.value == "assign" ? "true" : "false"
      security_groups             = var.security_group_ids
      delete_on_termination       = "true"
    }
  }

  dynamic "iam_instance_profile" {
    for_each = local.instance_profile_name != "" ? [local.instance_profile_name] : []
    content {
      name = iam_instance_profile.value
    }
  }

  monitoring {
    enabled = var.detailed_monitoring
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = var.metadata_tags ? "enabled" : "disabled"
  }

  dynamic "credit_specification" {
    for_each = local.burstable ? [var.cpu_credits] : []
    content {
      cpu_credits = credit_specification.value
    }
  }

  dynamic "maintenance_options" {
    for_each = var.auto_recovery != "" ? [var.auto_recovery] : []
    content {
      auto_recovery = maintenance_options.value
    }
  }

  dynamic "placement" {
    for_each = var.placement_group != "" || var.tenancy != "" ? [1] : []
    content {
      group_name = var.placement_group != "" && !startswith(var.placement_group, "pg-") ? var.placement_group : null
      group_id   = startswith(var.placement_group, "pg-") ? var.placement_group : null
      tenancy    = var.tenancy != "" ? var.tenancy : null
    }
  }

  dynamic "cpu_options" {
    for_each = anytrue([var.cpu_options.core_count != -1, var.cpu_options.threads_per_core != -1, var.cpu_options.nested_virtualization != ""]) ? [var.cpu_options] : []
    content {
      core_count            = cpu_options.value.core_count != -1 ? cpu_options.value.core_count : null
      threads_per_core      = cpu_options.value.threads_per_core != -1 ? cpu_options.value.threads_per_core : null
      nested_virtualization = cpu_options.value.nested_virtualization != "" ? cpu_options.value.nested_virtualization : null
    }
  }

  dynamic "network_performance_options" {
    for_each = var.bandwidth_weighting != "" ? [var.bandwidth_weighting] : []
    content {
      bandwidth_weighting = network_performance_options.value
    }
  }

  dynamic "capacity_reservation_specification" {
    for_each = var.capacity_reservation.preference != "" || length(var.capacity_reservation.reservation_ids) + length(var.capacity_reservation.resource_group_arns) > 0 ? [var.capacity_reservation] : []
    content {
      capacity_reservation_preference = capacity_reservation_specification.value.preference != "" ? capacity_reservation_specification.value.preference : null

      dynamic "capacity_reservation_target" {
        for_each = concat(
          [for id in capacity_reservation_specification.value.reservation_ids : { id = id, group = null }],
          [for arn in capacity_reservation_specification.value.resource_group_arns : { id = null, group = arn }],
        )
        content {
          capacity_reservation_id                 = capacity_reservation_target.value.id
          capacity_reservation_resource_group_arn = capacity_reservation_target.value.group
        }
      }
    }
  }

  block_device_mappings {
    device_name = var.root_volume.device_name
    ebs {
      volume_size           = var.root_volume.size_gib
      volume_type           = var.root_volume.type
      iops                  = var.root_volume.iops != -1 ? var.root_volume.iops : null
      throughput            = var.root_volume.throughput != -1 ? var.root_volume.throughput : null
      encrypted             = "true"
      kms_key_id            = var.kms_key_arn != "" ? var.kms_key_arn : null
      delete_on_termination = "true"
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.ebs_volumes
    content {
      device_name = block_device_mappings.key
      ebs {
        volume_size           = block_device_mappings.value.size_gib
        volume_type           = block_device_mappings.value.type
        iops                  = block_device_mappings.value.iops != -1 ? block_device_mappings.value.iops : null
        throughput            = block_device_mappings.value.throughput != -1 ? block_device_mappings.value.throughput : null
        snapshot_id           = block_device_mappings.value.snapshot_id != "" ? block_device_mappings.value.snapshot_id : null
        encrypted             = "true"
        kms_key_id            = var.kms_key_arn != "" ? var.kms_key_arn : null
        delete_on_termination = block_device_mappings.value.delete_on_termination ? "true" : "false"
      }
    }
  }

  dynamic "tag_specifications" {
    for_each = toset(["instance", "volume", "network-interface"])
    content {
      resource_type = tag_specifications.value
      tags          = local.instance_tags
    }
  }

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.ami != ""
      error_message = "ami_ssm_parameter ${var.ami_ssm_parameter} resolved to an empty value; it must hold an AMI ID."
    }

    precondition {
      condition     = length(local.missing_required_tags) == 0
      error_message = "tags is missing ${join(", ", local.missing_required_tags)}, which required_tag_keys makes mandatory. Without them the instances are unattributable in Cost Explorer and invisible to tag-based SCPs."
    }

    precondition {
      condition     = alltrue([for t in keys(var.instance_weights) : contains(local.instance_types, t)])
      error_message = "instance_weights names types that are not in instance_types (${join(", ", [for t in keys(var.instance_weights) : t if !contains(local.instance_types, t)])}); with instance_requirements, weights do not apply at all."
    }

    precondition {
      # https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html
      condition     = !var.warm_pool.enabled ? true : (local.uses_spot ? false : length(var.instance_weights) == 0)
      error_message = "A warm pool cannot be used with Spot or with instance weights. Make the fleet all on-demand and unweighted, or turn the warm pool off."
    }

    precondition {
      condition     = var.ignore_desired_capacity_changes ? true : alltrue([length(var.target_tracking_policies) == 0, !var.predictive_scaling.enabled, alltrue([for a in values(var.scheduled_actions) : a.desired_capacity == -1])])
      error_message = "Scaling policies and scheduled desired_capacity changes move the instance count, and with ignore_desired_capacity_changes = false every apply moves it back. Set ignore_desired_capacity_changes = true, or drop the scaling."
    }
  }
}

# ---------------------------------------------------------------------------
# Auto Scaling group
# ---------------------------------------------------------------------------

# Two resources with one body, because lifecycle.ignore_changes cannot be
# conditional: in aws_autoscaling_group.this something else owns the instance
# count, in .static Terraform does. tests/group_parity.py fails when the bodies
# drift apart.

resource "aws_autoscaling_group" "this" {
  count = local.create ? (var.ignore_desired_capacity_changes ? 1 : 0) : 0

  # BEGIN GROUP BODY
  name_prefix         = "${var.name}-"
  vpc_zone_identifier = var.subnet_ids

  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = local.desired_capacity
  protect_from_scale_in = var.protect_from_scale_in
  capacity_rebalance    = local.capacity_rebalance
  max_instance_lifetime = var.max_instance_lifetime != 0 ? var.max_instance_lifetime : null

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.default_instance_warmup != -1 ? var.default_instance_warmup : null
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  target_group_arns         = var.target_group_arns
  service_linked_role_arn   = var.service_linked_role_arn != "" ? var.service_linked_role_arn : null

  enabled_metrics     = var.enabled_metrics
  metrics_granularity = "1Minute"

  wait_for_capacity_timeout        = var.wait_for_capacity_timeout != "" ? var.wait_for_capacity_timeout : null
  wait_for_elb_capacity            = var.wait_for_elb_capacity != -1 ? var.wait_for_elb_capacity : null
  ignore_failed_scaling_activities = var.ignore_failed_scaling_activities

  dynamic "availability_zone_distribution" {
    for_each = var.availability_zone_distribution != "" ? [var.availability_zone_distribution] : []
    content {
      capacity_distribution_strategy = availability_zone_distribution.value
    }
  }

  dynamic "instance_lifecycle_policy" {
    for_each = var.terminate_hook_abandon != "" ? [var.terminate_hook_abandon] : []
    content {
      retention_triggers {
        terminate_hook_abandon = instance_lifecycle_policy.value
      }
    }
  }

  dynamic "instance_maintenance_policy" {
    for_each = var.instance_maintenance_policy.min_healthy_percentage != -1 ? [var.instance_maintenance_policy] : []
    content {
      min_healthy_percentage = instance_maintenance_policy.value.min_healthy_percentage
      max_healthy_percentage = instance_maintenance_policy.value.max_healthy_percentage
    }
  }

  dynamic "launch_template" {
    for_each = local.mixed ? [] : [1]
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = local.mixed ? [1] : []
    content {
      instances_distribution {
        on_demand_base_capacity                  = var.purchase_options.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.purchase_options.on_demand_percentage_above_base_capacity
        on_demand_allocation_strategy            = var.purchase_options.on_demand_allocation_strategy != "" ? var.purchase_options.on_demand_allocation_strategy : null
        spot_allocation_strategy                 = var.purchase_options.spot_allocation_strategy
        spot_max_price                           = var.purchase_options.spot_max_price != "" ? var.purchase_options.spot_max_price : null
        spot_instance_pools                      = var.purchase_options.spot_instance_pools != 0 ? var.purchase_options.spot_instance_pools : null
      }

      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this[0].id
          version            = aws_launch_template.this[0].latest_version
        }

        dynamic "override" {
          for_each = local.instance_types
          content {
            instance_type     = override.value
            weighted_capacity = contains(keys(var.instance_weights), override.value) ? tostring(var.instance_weights[override.value]) : null
          }
        }

        dynamic "override" {
          for_each = local.attribute_based ? [var.instance_requirements] : []
          content {
            instance_requirements {
              vcpu_count {
                min = override.value.vcpu_min
                max = override.value.vcpu_max != -1 ? override.value.vcpu_max : null
              }
              memory_mib {
                min = override.value.memory_mib_min
                max = override.value.memory_mib_max != -1 ? override.value.memory_mib_max : null
              }
              cpu_manufacturers                                = length(override.value.cpu_manufacturers) > 0 ? override.value.cpu_manufacturers : null
              instance_generations                             = override.value.instance_generations
              burstable_performance                            = override.value.burstable_performance
              bare_metal                                       = override.value.bare_metal
              allowed_instance_types                           = length(override.value.allowed_instance_types) > 0 ? override.value.allowed_instance_types : null
              excluded_instance_types                          = length(override.value.excluded_instance_types) > 0 ? override.value.excluded_instance_types : null
              spot_max_price_percentage_over_lowest_price      = override.value.spot_max_price_percentage_over_lowest_price != -1 ? override.value.spot_max_price_percentage_over_lowest_price : null
              on_demand_max_price_percentage_over_lowest_price = override.value.on_demand_max_price_percentage_over_lowest_price != -1 ? override.value.on_demand_max_price_percentage_over_lowest_price : null
            }
          }
        }
      }
    }
  }

  dynamic "instance_refresh" {
    for_each = var.instance_refresh.enabled ? [var.instance_refresh] : []
    content {
      strategy = "Rolling"
      triggers = length(instance_refresh.value.triggers) > 0 ? instance_refresh.value.triggers : null

      preferences {
        min_healthy_percentage       = instance_refresh.value.min_healthy_percentage
        max_healthy_percentage       = instance_refresh.value.max_healthy_percentage
        instance_warmup              = instance_refresh.value.instance_warmup != -1 ? tostring(instance_refresh.value.instance_warmup) : null
        skip_matching                = instance_refresh.value.skip_matching
        auto_rollback                = instance_refresh.value.auto_rollback
        checkpoint_percentages       = length(instance_refresh.value.checkpoint_percentages) > 0 ? instance_refresh.value.checkpoint_percentages : null
        checkpoint_delay             = instance_refresh.value.checkpoint_delay_seconds != -1 ? tostring(instance_refresh.value.checkpoint_delay_seconds) : null
        scale_in_protected_instances = instance_refresh.value.scale_in_protected_instances
        standby_instances            = instance_refresh.value.standby_instances

        dynamic "alarm_specification" {
          for_each = length(instance_refresh.value.alarm_names) > 0 ? [instance_refresh.value.alarm_names] : []
          content {
            alarms = alarm_specification.value
          }
        }
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.warm_pool.enabled ? [var.warm_pool] : []
    content {
      pool_state                  = warm_pool.value.pool_state
      min_size                    = warm_pool.value.min_size
      max_group_prepared_capacity = warm_pool.value.max_group_prepared_capacity != -1 ? warm_pool.value.max_group_prepared_capacity : null

      instance_reuse_policy {
        reuse_on_scale_in = warm_pool.value.reuse_on_scale_in
      }
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = local.initial_hooks
    content {
      name                    = initial_lifecycle_hook.key
      lifecycle_transition    = local.hook_transition[initial_lifecycle_hook.value.transition]
      default_result          = initial_lifecycle_hook.value.default_result
      heartbeat_timeout       = initial_lifecycle_hook.value.heartbeat_timeout
      notification_target_arn = initial_lifecycle_hook.value.notification_target_arn != "" ? initial_lifecycle_hook.value.notification_target_arn : null
      role_arn                = initial_lifecycle_hook.value.role_arn != "" ? initial_lifecycle_hook.value.role_arn : null
      notification_metadata   = initial_lifecycle_hook.value.notification_metadata != "" ? initial_lifecycle_hook.value.notification_metadata : null
    }
  }

  dynamic "tag" {
    for_each = local.group_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  # END GROUP BODY

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

resource "aws_autoscaling_group" "static" {
  count = local.create ? (var.ignore_desired_capacity_changes ? 0 : 1) : 0

  # BEGIN GROUP BODY
  name_prefix         = "${var.name}-"
  vpc_zone_identifier = var.subnet_ids

  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = local.desired_capacity
  protect_from_scale_in = var.protect_from_scale_in
  capacity_rebalance    = local.capacity_rebalance
  max_instance_lifetime = var.max_instance_lifetime != 0 ? var.max_instance_lifetime : null

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_instance_warmup   = var.default_instance_warmup != -1 ? var.default_instance_warmup : null
  termination_policies      = var.termination_policies
  suspended_processes       = var.suspended_processes
  target_group_arns         = var.target_group_arns
  service_linked_role_arn   = var.service_linked_role_arn != "" ? var.service_linked_role_arn : null

  enabled_metrics     = var.enabled_metrics
  metrics_granularity = "1Minute"

  wait_for_capacity_timeout        = var.wait_for_capacity_timeout != "" ? var.wait_for_capacity_timeout : null
  wait_for_elb_capacity            = var.wait_for_elb_capacity != -1 ? var.wait_for_elb_capacity : null
  ignore_failed_scaling_activities = var.ignore_failed_scaling_activities

  dynamic "availability_zone_distribution" {
    for_each = var.availability_zone_distribution != "" ? [var.availability_zone_distribution] : []
    content {
      capacity_distribution_strategy = availability_zone_distribution.value
    }
  }

  dynamic "instance_lifecycle_policy" {
    for_each = var.terminate_hook_abandon != "" ? [var.terminate_hook_abandon] : []
    content {
      retention_triggers {
        terminate_hook_abandon = instance_lifecycle_policy.value
      }
    }
  }

  dynamic "instance_maintenance_policy" {
    for_each = var.instance_maintenance_policy.min_healthy_percentage != -1 ? [var.instance_maintenance_policy] : []
    content {
      min_healthy_percentage = instance_maintenance_policy.value.min_healthy_percentage
      max_healthy_percentage = instance_maintenance_policy.value.max_healthy_percentage
    }
  }

  dynamic "launch_template" {
    for_each = local.mixed ? [] : [1]
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  dynamic "mixed_instances_policy" {
    for_each = local.mixed ? [1] : []
    content {
      instances_distribution {
        on_demand_base_capacity                  = var.purchase_options.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.purchase_options.on_demand_percentage_above_base_capacity
        on_demand_allocation_strategy            = var.purchase_options.on_demand_allocation_strategy != "" ? var.purchase_options.on_demand_allocation_strategy : null
        spot_allocation_strategy                 = var.purchase_options.spot_allocation_strategy
        spot_max_price                           = var.purchase_options.spot_max_price != "" ? var.purchase_options.spot_max_price : null
        spot_instance_pools                      = var.purchase_options.spot_instance_pools != 0 ? var.purchase_options.spot_instance_pools : null
      }

      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this[0].id
          version            = aws_launch_template.this[0].latest_version
        }

        dynamic "override" {
          for_each = local.instance_types
          content {
            instance_type     = override.value
            weighted_capacity = contains(keys(var.instance_weights), override.value) ? tostring(var.instance_weights[override.value]) : null
          }
        }

        dynamic "override" {
          for_each = local.attribute_based ? [var.instance_requirements] : []
          content {
            instance_requirements {
              vcpu_count {
                min = override.value.vcpu_min
                max = override.value.vcpu_max != -1 ? override.value.vcpu_max : null
              }
              memory_mib {
                min = override.value.memory_mib_min
                max = override.value.memory_mib_max != -1 ? override.value.memory_mib_max : null
              }
              cpu_manufacturers                                = length(override.value.cpu_manufacturers) > 0 ? override.value.cpu_manufacturers : null
              instance_generations                             = override.value.instance_generations
              burstable_performance                            = override.value.burstable_performance
              bare_metal                                       = override.value.bare_metal
              allowed_instance_types                           = length(override.value.allowed_instance_types) > 0 ? override.value.allowed_instance_types : null
              excluded_instance_types                          = length(override.value.excluded_instance_types) > 0 ? override.value.excluded_instance_types : null
              spot_max_price_percentage_over_lowest_price      = override.value.spot_max_price_percentage_over_lowest_price != -1 ? override.value.spot_max_price_percentage_over_lowest_price : null
              on_demand_max_price_percentage_over_lowest_price = override.value.on_demand_max_price_percentage_over_lowest_price != -1 ? override.value.on_demand_max_price_percentage_over_lowest_price : null
            }
          }
        }
      }
    }
  }

  dynamic "instance_refresh" {
    for_each = var.instance_refresh.enabled ? [var.instance_refresh] : []
    content {
      strategy = "Rolling"
      triggers = length(instance_refresh.value.triggers) > 0 ? instance_refresh.value.triggers : null

      preferences {
        min_healthy_percentage       = instance_refresh.value.min_healthy_percentage
        max_healthy_percentage       = instance_refresh.value.max_healthy_percentage
        instance_warmup              = instance_refresh.value.instance_warmup != -1 ? tostring(instance_refresh.value.instance_warmup) : null
        skip_matching                = instance_refresh.value.skip_matching
        auto_rollback                = instance_refresh.value.auto_rollback
        checkpoint_percentages       = length(instance_refresh.value.checkpoint_percentages) > 0 ? instance_refresh.value.checkpoint_percentages : null
        checkpoint_delay             = instance_refresh.value.checkpoint_delay_seconds != -1 ? tostring(instance_refresh.value.checkpoint_delay_seconds) : null
        scale_in_protected_instances = instance_refresh.value.scale_in_protected_instances
        standby_instances            = instance_refresh.value.standby_instances

        dynamic "alarm_specification" {
          for_each = length(instance_refresh.value.alarm_names) > 0 ? [instance_refresh.value.alarm_names] : []
          content {
            alarms = alarm_specification.value
          }
        }
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.warm_pool.enabled ? [var.warm_pool] : []
    content {
      pool_state                  = warm_pool.value.pool_state
      min_size                    = warm_pool.value.min_size
      max_group_prepared_capacity = warm_pool.value.max_group_prepared_capacity != -1 ? warm_pool.value.max_group_prepared_capacity : null

      instance_reuse_policy {
        reuse_on_scale_in = warm_pool.value.reuse_on_scale_in
      }
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = local.initial_hooks
    content {
      name                    = initial_lifecycle_hook.key
      lifecycle_transition    = local.hook_transition[initial_lifecycle_hook.value.transition]
      default_result          = initial_lifecycle_hook.value.default_result
      heartbeat_timeout       = initial_lifecycle_hook.value.heartbeat_timeout
      notification_target_arn = initial_lifecycle_hook.value.notification_target_arn != "" ? initial_lifecycle_hook.value.notification_target_arn : null
      role_arn                = initial_lifecycle_hook.value.role_arn != "" ? initial_lifecycle_hook.value.role_arn : null
      notification_metadata   = initial_lifecycle_hook.value.notification_metadata != "" ? initial_lifecycle_hook.value.notification_metadata : null
    }
  }

  dynamic "tag" {
    for_each = local.group_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  # END GROUP BODY

  lifecycle {
    create_before_destroy = true
  }
}
