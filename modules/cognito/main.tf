# -----------------------------------------------------------------------------
# User Pool
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool" "this" {
  count = var.create_user_pool ? 1 : 0

  name                       = var.user_pool_name
  alias_attributes           = var.alias_attributes
  auto_verified_attributes   = var.auto_verified_attributes
  username_attributes        = var.username_attributes
  mfa_configuration          = var.mfa_configuration
  sms_authentication_message = var.sms_authentication_message
  # Email verification (use verification_message_template instead of individual fields)
  # email_verification_subject = var.email_verification_subject
  # email_verification_message = var.email_verification_message
  sms_verification_message   = var.sms_verification_message
  deletion_protection        = var.deletion_protection

  dynamic "account_recovery_setting" {
    for_each = var.account_recovery_setting != null ? [var.account_recovery_setting] : []
    content {
      dynamic "recovery_mechanism" {
        for_each = account_recovery_setting.value.recovery_mechanisms
        content {
          name     = recovery_mechanism.value.name
          priority = recovery_mechanism.value.priority
        }
      }
    }
  }

  dynamic "admin_create_user_config" {
    for_each = var.admin_create_user_config != null ? [var.admin_create_user_config] : []
    content {
      allow_admin_create_user_only = lookup(admin_create_user_config.value, "allow_admin_create_user_only", false)

      dynamic "invite_message_template" {
        for_each = lookup(admin_create_user_config.value, "invite_message_template", null) != null ? [admin_create_user_config.value.invite_message_template] : []
        content {
          email_message = lookup(invite_message_template.value, "email_message", null)
          email_subject = lookup(invite_message_template.value, "email_subject", null)
          sms_message   = lookup(invite_message_template.value, "sms_message", null)
        }
      }
    }
  }

  dynamic "device_configuration" {
    for_each = var.device_configuration != null ? [var.device_configuration] : []
    content {
      challenge_required_on_new_device      = lookup(device_configuration.value, "challenge_required_on_new_device", false)
      device_only_remembered_on_user_prompt = lookup(device_configuration.value, "device_only_remembered_on_user_prompt", false)
    }
  }

  dynamic "email_configuration" {
    for_each = var.email_configuration != null ? [var.email_configuration] : []
    content {
      configuration_set      = lookup(email_configuration.value, "configuration_set", null)
      email_sending_account  = lookup(email_configuration.value, "email_sending_account", "COGNITO_DEFAULT")
      from_email_address     = lookup(email_configuration.value, "from_email_address", null)
      reply_to_email_address = lookup(email_configuration.value, "reply_to_email_address", null)
      source_arn             = lookup(email_configuration.value, "source_arn", null)
    }
  }

  dynamic "lambda_config" {
    for_each = var.lambda_config != null ? [var.lambda_config] : []
    content {
      create_auth_challenge          = lookup(lambda_config.value, "create_auth_challenge", null)
      custom_message                 = lookup(lambda_config.value, "custom_message", null)
      define_auth_challenge          = lookup(lambda_config.value, "define_auth_challenge", null)
      post_authentication            = lookup(lambda_config.value, "post_authentication", null)
      post_confirmation              = lookup(lambda_config.value, "post_confirmation", null)
      pre_authentication             = lookup(lambda_config.value, "pre_authentication", null)
      pre_sign_up                    = lookup(lambda_config.value, "pre_sign_up", null)
      pre_token_generation           = lookup(lambda_config.value, "pre_token_generation", null)
      user_migration                 = lookup(lambda_config.value, "user_migration", null)
      verify_auth_challenge_response = lookup(lambda_config.value, "verify_auth_challenge_response", null)
      kms_key_id                     = lookup(lambda_config.value, "kms_key_id", null)

      dynamic "custom_email_sender" {
        for_each = lookup(lambda_config.value, "custom_email_sender", null) != null ? [lambda_config.value.custom_email_sender] : []
        content {
          lambda_arn     = custom_email_sender.value.lambda_arn
          lambda_version = custom_email_sender.value.lambda_version
        }
      }

      dynamic "custom_sms_sender" {
        for_each = lookup(lambda_config.value, "custom_sms_sender", null) != null ? [lambda_config.value.custom_sms_sender] : []
        content {
          lambda_arn     = custom_sms_sender.value.lambda_arn
          lambda_version = custom_sms_sender.value.lambda_version
        }
      }
    }
  }

  dynamic "password_policy" {
    for_each = var.password_policy != null ? [var.password_policy] : []
    content {
      minimum_length                   = lookup(password_policy.value, "minimum_length", 8)
      require_lowercase                = lookup(password_policy.value, "require_lowercase", true)
      require_numbers                  = lookup(password_policy.value, "require_numbers", true)
      require_symbols                  = lookup(password_policy.value, "require_symbols", true)
      require_uppercase                = lookup(password_policy.value, "require_uppercase", true)
      temporary_password_validity_days = lookup(password_policy.value, "temporary_password_validity_days", 7)
    }
  }

  dynamic "schema" {
    for_each = var.schema_attributes
    content {
      name                     = schema.value.name
      attribute_data_type      = schema.value.attribute_data_type
      developer_only_attribute = lookup(schema.value, "developer_only_attribute", false)
      mutable                  = lookup(schema.value, "mutable", true)
      required                 = lookup(schema.value, "required", false)

      dynamic "number_attribute_constraints" {
        for_each = lookup(schema.value, "number_attribute_constraints", null) != null ? [schema.value.number_attribute_constraints] : []
        content {
          min_value = lookup(number_attribute_constraints.value, "min_value", null)
          max_value = lookup(number_attribute_constraints.value, "max_value", null)
        }
      }

      dynamic "string_attribute_constraints" {
        for_each = lookup(schema.value, "string_attribute_constraints", null) != null ? [schema.value.string_attribute_constraints] : []
        content {
          min_length = lookup(string_attribute_constraints.value, "min_length", null)
          max_length = lookup(string_attribute_constraints.value, "max_length", null)
        }
      }
    }
  }

  dynamic "sms_configuration" {
    for_each = var.sms_configuration != null ? [var.sms_configuration] : []
    content {
      external_id    = sms_configuration.value.external_id
      sns_caller_arn = sms_configuration.value.sns_caller_arn
      sns_region     = lookup(sms_configuration.value, "sns_region", null)
    }
  }

  dynamic "software_token_mfa_configuration" {
    for_each = var.software_token_mfa_configuration != null ? [var.software_token_mfa_configuration] : []
    content {
      enabled = software_token_mfa_configuration.value.enabled
    }
  }

  dynamic "user_attribute_update_settings" {
    for_each = var.user_attribute_update_settings != null ? [var.user_attribute_update_settings] : []
    content {
      attributes_require_verification_before_update = user_attribute_update_settings.value.attributes_require_verification_before_update
    }
  }

  dynamic "user_pool_add_ons" {
    for_each = var.user_pool_add_ons != null ? [var.user_pool_add_ons] : []
    content {
      advanced_security_mode = user_pool_add_ons.value.advanced_security_mode
    }
  }

  dynamic "username_configuration" {
    for_each = var.username_configuration != null ? [var.username_configuration] : []
    content {
      case_sensitive = username_configuration.value.case_sensitive
    }
  }

  dynamic "verification_message_template" {
    for_each = var.verification_message_template != null ? [var.verification_message_template] : []
    content {
      default_email_option  = lookup(verification_message_template.value, "default_email_option", "CONFIRM_WITH_CODE")
      email_message         = lookup(verification_message_template.value, "email_message", null)
      email_message_by_link = lookup(verification_message_template.value, "email_message_by_link", null)
      email_subject         = lookup(verification_message_template.value, "email_subject", null)
      email_subject_by_link = lookup(verification_message_template.value, "email_subject_by_link", null)
      sms_message           = lookup(verification_message_template.value, "sms_message", null)
    }
  }

  tags = merge(
    var.tags,
    var.user_pool_tags,
    {
      Name = var.user_pool_name
    }
  )
}

