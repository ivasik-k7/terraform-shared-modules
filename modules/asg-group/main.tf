# A universal EC2 Auto Scaling Group: launch template + ASG + optional instance
# IAM + optional security group + metrics. Workload-agnostic - drive the role,
# user-data, tags, and scaling to fit ECS capacity, a web/app fleet, batch
# workers, self-managed k8s nodes, etc. Outputs the ASG ARN so consumers
# (e.g. ecs-orchestrator capacity providers) can reference it.

locals {
  create                = var.create
  create_iam            = var.create && var.instance_profile_name == null && var.create_instance_profile
  create_security_group = var.create && var.create_security_group

  instance_profile_name = var.instance_profile_name != null ? var.instance_profile_name : (
    local.create_iam ? aws_iam_instance_profile.this[0].name : null
  )

  security_group_ids = concat(
    local.create_security_group ? [aws_security_group.this[0].id] : [],
    var.security_group_ids,
  )

  ami = var.ami != null ? var.ami : (local.create ? nonsensitive(data.aws_ssm_parameter.ami[0].value) : null)

  override_instance_types = length(var.instance_types) > 0 ? var.instance_types : [var.instance_type]

  user_data = var.user_data != null ? base64encode(var.user_data) : var.user_data_base64

  tags = var.tags
}

data "aws_ssm_parameter" "ami" {
  count = local.create && var.ami == null ? 1 : 0
  name  = var.ami_ssm_parameter
}

# ----------------------------------------------------------------------------
# IAM (optional): instance role + profile, policies driven entirely by the caller
# ----------------------------------------------------------------------------

data "aws_iam_policy_document" "assume" {
  count = local.create_iam ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = local.create_iam ? 1 : 0

  # iam role name_prefix is capped at 38 chars - truncate so a long var.name
  # doesn't break instance-profile creation.
  name_prefix          = substr("${var.name}-", 0, 38)
  assume_role_policy   = data.aws_iam_policy_document.assume[0].json
  permissions_boundary = var.iam_permissions_boundary
  tags                 = local.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.create_iam ? var.iam_role_policies : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = local.create_iam && var.iam_role_inline_policy != null ? 1 : 0

  name_prefix = "${var.name}-"
  role        = aws_iam_role.this[0].id
  policy      = var.iam_role_inline_policy
}

resource "aws_iam_instance_profile" "this" {
  count = local.create_iam ? 1 : 0

  name_prefix = substr("${var.name}-", 0, 38)
  role        = aws_iam_role.this[0].name
  tags        = local.tags
}

# ----------------------------------------------------------------------------
# Security group (optional; no inbound by default, egress allow-all)
# ----------------------------------------------------------------------------

