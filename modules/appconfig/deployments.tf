# new hosted version -> forced replacement here -> redeploy through the strategy.
# restrictions: one in-flight deployment per environment (parallel redeploys to
# the same env 409), and apply returns at deployment START - rollout, bake and
# any rollback finish inside appconfig, not in terraform.

resource "aws_appconfig_deployment" "this" {
  for_each = local.create ? local.deployments : {}

  application_id           = aws_appconfig_application.this[0].id
  environment_id           = aws_appconfig_environment.this[each.value.environment].environment_id
  configuration_profile_id = aws_appconfig_configuration_profile.this[local.deployment_profile_instance[each.key]].configuration_profile_id
  deployment_strategy_id   = local.deployment_strategy_id[each.key]

  configuration_version = each.value.configuration_version != "" ? each.value.configuration_version : tostring(aws_appconfig_hosted_configuration_version.this[local.deployment_profile_instance[each.key]].version_number)

  description = each.value.description != "" ? each.value.description : "managed by terraform"
  tags        = local.common_tags
}