# -----------------------------------------------------------------------------
# User Pool Client
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_client" "this" {
  for_each = var.create_user_pool ? var.user_pool_clients : {}

  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this[0].id

  access_token_validity                         = lookup(each.value, "access_token_validity", null)
  id_token_validity                             = lookup(each.value, "id_token_validity", null)
  refresh_token_validity                        = lookup(each.value, "refresh_token_validity", 30)
  allowed_oauth_flows                           = lookup(each.value, "allowed_oauth_flows", null)
  allowed_oauth_flows_user_pool_client          = lookup(each.value, "allowed_oauth_flows_user_pool_client", false)
  allowed_oauth_scopes                          = lookup(each.value, "allowed_oauth_scopes", null)
  callback_urls                                 = lookup(each.value, "callback_urls", null)
  default_redirect_uri                          = lookup(each.value, "default_redirect_uri", null)
  enable_token_revocation                       = lookup(each.value, "enable_token_revocation", true)
  enable_propagate_additional_user_context_data = lookup(each.value, "enable_propagate_additional_user_context_data", false)
  explicit_auth_flows                           = lookup(each.value, "explicit_auth_flows", null)
  generate_secret                               = lookup(each.value, "generate_secret", false)
  logout_urls                                   = lookup(each.value, "logout_urls", null)
  prevent_user_existence_errors                 = lookup(each.value, "prevent_user_existence_errors", "ENABLED")
  read_attributes                               = lookup(each.value, "read_attributes", null)
  supported_identity_providers                  = lookup(each.value, "supported_identity_providers", null)
  write_attributes                              = lookup(each.value, "write_attributes", null)
  auth_session_validity                         = lookup(each.value, "auth_session_validity", 3)

  dynamic "analytics_configuration" {
    for_each = lookup(each.value, "analytics_configuration", null) != null ? [each.value.analytics_configuration] : []
    content {
      application_arn  = lookup(analytics_configuration.value, "application_arn", null)
      application_id   = lookup(analytics_configuration.value, "application_id", null)
      external_id      = lookup(analytics_configuration.value, "external_id", null)
      role_arn         = lookup(analytics_configuration.value, "role_arn", null)
      user_data_shared = lookup(analytics_configuration.value, "user_data_shared", false)
    }
  }

  dynamic "token_validity_units" {
    for_each = lookup(each.value, "token_validity_units", null) != null ? [each.value.token_validity_units] : []
    content {
      access_token  = lookup(token_validity_units.value, "access_token", "hours")
      id_token      = lookup(token_validity_units.value, "id_token", "hours")
      refresh_token = lookup(token_validity_units.value, "refresh_token", "days")
    }
  }
}

