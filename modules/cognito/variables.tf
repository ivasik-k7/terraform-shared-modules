# -----------------------------------------------------------------------------
# General Settings
# -----------------------------------------------------------------------------
variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# User Pool Settings
# -----------------------------------------------------------------------------
variable "create_user_pool" {
  description = "Whether to create a Cognito User Pool"
  type        = bool
  default     = true
}

variable "user_pool_name" {
  description = "Name of the Cognito User Pool"
  type        = string
  default     = ""
}

variable "alias_attributes" {
  description = "Attributes supported as an alias for this user pool (email, phone_number, preferred_username)"
  type        = list(string)
  default     = null
}

variable "auto_verified_attributes" {
  description = "Attributes to be auto-verified (email, phone_number)"
  type        = list(string)
  default     = []
}

variable "username_attributes" {
  description = "Whether email addresses or phone numbers can be specified as usernames"
  type        = list(string)
  default     = null
}

variable "mfa_configuration" {
  description = "Multi-Factor Authentication (MFA) configuration (OFF, ON, OPTIONAL)"
  type        = string
  default     = "OFF"

  validation {
    condition     = contains(["OFF", "ON", "OPTIONAL"], var.mfa_configuration)
    error_message = "MFA configuration must be OFF, ON, or OPTIONAL."
  }
}

variable "sms_authentication_message" {
  description = "String representing the SMS authentication message"
  type        = string
  default     = null
}

variable "email_verification_subject" {
  description = "String representing the email verification subject"
  type        = string
  default     = null
}

variable "email_verification_message" {
  description = "String representing the email verification message"
  type        = string
  default     = null
}

variable "sms_verification_message" {
  description = "String representing the SMS verification message"
  type        = string
  default     = null
}

variable "deletion_protection" {
  description = "When active, prevents accidental deletion of the user pool"
  type        = string
  default     = "INACTIVE"

  validation {
    condition     = contains(["ACTIVE", "INACTIVE"], var.deletion_protection)
    error_message = "Deletion protection must be ACTIVE or INACTIVE."
  }
}

