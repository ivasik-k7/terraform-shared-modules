# custom shapes only; the AppConfig.* presets are referenced by id and never
# created here.

resource "aws_appconfig_deployment_strategy" "this" {
  for_each = local.create ? var.deployment_strategies : {}

  name                           = each.key
  description                    = each.value.description
  deployment_duration_in_minutes = each.value.deployment_duration_minutes
  growth_factor                  = each.value.growth_factor
  growth_type                    = each.value.growth_type
  final_bake_time_in_minutes     = each.value.bake_time_minutes
  replicate_to                   = each.value.replicate_to
  tags                           = merge(local.common_tags, each.value.tags)
}
