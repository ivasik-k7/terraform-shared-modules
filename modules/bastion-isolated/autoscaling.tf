# asg so the box self-heals and we can scale to 0 off-hours. spot via mixed
# policy if you want to shave the bill further.

resource "aws_autoscaling_group" "this" {
  count = local.create ? 1 : 0

  name_prefix         = "${var.name}-"
  vpc_zone_identifier = var.subnet_ids

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_cooldown          = var.default_cooldown
  termination_policies      = var.termination_policies
  capacity_rebalance        = var.capacity_rebalance
  enabled_metrics           = var.enabled_metrics
  target_group_arns         = var.target_group_arns

  dynamic "launch_template" {
    for_each = local.use_mixed_instances ? [] : [1]
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  # spot / multiple types
  dynamic "mixed_instances_policy" {
    for_each = local.use_mixed_instances ? [1] : []
    content {
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this[0].id
          version            = aws_launch_template.this[0].latest_version
        }
        dynamic "override" {
          for_each = local.override_types
          content {
            instance_type = override.value
          }
        }
      }
      instances_distribution {
        on_demand_base_capacity                  = var.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.spot_enabled ? var.on_demand_percentage_above_base_capacity : 100
        spot_allocation_strategy                 = var.spot_allocation_strategy
      }
    }
  }

  # roll the fleet when the baked ami changes
  dynamic "instance_refresh" {
    for_each = var.instance_refresh != null ? [var.instance_refresh] : []
    content {
      strategy = instance_refresh.value.strategy
      preferences {
        min_healthy_percentage = instance_refresh.value.min_healthy_percentage
        instance_warmup        = instance_refresh.value.instance_warmup
        auto_rollback          = instance_refresh.value.auto_rollback
      }
    }
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, { "Name" = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # the schedules own capacity. if TF reverts min/max/desired, an apply during
    # off-hours just turns the box (and the bill) back on. change the schedules,
    # not these inputs - they only seed the initial size.
    ignore_changes = [min_size, max_size, desired_capacity]

    precondition {
      condition     = var.health_check_type != "ELB" || length(var.target_group_arns) > 0
      error_message = "health_check_type = \"ELB\" requires target_group_arns so the ASG has a load balancer to health-check against."
    }
  }
}
