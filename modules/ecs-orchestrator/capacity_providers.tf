# ec2 capacity providers built from ASG ARNs the caller passes (the ASG itself
# lives in the asg/ec2 modules). fargate is registered by a toggle; pre-existing
# providers can be registered by name too.

resource "aws_ecs_capacity_provider" "ec2" {
  for_each = local.create ? var.ec2_capacity_providers : {}

  name = each.key

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

locals {
  cluster_capacity_providers = distinct(concat(
    var.enable_fargate_capacity_providers ? ["FARGATE", "FARGATE_SPOT"] : [],
    [for k, v in aws_ecs_capacity_provider.ec2 : k],
    var.external_capacity_providers,
  ))
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  count = local.create ? 1 : 0

  cluster_name       = aws_ecs_cluster.this[0].name
  capacity_providers = local.cluster_capacity_providers

  dynamic "default_capacity_provider_strategy" {
    for_each = var.default_capacity_provider_strategy
    content {
      capacity_provider = default_capacity_provider_strategy.value.capacity_provider
      weight            = default_capacity_provider_strategy.value.weight
      base              = default_capacity_provider_strategy.value.base
    }
  }
}