# -----------------------------------------------------------------------------
# User Pool Domain
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_domain" "this" {
  for_each = var.create_user_pool ? var.user_pool_domains : {}

  domain          = each.value.domain
  user_pool_id    = aws_cognito_user_pool.this[0].id
  certificate_arn = lookup(each.value, "certificate_arn", null)
}

# -----------------------------------------------------------------------------
# Resource Server
# -----------------------------------------------------------------------------
resource "aws_cognito_resource_server" "this" {
  for_each = var.create_user_pool ? var.resource_servers : {}

  identifier   = each.value.identifier
  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this[0].id

  dynamic "scope" {
    for_each = lookup(each.value, "scopes", [])
    content {
      scope_name        = scope.value.scope_name
      scope_description = scope.value.scope_description
    }
  }
}

# -----------------------------------------------------------------------------
# Identity Provider
# -----------------------------------------------------------------------------
resource "aws_cognito_identity_provider" "this" {
  for_each = var.create_user_pool ? var.identity_providers : {}

  user_pool_id  = aws_cognito_user_pool.this[0].id
  provider_name = each.value.provider_name
  provider_type = each.value.provider_type

  provider_details = each.value.provider_details

  attribute_mapping = lookup(each.value, "attribute_mapping", null)
  idp_identifiers   = lookup(each.value, "idp_identifiers", null)
}

# -----------------------------------------------------------------------------
# User Pool UI Customization
# -----------------------------------------------------------------------------
resource "aws_cognito_user_pool_ui_customization" "this" {
  for_each = var.create_user_pool ? var.ui_customizations : {}

  user_pool_id = aws_cognito_user_pool.this[0].id
  client_id    = lookup(each.value, "client_id", null)

  css        = lookup(each.value, "css", null)
  image_file = lookup(each.value, "image_file", null)
}

# -----------------------------------------------------------------------------
# Identity Pool
# -----------------------------------------------------------------------------
resource "aws_cognito_identity_pool" "this" {
  count = var.create_identity_pool ? 1 : 0

  identity_pool_name               = var.identity_pool_name
  allow_unauthenticated_identities = var.allow_unauthenticated_identities
  allow_classic_flow               = var.allow_classic_flow

  dynamic "cognito_identity_providers" {
    for_each = var.cognito_identity_providers
    content {
      client_id               = cognito_identity_providers.value.client_id
      provider_name           = cognito_identity_providers.value.provider_name
      server_side_token_check = lookup(cognito_identity_providers.value, "server_side_token_check", false)
    }
  }

  supported_login_providers = var.supported_login_providers

  saml_provider_arns           = var.saml_provider_arns
  openid_connect_provider_arns = var.openid_connect_provider_arns

  tags = merge(
    var.tags,
    var.identity_pool_tags,
    {
      Name = var.identity_pool_name
    }
  )
}