resource "aws_security_group" "this" {
  count = local.create_security_group ? 1 : 0

  name_prefix = "${coalesce(var.security_group_name, var.name)}-"
  description = "Node group ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(local.tags, { Name = var.name })

  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "this" {
  for_each = local.create_security_group ? var.security_group_ingress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description
}

resource "aws_vpc_security_group_egress_rule" "this" {
  for_each = local.create_security_group ? var.security_group_egress_rules : {}

  security_group_id            = aws_security_group.this[0].id
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  ip_protocol                  = each.value.ip_protocol
  cidr_ipv4                    = each.value.cidr_ipv4
  cidr_ipv6                    = each.value.cidr_ipv6
  referenced_security_group_id = each.value.referenced_security_group_id
  prefix_list_id               = each.value.prefix_list_id
  description                  = each.value.description
}

# ----------------------------------------------------------------------------
# Launch template: instance shape (IMDSv2, encrypted root, extra volumes)
# ----------------------------------------------------------------------------

resource "aws_launch_template" "this" {
  count = local.create ? 1 : 0

  name_prefix   = "${var.name}-"
  image_id      = local.ami
  instance_type = var.instance_type
  key_name      = var.key_name
  user_data     = local.user_data
  ebs_optimized = var.ebs_optimized

  # SGs go top-level normally; when forcing a public-IP setting they must move
  # into the network_interface (the two are mutually exclusive in an LT).
  vpc_security_group_ids = var.associate_public_ip_address == null ? local.security_group_ids : null

  dynamic "network_interfaces" {
    for_each = var.associate_public_ip_address != null ? [1] : []
    content {
      device_index                = 0
      associate_public_ip_address = var.associate_public_ip_address
      security_groups             = local.security_group_ids
      delete_on_termination       = true
    }
  }

  dynamic "iam_instance_profile" {
    for_each = local.instance_profile_name != null ? [1] : []
    content {
      name = local.instance_profile_name
    }
  }

  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = var.metadata_tags_enabled ? "enabled" : "disabled"
  }

  dynamic "placement" {
    for_each = var.placement_group != null || var.tenancy != null ? [1] : []
    content {
      group_name = var.placement_group
      tenancy    = var.tenancy
    }
  }

  dynamic "cpu_options" {
    for_each = var.cpu_options != null ? [var.cpu_options] : []
    content {
      core_count       = cpu_options.value.core_count
      threads_per_core = cpu_options.value.threads_per_core
    }
  }

  block_device_mappings {
    device_name = var.root_volume_device_name
    ebs {
      volume_size           = var.root_volume_size
      volume_type           = var.root_volume_type
      iops                  = var.root_volume_iops
      throughput            = var.root_volume_throughput
      encrypted             = var.root_volume_encrypted
      kms_key_id            = var.kms_key_id
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = { for d in var.ebs_block_devices : d.device_name => d }
    content {
      device_name = block_device_mappings.value.device_name
      ebs {
        volume_size           = block_device_mappings.value.volume_size
        volume_type           = block_device_mappings.value.volume_type
        iops                  = block_device_mappings.value.iops
        throughput            = block_device_mappings.value.throughput
        encrypted             = block_device_mappings.value.encrypted
        kms_key_id            = block_device_mappings.value.kms_key_id
        snapshot_id           = block_device_mappings.value.snapshot_id
        delete_on_termination = block_device_mappings.value.delete_on_termination
      }
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.tags, { Name = var.name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.tags, { Name = var.name })
  }

  tags = local.tags

  lifecycle {
    create_before_destroy = true

    precondition {
      condition     = local.ami != null
      error_message = "Provide ami, or a valid ami_ssm_parameter that resolves to an AMI id."
    }

    # fail closed like the ec2 module: never let instances fall back to the
    # permissive VPC default security group.
    precondition {
      condition     = length(local.security_group_ids) > 0
      error_message = "Provide security_group_ids or set create_security_group = true; instances must not fall back to the VPC default security group."
    }
  }
}

# ----------------------------------------------------------------------------
# Auto Scaling Group
# ----------------------------------------------------------------------------

resource "aws_autoscaling_group" "this" {
  count = local.create ? 1 : 0

  name_prefix           = "${var.name}-"
  vpc_zone_identifier   = length(var.subnet_ids) > 0 ? var.subnet_ids : null
  availability_zones    = var.availability_zones
  min_size              = var.min_size
  max_size              = var.max_size
  desired_capacity      = var.desired_capacity
  protect_from_scale_in = var.protect_from_scale_in
  capacity_rebalance    = var.spot != null ? true : var.capacity_rebalance

  health_check_type         = var.health_check_type
  health_check_grace_period = var.health_check_grace_period
  default_cooldown          = var.default_cooldown
  default_instance_warmup   = var.default_instance_warmup
  termination_policies      = var.termination_policies
  target_group_arns         = var.target_group_arns
  suspended_processes       = var.suspended_processes
  enabled_metrics           = var.enabled_metrics
  metrics_granularity       = var.metrics_granularity

  wait_for_capacity_timeout = var.wait_for_capacity_timeout
  min_elb_capacity          = var.min_elb_capacity
  wait_for_elb_capacity     = var.wait_for_elb_capacity

  # plain on-demand single-type fleet
  dynamic "launch_template" {
    for_each = var.spot == null ? [1] : []
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  # mixed on-demand + spot across instance_types
  dynamic "mixed_instances_policy" {
    for_each = var.spot != null ? [1] : []
    content {
      launch_template {
        launch_template_specification {
          launch_template_id = aws_launch_template.this[0].id
          version            = aws_launch_template.this[0].latest_version
        }
        dynamic "override" {
          for_each = local.override_instance_types
          content {
            instance_type     = override.value
            weighted_capacity = contains(keys(var.instance_weights), override.value) ? tostring(var.instance_weights[override.value]) : null
          }
        }
      }
      instances_distribution {
        on_demand_base_capacity                  = var.spot.on_demand_base_capacity
        on_demand_percentage_above_base_capacity = var.spot.on_demand_percentage_above_base_capacity
        spot_allocation_strategy                 = var.spot.allocation_strategy
        spot_max_price                           = var.spot.spot_max_price
        spot_instance_pools                      = var.spot.spot_instance_pools
      }
    }
  }

  dynamic "instance_refresh" {
    for_each = var.instance_refresh != null ? [var.instance_refresh] : []
    content {
      strategy = instance_refresh.value.strategy
      preferences {
        min_healthy_percentage = instance_refresh.value.min_healthy_percentage
        max_healthy_percentage = instance_refresh.value.max_healthy_percentage
        instance_warmup        = instance_refresh.value.instance_warmup
        auto_rollback          = instance_refresh.value.auto_rollback
      }
    }
  }

  dynamic "warm_pool" {
    for_each = var.warm_pool != null ? [var.warm_pool] : []
    content {
      pool_state                  = warm_pool.value.pool_state
      min_size                    = warm_pool.value.min_size
      max_group_prepared_capacity = warm_pool.value.max_group_prepared_capacity
    }
  }

  dynamic "initial_lifecycle_hook" {
    for_each = var.initial_lifecycle_hooks
    content {
      name                    = initial_lifecycle_hook.key
      lifecycle_transition    = initial_lifecycle_hook.value.lifecycle_transition
      default_result          = initial_lifecycle_hook.value.default_result
      heartbeat_timeout       = initial_lifecycle_hook.value.heartbeat_timeout
      notification_target_arn = initial_lifecycle_hook.value.notification_target_arn
      role_arn                = initial_lifecycle_hook.value.role_arn
      notification_metadata   = initial_lifecycle_hook.value.notification_metadata
    }
  }

  dynamic "tag" {
    for_each = merge(local.tags, var.autoscaling_group_tags, { Name = var.name })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    create_before_destroy = true
    # an autoscaler / capacity provider / scheduled action owns the live count
    ignore_changes = [desired_capacity]

    # an ASG needs somewhere to place instances - fail fast instead of an
    # opaque apply error.
    precondition {
      # try(), not &&: terraform < 1.10 evaluates eagerly and length() rejects null
      condition     = length(var.subnet_ids) > 0 || try(length(var.availability_zones) > 0, false)
      error_message = "Provide subnet_ids (recommended) or availability_zones for the ASG."
    }
  }
}
