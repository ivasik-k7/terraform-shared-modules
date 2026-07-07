# hosted content is immutable + versioned; a change means a new version.
# NB: hosted store caps a config at 2MB (aws quota).

resource "aws_appconfig_configuration_profile" "this" {
  # instance keys: "pk" for plain profiles, "pk:ek" for env-specialized ones
  for_each = local.create ? local.profile_instances : {}

  application_id = aws_appconfig_application.this[0].id
  name           = each.value.env == "" ? each.value.profile : "${each.value.profile}-${each.value.env}"
  description    = var.profiles[each.value.profile].description
  location_uri   = var.profiles[each.value.profile].location_uri
  type           = local.profile_type_api[each.key]

  retrieval_role_arn = var.profiles[each.value.profile].retrieval_role_arn != "" ? var.profiles[each.value.profile].retrieval_role_arn : null
  kms_key_identifier = var.profiles[each.value.profile].kms_key_arn != "" ? var.profiles[each.value.profile].kms_key_arn : null

  dynamic "validator" {
    for_each = var.profiles[each.value.profile].json_schema != "" ? [var.profiles[each.value.profile].json_schema] : []
    content {
      type    = "JSON_SCHEMA"
      content = validator.value
    }
  }

  dynamic "validator" {
    for_each = var.profiles[each.value.profile].lambda_validator_arn != "" ? [var.profiles[each.value.profile].lambda_validator_arn] : []
    content {
      type    = "LAMBDA"
      content = validator.value
    }
  }

  tags = merge(local.common_tags, var.profiles[each.value.profile].tags)
}

resource "aws_appconfig_hosted_configuration_version" "this" {
  for_each = local.create ? local.hosted_content : {}

  application_id           = aws_appconfig_application.this[0].id
  configuration_profile_id = aws_appconfig_configuration_profile.this[each.key].configuration_profile_id
  description              = "managed by terraform"
  content                  = each.value
  content_type             = local.hosted_content_type[each.key]

  # keep the old version until the new one exists - an in-flight rollback
  # needs somewhere to land
  lifecycle {
    create_before_destroy = true
  }
}