variable "user_pool_tags" {
  description = "Additional tags for the User Pool"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Account Recovery Settings
# -----------------------------------------------------------------------------
variable "account_recovery_setting" {
  description = "Account recovery configuration"
  type = object({
    recovery_mechanisms = list(object({
      name     = string
      priority = number
    }))
  })
  default = null
}

# -----------------------------------------------------------------------------
# Admin Create User Config
# -----------------------------------------------------------------------------
variable "admin_create_user_config" {
  description = "Configuration for admin user creation"
  type = object({
    allow_admin_create_user_only = optional(bool)
    invite_message_template = optional(object({
      email_message = optional(string)
      email_subject = optional(string)
      sms_message   = optional(string)
    }))
  })
  default = null
}

# -----------------------------------------------------------------------------
# Device Configuration
# -----------------------------------------------------------------------------
variable "device_configuration" {
  description = "Device tracking configuration"
  type = object({
    challenge_required_on_new_device      = optional(bool)
    device_only_remembered_on_user_prompt = optional(bool)
  })
  default = null
}

# -----------------------------------------------------------------------------
# Email Configuration
# -----------------------------------------------------------------------------
variable "email_configuration" {
  description = "Email configuration for the user pool"
  type = object({
    configuration_set      = optional(string)
    email_sending_account  = optional(string)
    from_email_address     = optional(string)
    reply_to_email_address = optional(string)
    source_arn             = optional(string)
  })
  default = null
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------
variable "lambda_config" {
  description = "Lambda triggers configuration"
  type = object({
    create_auth_challenge          = optional(string)
    custom_message                 = optional(string)
    define_auth_challenge          = optional(string)
    post_authentication            = optional(string)
    post_confirmation              = optional(string)
    pre_authentication             = optional(string)
    pre_sign_up                    = optional(string)
    pre_token_generation           = optional(string)
    user_migration                 = optional(string)
    verify_auth_challenge_response = optional(string)
    kms_key_id                     = optional(string)
    custom_email_sender = optional(object({
      lambda_arn     = string
      lambda_version = string
    }))
    custom_sms_sender = optional(object({
      lambda_arn     = string
      lambda_version = string
    }))
  })
  default = null
}

# -----------------------------------------------------------------------------
# Password Policy
# -----------------------------------------------------------------------------
variable "password_policy" {
  description = "Password policy configuration"
  type = object({
    minimum_length                   = optional(number)
    require_lowercase                = optional(bool)
    require_numbers                  = optional(bool)
    require_symbols                  = optional(bool)
    require_uppercase                = optional(bool)
    temporary_password_validity_days = optional(number)
  })
  default = null
}

# -----------------------------------------------------------------------------
# Schema Attributes
# -----------------------------------------------------------------------------
variable "schema_attributes" {
  description = "List of schema attributes for the user pool"
  type = list(object({
    name                     = string
    attribute_data_type      = string
    developer_only_attribute = optional(bool)
    mutable                  = optional(bool)
    required                 = optional(bool)
    number_attribute_constraints = optional(object({
      min_value = optional(string)
      max_value = optional(string)
    }))
    string_attribute_constraints = optional(object({
      min_length = optional(string)
      max_length = optional(string)
    }))
  }))
  default = []
}

# -----------------------------------------------------------------------------
# SMS Configuration
# -----------------------------------------------------------------------------
variable "sms_configuration" {
  description = "SMS configuration for the user pool"
  type = object({
    external_id    = string
    sns_caller_arn = string
    sns_region     = optional(string)
  })
  default = null
}

# -----------------------------------------------------------------------------
# Software Token MFA Configuration
# -----------------------------------------------------------------------------
variable "software_token_mfa_configuration" {
  description = "Software token MFA configuration"
  type = object({
    enabled = bool
  })
  default = null
}

# -----------------------------------------------------------------------------
# User Attribute Update Settings
# -----------------------------------------------------------------------------
variable "user_attribute_update_settings" {
  description = "User attribute update settings"
  type = object({
    attributes_require_verification_before_update = list(string)
  })
  default = null
}

# -----------------------------------------------------------------------------
# User Pool Add-ons
# -----------------------------------------------------------------------------
variable "user_pool_add_ons" {
  description = "User pool add-ons configuration"
  type = object({
    advanced_security_mode = string
  })
  default = null

  validation {
    condition = var.user_pool_add_ons == null || (
      var.user_pool_add_ons != null && contains(["OFF", "AUDIT", "ENFORCED"], var.user_pool_add_ons.advanced_security_mode)
    )
    error_message = "Advanced security mode must be OFF, AUDIT, or ENFORCED."
  }
}

# -----------------------------------------------------------------------------
# Username Configuration
# -----------------------------------------------------------------------------
variable "username_configuration" {
  description = "Username configuration"
  type = object({
    case_sensitive = bool
  })
  default = null
}

# -----------------------------------------------------------------------------
# Verification Message Template
# -----------------------------------------------------------------------------
variable "verification_message_template" {
  description = "Verification message template configuration"
  type = object({
    default_email_option  = optional(string)
    email_message         = optional(string)
    email_message_by_link = optional(string)
    email_subject         = optional(string)
    email_subject_by_link = optional(string)
    sms_message           = optional(string)
  })
  default = null
}

# -----------------------------------------------------------------------------
# User Pool Clients
# -----------------------------------------------------------------------------
variable "user_pool_clients" {
  description = "Map of user pool clients to create"
  type = map(object({
    name                                          = string
    access_token_validity                         = optional(number)
    id_token_validity                             = optional(number)
    refresh_token_validity                        = optional(number)
    allowed_oauth_flows                           = optional(list(string))
    allowed_oauth_flows_user_pool_client          = optional(bool)
    allowed_oauth_scopes                          = optional(list(string))
    callback_urls                                 = optional(list(string))
    default_redirect_uri                          = optional(string)
    enable_token_revocation                       = optional(bool)
    enable_propagate_additional_user_context_data = optional(bool)
    explicit_auth_flows                           = optional(list(string))
    generate_secret                               = optional(bool)
    logout_urls                                   = optional(list(string))
    prevent_user_existence_errors                 = optional(string)
    read_attributes                               = optional(list(string))
    supported_identity_providers                  = optional(list(string))
    write_attributes                              = optional(list(string))
    auth_session_validity                         = optional(number)
    analytics_configuration = optional(object({
      application_arn  = optional(string)
      application_id   = optional(string)
      external_id      = optional(string)
      role_arn         = optional(string)
      user_data_shared = optional(bool)
    }))
    token_validity_units = optional(object({
      access_token  = optional(string)
      id_token      = optional(string)
      refresh_token = optional(string)
    }))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# User Pool Domains
# -----------------------------------------------------------------------------
variable "user_pool_domains" {
  description = "Map of user pool domains to create"
  type = map(object({
    domain          = string
    certificate_arn = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Resource Servers
# -----------------------------------------------------------------------------
variable "resource_servers" {
  description = "Map of resource servers to create"
  type = map(object({
    identifier = string
    name       = string
    scopes = optional(list(object({
      scope_name        = string
      scope_description = string
    })))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Identity Providers
# -----------------------------------------------------------------------------
variable "identity_providers" {
  description = "Map of identity providers to create"
  type = map(object({
    provider_name     = string
    provider_type     = string
    provider_details  = map(string)
    attribute_mapping = optional(map(string))
    idp_identifiers   = optional(list(string))
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# UI Customizations
# -----------------------------------------------------------------------------
variable "ui_customizations" {
  description = "Map of UI customizations"
  type = map(object({
    client_id  = optional(string)
    css        = optional(string)
    image_file = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Identity Pool Settings
# -----------------------------------------------------------------------------
variable "create_identity_pool" {
  description = "Whether to create a Cognito Identity Pool"
  type        = bool
  default     = false
}

variable "identity_pool_name" {
  description = "Name of the Cognito Identity Pool"
  type        = string
  default     = ""
}

variable "allow_unauthenticated_identities" {
  description = "Whether the identity pool supports unauthenticated logins"
  type        = bool
  default     = false
}

variable "allow_classic_flow" {
  description = "Whether to enable the classic / basic flow"
  type        = bool
  default     = false
}

variable "cognito_identity_providers" {
  description = "List of Cognito identity providers"
  type = list(object({
    client_id               = string
    provider_name           = string
    server_side_token_check = optional(bool)
  }))
  default = []
}

variable "supported_login_providers" {
  description = "Map of supported login providers"
  type        = map(string)
  default     = {}
}

variable "saml_provider_arns" {
  description = "List of SAML provider ARNs"
  type        = list(string)
  default     = []
}

variable "openid_connect_provider_arns" {
  description = "List of OpenID Connect provider ARNs"
  type        = list(string)
  default     = []
}

variable "identity_pool_tags" {
  description = "Additional tags for the Identity Pool"
  type        = map(string)
  default     = {}
}

# -----------------------------------------------------------------------------
# Identity Pool Roles
# -----------------------------------------------------------------------------
variable "identity_pool_roles" {
  description = "Map of roles for authenticated and unauthenticated identities"
  type        = map(string)
  default     = null
}

variable "identity_pool_role_mappings" {
  description = "List of role mappings for the identity pool"
  type = list(object({
    identity_provider         = string
    ambiguous_role_resolution = optional(string)
    type                      = string
    mapping_rules = optional(list(object({
      claim      = string
      match_type = string
      role_arn   = string
      value      = string
    })))
  }))
  default = []
}

# -----------------------------------------------------------------------------
# User Groups
# -----------------------------------------------------------------------------
variable "user_groups" {
  description = "Map of user groups to create"
  type = map(object({
    name        = string
    description = optional(string)
    precedence  = optional(number)
    role_arn    = optional(string)
  }))
  default = {}
}

# -----------------------------------------------------------------------------
# Risk Configuration
# -----------------------------------------------------------------------------
variable "risk_configuration" {
  description = "Risk configuration for the user pool"
  type = object({
    client_id = optional(string)
    account_takeover_risk_configuration = optional(object({
      notify_configuration = object({
        from            = optional(string)
        reply_to        = optional(string)
        source_arn      = string
        block_email     = optional(map(string))
        mfa_email       = optional(map(string))
        no_action_email = optional(map(string))
      })
      actions = object({
        high_action = optional(object({
          event_action = string
          notify       = bool
        }))
        low_action = optional(object({
          event_action = string
          notify       = bool
        }))
        medium_action = optional(object({
          event_action = string
          notify       = bool
        }))
      })
    }))
    compromised_credentials_risk_configuration = optional(object({
      event_filter = optional(list(string))
      actions = object({
        event_action = string
      })
    }))
    risk_exception_configuration = optional(object({
      blocked_ip_range_list = optional(list(string))
      skipped_ip_range_list = optional(list(string))
    }))
  })
  default = null
}