# -----------------------------------------------------------------------------
# Identity Pool Roles Attachment
# -----------------------------------------------------------------------------
resource "aws_cognito_identity_pool_roles_attachment" "this" {
  count = var.create_identity_pool && var.identity_pool_roles != null ? 1 : 0

  identity_pool_id = aws_cognito_identity_pool.this[0].id
  roles            = var.identity_pool_roles

  dynamic "role_mapping" {
    for_each = var.identity_pool_role_mappings
    content {
      identity_provider         = role_mapping.value.identity_provider
      ambiguous_role_resolution = lookup(role_mapping.value, "ambiguous_role_resolution", null)
      type                      = role_mapping.value.type

      dynamic "mapping_rule" {
        for_each = lookup(role_mapping.value, "mapping_rules", [])
        content {
          claim      = mapping_rule.value.claim
          match_type = mapping_rule.value.match_type
          role_arn   = mapping_rule.value.role_arn
          value      = mapping_rule.value.value
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# User Group
# -----------------------------------------------------------------------------
resource "aws_cognito_user_group" "this" {
  for_each = var.create_user_pool ? var.user_groups : {}

  name         = each.value.name
  user_pool_id = aws_cognito_user_pool.this[0].id
  description  = lookup(each.value, "description", null)
  precedence   = lookup(each.value, "precedence", null)
  role_arn     = lookup(each.value, "role_arn", null)
}

# -----------------------------------------------------------------------------
# User Pool Risk Configuration
# -----------------------------------------------------------------------------
resource "aws_cognito_risk_configuration" "this" {
  count = var.create_user_pool && var.risk_configuration != null ? 1 : 0

  user_pool_id = aws_cognito_user_pool.this[0].id
  client_id    = lookup(var.risk_configuration, "client_id", null)

  dynamic "account_takeover_risk_configuration" {
    for_each = lookup(var.risk_configuration, "account_takeover_risk_configuration", null) != null ? [var.risk_configuration.account_takeover_risk_configuration] : []
    content {
      dynamic "notify_configuration" {
        for_each = [account_takeover_risk_configuration.value.notify_configuration]
        content {
          from       = lookup(notify_configuration.value, "from", null)
          reply_to   = lookup(notify_configuration.value, "reply_to", null)
          source_arn = notify_configuration.value.source_arn
        }
      }

      dynamic "actions" {
        for_each = [account_takeover_risk_configuration.value.actions]
        content {
          dynamic "high_action" {
            for_each = lookup(actions.value, "high_action", null) != null ? [actions.value.high_action] : []
            content {
              event_action = high_action.value.event_action
              notify       = high_action.value.notify
            }
          }

          dynamic "low_action" {
            for_each = lookup(actions.value, "low_action", null) != null ? [actions.value.low_action] : []
            content {
              event_action = low_action.value.event_action
              notify       = low_action.value.notify
            }
          }

          dynamic "medium_action" {
            for_each = lookup(actions.value, "medium_action", null) != null ? [actions.value.medium_action] : []
            content {
              event_action = medium_action.value.event_action
              notify       = medium_action.value.notify
            }
          }
        }
      }
    }
  }

  dynamic "compromised_credentials_risk_configuration" {
    for_each = lookup(var.risk_configuration, "compromised_credentials_risk_configuration", null) != null ? [var.risk_configuration.compromised_credentials_risk_configuration] : []
    content {
      event_filter = lookup(compromised_credentials_risk_configuration.value, "event_filter", null)

      dynamic "actions" {
        for_each = [compromised_credentials_risk_configuration.value.actions]
        content {
          event_action = actions.value.event_action
        }
      }
    }
  }

  dynamic "risk_exception_configuration" {
    for_each = lookup(var.risk_configuration, "risk_exception_configuration", null) != null ? [var.risk_configuration.risk_exception_configuration] : []
    content {
      blocked_ip_range_list = lookup(risk_exception_configuration.value, "blocked_ip_range_list", null)
      skipped_ip_range_list = lookup(risk_exception_configuration.value, "skipped_ip_range_list", null)
    }
  }
}
