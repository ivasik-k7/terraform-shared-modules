terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

# ============================================================================
# Cognito User Pool - Full Featured Free Tier Configuration
# ============================================================================

module "cognito" {
  source = "../../modules/cognito"

  create_user_pool = true
  user_pool_name   = "${local.name_prefix}-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  mfa_configuration = "OPTIONAL"

  deletion_protection = "INACTIVE"

  account_recovery_setting = {
    recovery_mechanisms = [
      {
        name     = "verified_email"
        priority = 1
      }
    ]
  }

  admin_create_user_config = {
    allow_admin_create_user_only = false
    invite_message_template = {
      email_subject = "Welcome to Archon Platform"
      email_message = "Your username is {username} and temporary password is {####}"
      sms_message   = "Your username is {username} and temporary password is {####}"
    }
  }

  device_configuration = {
    challenge_required_on_new_device      = true
    device_only_remembered_on_user_prompt = true
  }

  email_configuration = {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy = {
    minimum_length                   = 12
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  schema_attributes = [
    {
      name                = "company"
      attribute_data_type = "String"
      mutable             = true
      required            = false
      string_attribute_constraints = {
        min_length = "1"
        max_length = "256"
      }
    },
    {
      name                = "department"
      attribute_data_type = "String"
      mutable             = true
      required            = false
      string_attribute_constraints = {
        min_length = "1"
        max_length = "256"
      }
    },
    {
      name                = "employee_id"
      attribute_data_type = "Number"
      mutable             = false
      required            = false
      number_attribute_constraints = {
        min_value = "1"
        max_value = "999999"
      }
    }
  ]

  software_token_mfa_configuration = {
    enabled = true
  }

  user_attribute_update_settings = {
    attributes_require_verification_before_update = ["email"]
  }

  user_pool_add_ons = {
    advanced_security_mode = "AUDIT"
  }

  username_configuration = {
    case_sensitive = false
  }

  verification_message_template = {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Archon Platform - Verify your email"
    email_message        = "Your verification code is {####}"
  }

  # ============================================================================
  # User Pool Clients
  # ============================================================================

  user_pool_clients = {
    web_app = {
      name                   = "${local.name_prefix}-web-app"
      generate_secret        = false
      refresh_token_validity = 30
      access_token_validity  = 1
      id_token_validity      = 1

      token_validity_units = {
        refresh_token = "days"
        access_token  = "hours"
        id_token      = "hours"
      }

      explicit_auth_flows = [
        "ALLOW_USER_SRP_AUTH",
        "ALLOW_REFRESH_TOKEN_AUTH",
        "ALLOW_USER_PASSWORD_AUTH"
      ]

      allowed_oauth_flows_user_pool_client = true
      allowed_oauth_flows                  = ["code", "implicit"]
      allowed_oauth_scopes                 = ["email", "openid", "profile", "aws.cognito.signin.user.admin"]

      callback_urls = [
        "https://localhost:3000/callback",
        "https://app.archon-hub.com/callback"
      ]

      logout_urls = [
        "https://localhost:3000/logout",
        "https://app.archon-hub.com/logout"
      ]

      supported_identity_providers = ["COGNITO"]

      prevent_user_existence_errors                 = "ENABLED"
      enable_token_revocation                       = true
      enable_propagate_additional_user_context_data = false
    }

    mobile_app = {
      name                   = "${local.name_prefix}-mobile-app"
      generate_secret        = true
      refresh_token_validity = 90
      access_token_validity  = 1
      id_token_validity      = 1

      token_validity_units = {
        refresh_token = "days"
        access_token  = "hours"
        id_token      = "hours"
      }

      explicit_auth_flows = [
        "ALLOW_USER_SRP_AUTH",
        "ALLOW_REFRESH_TOKEN_AUTH"
      ]

      read_attributes = [
        "email",
        "email_verified",
        "name",
        "custom:company",
        "custom:department"
      ]

      write_attributes = [
        "email",
        "name",
        "custom:company",
        "custom:department"
      ]

      prevent_user_existence_errors = "ENABLED"
      enable_token_revocation       = true
    }

    admin_cli = {
      name                   = "${local.name_prefix}-admin-cli"
      generate_secret        = true
      refresh_token_validity = 1
      access_token_validity  = 1
      id_token_validity      = 1

      token_validity_units = {
        refresh_token = "days"
        access_token  = "hours"
        id_token      = "hours"
      }

      explicit_auth_flows = [
        "ALLOW_ADMIN_USER_PASSWORD_AUTH",
        "ALLOW_REFRESH_TOKEN_AUTH"
      ]

      prevent_user_existence_errors = "ENABLED"
      enable_token_revocation       = true
    }
  }

  # ============================================================================
  # User Pool Domain (Free tier)
  # ============================================================================

  user_pool_domains = {
    main = {
      domain = "${local.name_prefix}-auth"
    }
  }

  # ============================================================================
  # Resource Servers (Free tier)
  # ============================================================================

  resource_servers = {
    api = {
      identifier = "https://api.archon-hub.com"
      name       = "Archon Hub API"
      scopes = [
        {
          scope_name        = "read"
          scope_description = "Read access to API resources"
        },
        {
          scope_name        = "write"
          scope_description = "Write access to API resources"
        },
        {
          scope_name        = "admin"
          scope_description = "Administrative access to API resources"
        }
      ]
    }
  }

  # ============================================================================
  # User Groups (Free tier)
  # ============================================================================

  user_groups = {
    admins = {
      name        = "Admins"
      description = "Administrator users with full access"
      precedence  = 1
    }

    developers = {
      name        = "Developers"
      description = "Developer users with API access"
      precedence  = 10
    }

    users = {
      name        = "Users"
      description = "Standard users with basic access"
      precedence  = 100
    }

    readonly = {
      name        = "ReadOnly"
      description = "Read-only users"
      precedence  = 200
    }
  }

  # ============================================================================
  # Identity Pool (Free tier: 50,000 MAUs)
  # ============================================================================

  create_identity_pool             = true
  identity_pool_name               = "${local.name_prefix}-identity-pool"
  allow_unauthenticated_identities = false
  allow_classic_flow               = false

  tags = merge(
    local.base_tags,
    {
      Service     = "cognito"
      Application = "authentication"
      Team        = "platform"
      Owner       = "devops-team"
    }
  )
}

# ============================================================================
# Outputs
# ============================================================================

output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = module.cognito.user_pool_id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = module.cognito.user_pool_arn
}

output "user_pool_endpoint" {
  description = "Cognito User Pool endpoint"
  value       = module.cognito.user_pool_endpoint
}

output "user_pool_client_ids" {
  description = "Map of User Pool Client IDs"
  value       = module.cognito.user_pool_client_ids
}

output "user_pool_client_secrets" {
  description = "Map of User Pool Client secrets"
  value       = module.cognito.user_pool_client_secrets
  sensitive   = true
}

output "user_pool_domain" {
  description = "Cognito User Pool domain"
  value       = module.cognito.user_pool_domain_names
}

output "hosted_ui_url" {
  description = "Hosted UI URL"
  value       = module.cognito.hosted_ui_url
}

output "identity_pool_id" {
  description = "Cognito Identity Pool ID"
  value       = module.cognito.identity_pool_id
}

output "user_groups" {
  description = "User groups created"
  value       = module.cognito.user_group_names
}

output "resource_servers" {
  description = "Resource servers created"
  value       = module.cognito.resource_server_identifiers
}
