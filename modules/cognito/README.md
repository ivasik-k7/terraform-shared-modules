# Cognito Module

Production-grade Terraform module for deploying Amazon Cognito User Pools and Identity Pools with authentication and authorization features.

## Features

- **User Pool Management** - Complete user pool configuration with all AWS Cognito features
- **Multi-Factor Authentication** - SMS and TOTP (software token) MFA support
- **OAuth 2.0 & OIDC** - Full OAuth 2.0 and OpenID Connect support
- **Custom Domains** - Cognito-hosted and custom domain support
- **Identity Providers** - SAML, OIDC, and social identity provider integration
- **User Groups** - Role-based access control with IAM integration
- **Identity Pool** - Federated identities for AWS service access
- **Advanced Security** - Risk-based authentication and account takeover protection
- **Lambda Triggers** - Customizable authentication flows with Lambda
- **Custom Attributes** - Extensible user schema with custom attributes

## Quick Start

### Basic User Pool

```hcl
module "cognito" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "my-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy = {
    minimum_length    = 12
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  user_pool_clients = {
    web_app = {
      name                   = "web-app-client"
      generate_secret        = false
      refresh_token_validity = 30

      explicit_auth_flows = [
        "ALLOW_USER_SRP_AUTH",
        "ALLOW_REFRESH_TOKEN_AUTH"
      ]
    }
  }

  tags = {
    Environment = "production"
    Service     = "authentication"
  }
}
```

### User Pool with MFA and Advanced Security

```hcl
module "cognito_secure" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "secure-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]
  mfa_configuration        = "OPTIONAL"

  software_token_mfa_configuration = {
    enabled = true
  }

  user_pool_add_ons = {
    advanced_security_mode = "ENFORCED"
  }

  password_policy = {
    minimum_length                   = 14
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    require_uppercase                = true
    temporary_password_validity_days = 3
  }

  tags = {
    Environment = "production"
    Compliance  = "required"
  }
}
```

### User Pool with OAuth 2.0 and Custom Domain

