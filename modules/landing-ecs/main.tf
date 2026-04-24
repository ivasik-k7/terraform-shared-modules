resource "aws_ecs_cluster" "this" {
  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  dynamic "setting" {
    for_each = var.cluster_settings
    content {
      name  = setting.key
      value = setting.value
    }
  }

  tags = local.cluster_tags
}

# Fargate providers always registered; extras go in var.capacity_providers.
# default_* only matters for RunTask calls without an explicit strategy.
resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.this.name
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