```hcl
module "cognito_oauth" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "oauth-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  user_pool_clients = {
    web_app = {
      name                                 = "web-app"
      generate_secret                      = false
      allowed_oauth_flows_user_pool_client = true
      allowed_oauth_flows                  = ["code", "implicit"]
      allowed_oauth_scopes                 = ["email", "openid", "profile"]

      callback_urls = [
        "https://app.example.com/callback"
      ]

      logout_urls = [
        "https://app.example.com/logout"
      ]

      supported_identity_providers = ["COGNITO"]
    }
  }

  user_pool_domains = {
    main = {
      domain = "my-app-auth"
    }
  }

  resource_servers = {
    api = {
      identifier = "https://api.example.com"
      name       = "My API"
      scopes = [
        {
          scope_name        = "read"
          scope_description = "Read access"
        },
        {
          scope_name        = "write"
          scope_description = "Write access"
        }
      ]
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### User Pool with Custom Attributes

```hcl
module "cognito_custom" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "custom-attributes-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

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

  tags = {
    Environment = "production"
  }
}
```

### Identity Pool with User Pool Integration

```hcl
module "cognito_identity" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "my-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  user_pool_clients = {
    web_app = {
      name = "web-app"
    }
  }

  create_identity_pool             = true
  identity_pool_name               = "my-identity-pool"
  allow_unauthenticated_identities = false

  tags = {
    Environment = "production"
  }
}
```

### User Groups with IAM Roles

```hcl
module "cognito_groups" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "grouped-user-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  user_groups = {
    admins = {
      name        = "Admins"
      description = "Administrator users"
      precedence  = 1
      role_arn    = aws_iam_role.admin.arn
    }

    users = {
      name        = "Users"
      description = "Standard users"
      precedence  = 10
      role_arn    = aws_iam_role.user.arn
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Lambda Triggers

```hcl
module "cognito_lambda" {
  source = "./modules/cognito"

  create_user_pool = true
  user_pool_name   = "lambda-triggered-pool"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  lambda_config = {
    pre_sign_up         = aws_lambda_function.pre_signup.arn
    post_confirmation   = aws_lambda_function.post_confirmation.arn
    pre_authentication  = aws_lambda_function.pre_auth.arn
    post_authentication = aws_lambda_function.post_auth.arn
    custom_message      = aws_lambda_function.custom_message.arn
  }

  tags = {
    Environment = "production"
  }
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| aws       | ~> 5.0   |

## Providers

| Name | Version |
| ---- | ------- |
| aws  | ~> 5.0  |

## Resources

| Name                                                                                                                                                                  | Type     |
| --------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [aws_cognito_user_pool.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool)                                           | resource |
| [aws_cognito_user_pool_client.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_client)                             | resource |
| [aws_cognito_user_pool_domain.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_domain)                             | resource |
| [aws_cognito_resource_server.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_resource_server)                               | resource |
| [aws_cognito_identity_provider.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_identity_provider)                           | resource |
| [aws_cognito_user_pool_ui_customization.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_pool_ui_customization)         | resource |
| [aws_cognito_identity_pool.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_identity_pool)                                   | resource |
| [aws_cognito_identity_pool_roles_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_identity_pool_roles_attachment) | resource |
| [aws_cognito_user_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_user_group)                                         | resource |
| [aws_cognito_risk_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cognito_risk_configuration)                         | resource |

## Inputs

### Core Configuration

| Name                     | Description                                                            | Type           | Default      | Required |
| ------------------------ | ---------------------------------------------------------------------- | -------------- | ------------ | :------: |
| create_user_pool         | Whether to create a Cognito User Pool                                  | `bool`         | `true`       |    no    |
| user_pool_name           | Name of the Cognito User Pool                                          | `string`       | `""`         |   yes    |
| username_attributes      | Whether email addresses or phone numbers can be specified as usernames | `list(string)` | `null`       |    no    |
| auto_verified_attributes | Attributes to be auto-verified (email, phone_number)                   | `list(string)` | `[]`         |    no    |
| mfa_configuration        | Multi-Factor Authentication configuration (OFF, ON, OPTIONAL)          | `string`       | `"OFF"`      |    no    |
| deletion_protection      | When active, prevents accidental deletion of the user pool             | `string`       | `"INACTIVE"` |    no    |
| tags                     | Common tags to apply to all resources                                  | `map(string)`  | `{}`         |    no    |

### Password Policy

| Name            | Description                   | Type     | Default | Required |
| --------------- | ----------------------------- | -------- | ------- | :------: |
| password_policy | Password policy configuration | `object` | `null`  |    no    |

### User Pool Clients

| Name              | Description                        | Type          | Default | Required |
| ----------------- | ---------------------------------- | ------------- | ------- | :------: |
| user_pool_clients | Map of user pool clients to create | `map(object)` | `{}`    |    no    |

### Advanced Security

| Name               | Description                                         | Type     | Default | Required |
| ------------------ | --------------------------------------------------- | -------- | ------- | :------: |
| user_pool_add_ons  | User pool add-ons configuration (advanced security) | `object` | `null`  |    no    |
| risk_configuration | Risk configuration for the user pool                | `object` | `null`  |    no    |

### Lambda Triggers

| Name          | Description                   | Type     | Default | Required |
| ------------- | ----------------------------- | -------- | ------- | :------: |
| lambda_config | Lambda triggers configuration | `object` | `null`  |    no    |

### Identity Pool

| Name                             | Description                                               | Type     | Default | Required |
| -------------------------------- | --------------------------------------------------------- | -------- | ------- | :------: |
| create_identity_pool             | Whether to create a Cognito Identity Pool                 | `bool`   | `false` |    no    |
| identity_pool_name               | Name of the Cognito Identity Pool                         | `string` | `""`    |    no    |
| allow_unauthenticated_identities | Whether the identity pool supports unauthenticated logins | `bool`   | `false` |    no    |

## Outputs

| Name                        | Description                                 |
| --------------------------- | ------------------------------------------- |
| user_pool_id                | ID of the Cognito User Pool                 |
| user_pool_arn               | ARN of the Cognito User Pool                |
| user_pool_endpoint          | Endpoint of the Cognito User Pool           |
| user_pool_client_ids        | Map of user pool client IDs                 |
| user_pool_client_secrets    | Map of user pool client secrets (sensitive) |
| user_pool_domain_names      | Map of user pool domain names               |
| hosted_ui_url               | Hosted UI URL for the user pool             |
| identity_pool_id            | ID of the Cognito Identity Pool             |
| user_group_names            | Map of user group names                     |
| resource_server_identifiers | Map of resource server identifiers          |

## Free Tier Limits

AWS Cognito Free Tier includes:

- **50,000 MAUs** (Monthly Active Users) for User Pools
- **50,000 MAUs** for Identity Pools
- **50 emails/day** with Cognito email service
- **TOTP MFA** is free (SMS MFA incurs charges)
- **Advanced Security** - 50,000 MAUs in AUDIT mode

## Best Practices

### Security

- **Enable MFA** - Use OPTIONAL or ON for sensitive applications
- **Strong Password Policy** - Minimum 12 characters with complexity requirements
- **Advanced Security** - Enable in AUDIT or ENFORCED mode
- **Deletion Protection** - Set to ACTIVE for production environments
- **Token Revocation** - Enable for all clients
- **User Existence Errors** - Set to ENABLED to prevent user enumeration

### Performance

- **Token Validity** - Balance security and user experience
  - Access tokens: 1 hour
  - ID tokens: 1 hour
  - Refresh tokens: 30 days
- **Caching** - Use token caching in applications
- **Connection Pooling** - Reuse SDK clients

### Cost Optimization

- **Use TOTP MFA** - Avoid SMS costs
- **Cognito Email Service** - Use for low-volume (50 emails/day free)
- **SES Integration** - For high-volume email needs
- **Advanced Security** - Start with AUDIT mode
- **Monitor MAUs** - Track monthly active users

### Monitoring

- **CloudWatch Metrics** - Monitor sign-in success/failure rates
- **Advanced Security Events** - Review risk-based authentication events
- **Lambda Trigger Logs** - Monitor custom authentication flows
- **User Pool Analytics** - Track user activity and engagement

## IAM Permissions

### Required Permissions for Terraform

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cognito-idp:CreateUserPool",
        "cognito-idp:DeleteUserPool",
        "cognito-idp:DescribeUserPool",
        "cognito-idp:UpdateUserPool",
        "cognito-idp:CreateUserPoolClient",
        "cognito-idp:DeleteUserPoolClient",
        "cognito-idp:DescribeUserPoolClient",
        "cognito-idp:UpdateUserPoolClient",
        "cognito-idp:CreateUserPoolDomain",
        "cognito-idp:DeleteUserPoolDomain",
        "cognito-idp:DescribeUserPoolDomain",
        "cognito-idp:CreateGroup",
        "cognito-idp:DeleteGroup",
        "cognito-idp:GetGroup",
        "cognito-idp:UpdateGroup",
        "cognito-idp:CreateResourceServer",
        "cognito-idp:DeleteResourceServer",
        "cognito-idp:DescribeResourceServer",
        "cognito-idp:UpdateResourceServer",
        "cognito-idp:CreateIdentityProvider",
        "cognito-idp:DeleteIdentityProvider",
        "cognito-idp:DescribeIdentityProvider",
        "cognito-idp:UpdateIdentityProvider",
        "cognito-idp:SetRiskConfiguration",
        "cognito-idp:DescribeRiskConfiguration",
        "cognito-idp:SetUICustomization",
        "cognito-idp:GetUICustomization",
        "cognito-idp:TagResource",
        "cognito-idp:UntagResource",
        "cognito-idp:ListTagsForResource"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "cognito-identity:CreateIdentityPool",
        "cognito-identity:DeleteIdentityPool",
        "cognito-identity:DescribeIdentityPool",
        "cognito-identity:UpdateIdentityPool",
        "cognito-identity:SetIdentityPoolRoles",
        "cognito-identity:GetIdentityPoolRoles",
        "cognito-identity:TagResource",
        "cognito-identity:UntagResource",
        "cognito-identity:ListTagsForResource"
      ],
      "Resource": "*"
    }
  ]
}
```

## Troubleshooting

### Common Issues

**User Pool Domain Already Exists**

- Domain names must be globally unique
- Use a unique prefix or suffix

**Lambda Trigger Permissions**

- Ensure Lambda has permission to be invoked by Cognito
- Add resource-based policy to Lambda function

**MFA Not Working**

- Verify SMS configuration and IAM role
- Check SNS permissions for SMS delivery

**Custom Domain Certificate**

- Certificate must be in us-east-1 region
- Certificate must be validated

**Identity Pool Provider Error**

- Ensure User Pool and Client exist before creating Identity Pool
- Use correct provider name format: `cognito-idp.{region}.amazonaws.com/{user_pool_id}`

## Examples

See the [examples](../../examples/cognito/) directory for complete working examples:

- [Basic User Pool](../../examples/cognito/basic.tf)

## Contributing

Contributions are welcome! Please ensure:

- Code follows Terraform best practices
- All variables have descriptions and validations
- Examples are tested and working
- Documentation is updated

## License

This module is provided as-is for infrastructure management.
