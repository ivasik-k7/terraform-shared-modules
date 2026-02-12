# AWS KMS Terraform Module

A comprehensive, production-ready Terraform module for creating and managing AWS KMS (Key Management Service) keys with excellent flexibility and developer experience.

## Features

- ✅ **Flexible Configuration**: Support for all KMS key types and configurations
- 🔄 **Automatic Key Rotation**: Configurable rotation periods with sensible defaults
- 🔐 **Custom Policies**: Easy policy management with default and custom statements
- 🎁 **KMS Grants**: Built-in support for service and principal grants
- 🌍 **Multi-Region Support**: Create multi-region primary keys
- 🏷️ **Smart Tagging**: Auto-generated descriptions and comprehensive tagging
- ✔️ **Input Validation**: Extensive validation for all variables
- 📦 **Multiple Examples**: Real-world usage examples included
- 🎯 **Best Practices**: Follows AWS and Terraform best practices

## Usage

### Basic Example

```hcl
module "kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "my-application-key"
  purpose     = "application"
  environment = "production"

  tags = {
    Team    = "Platform"
    Project = "MyApp"
  }
}

# Use in other resources
resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = "my-bucket"

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.kms_key.key_arn
    }
  }
}
```

### Advanced Example with Custom Policy

```hcl
data "aws_iam_role" "app_role" {
  name = "my-application-role"
}

module "kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "database-encryption-key"
  purpose     = "database"
  environment = "production"

  # Advanced configuration
  multi_region            = true
  enable_key_rotation     = true
  rotation_period_in_days = 90

  # Additional policy statements
  additional_policy_statements = [
    {
      Sid    = "AllowApplicationAccess"
      Effect = "Allow"
      Principal = {
        AWS = data.aws_iam_role.app_role.arn
      }
      Action = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey"
      ]
      Resource = "*"
    }
  ]

  # KMS Grants
  grants = {
    rds_grant = {
      grantee_principal = "arn:aws:iam::123456789012:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
      operations        = ["Decrypt", "Encrypt", "GenerateDataKey", "CreateGrant"]
    }
  }

  tags = {
    CostCenter = "Engineering"
    Compliance = "PCI-DSS"
  }
}
```

### Complete Custom Policy

```hcl
module "kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "custom-policy-key"
  purpose     = "custom"
  environment = "production"

  # Provide complete custom policy
  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow specific role"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:role/MyRole"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## Examples

This module includes several complete examples:

- [**basic**](examples/basic/main.tf) - Simplest possible usage
- [**advanced**](examples/advanced/main.tf) - Advanced features with grants and custom policies
- [**multiple-keys**](examples/multiple-keys/main.tf) - Managing multiple keys for different services

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| aws | >= 5.0 |

## Inputs

### Required Variables

| Name | Description | Type |
|------|-------------|------|
| `name` | Name of the KMS key (used for alias and tags) | `string` |

### Key Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `description` | Description of the KMS key | `string` | Auto-generated |
| `key_usage` | Intended use: ENCRYPT_DECRYPT, SIGN_VERIFY, or GENERATE_VERIFY_MAC | `string` | `"ENCRYPT_DECRYPT"` |
| `customer_master_key_spec` | Key specification | `string` | `"SYMMETRIC_DEFAULT"` |
| `multi_region` | Create a multi-region primary key | `bool` | `false` |

### Policy Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `key_policy` | Complete custom key policy (JSON) | `string` | `null` |
| `additional_policy_statements` | Additional policy statements to append | `list(object)` | `null` |
| `bypass_policy_lockout_safety_check` | Bypass policy lockout safety check | `bool` | `false` |

### Rotation & Deletion

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `enable_key_rotation` | Enable automatic key rotation | `bool` | `true` |
| `rotation_period_in_days` | Period for automatic rotation (90-2560) | `number` | `365` |
| `deletion_window_in_days` | Deletion window (7-30 days) | `number` | `30` |
| `is_enabled` | Whether the key is enabled | `bool` | `true` |

### Alias Configuration

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `create_alias` | Create an alias for the KMS key | `bool` | `true` |
| `alias_name` | Alias name (defaults to `alias/{name}`) | `string` | `null` |

### Grants

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `grants` | Map of KMS grants to create | `map(object)` | `{}` |

### Metadata & Tags

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `purpose` | Purpose of the key (used in description/tags) | `string` | `null` |
| `environment` | Environment name (used in description/tags) | `string` | `null` |
| `tags` | Additional tags for the KMS key | `map(string)` | `{}` |

## Outputs

### Key Identifiers

| Name | Description |
|------|-------------|
| `key_id` | The globally unique identifier for the KMS key |
| `key_arn` | The Amazon Resource Name (ARN) of the KMS key |
| `alias_name` | The display name of the alias |
| `alias_arn` | The ARN of the key alias |

### Key Attributes

| Name | Description |
|------|-------------|
| `key_usage` | The cryptographic usage of the KMS key |
| `customer_master_key_spec` | The key spec of the KMS key |
| `multi_region` | Whether the key is a multi-region key |
| `is_enabled` | Whether the key is enabled |

### Rotation & Security

| Name | Description |
|------|-------------|
| `enable_key_rotation` | Whether automatic key rotation is enabled |
| `rotation_period_in_days` | The period in days for automatic key rotation |
| `deletion_window_in_days` | Duration before deletion |

### Grants

| Name | Description |
|------|-------------|
| `grant_ids` | Map of grant names to their IDs |
| `grant_tokens` | Map of grant names to their tokens (sensitive) |

### Convenient Outputs

| Name | Description |
|------|-------------|
| `kms_key_for_encryption` | Convenient bundle of key_id, key_arn, and alias |

## Common Use Cases

### S3 Bucket Encryption

```hcl
module "s3_kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "s3-bucket-encryption"
  purpose     = "s3"
  environment = "production"

  additional_policy_statements = [
    {
      Sid    = "AllowS3ToUseKey"
      Effect = "Allow"
      Principal = {
        Service = "s3.amazonaws.com"
      }
      Action   = ["kms:Decrypt", "kms:GenerateDataKey"]
      Resource = "*"
    }
  ]
}

resource "aws_s3_bucket_server_side_encryption_configuration" "example" {
  bucket = aws_s3_bucket.example.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = module.s3_kms_key.key_arn
    }
  }
}
```

### RDS Database Encryption

```hcl
module "rds_kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "rds-database-encryption"
  purpose     = "database"
  environment = "production"

  enable_key_rotation     = true
  rotation_period_in_days = 90

  additional_policy_statements = [
    {
      Sid    = "AllowRDSToUseKey"
      Effect = "Allow"
      Principal = {
        Service = "rds.amazonaws.com"
      }
      Action   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:CreateGrant"]
      Resource = "*"
    }
  ]
}

resource "aws_db_instance" "example" {
  # ... other configuration ...
  storage_encrypted = true
  kms_key_id        = module.rds_kms_key.key_arn
}
```

### Secrets Manager Encryption

```hcl
module "secrets_kms_key" {
  source = "path/to/terraform-aws-kms"

  name        = "secrets-manager-encryption"
  purpose     = "secrets"
  environment = "production"

  additional_policy_statements = [
    {
      Sid    = "AllowSecretsManagerToUseKey"
      Effect = "Allow"
      Principal = {
        Service = "secretsmanager.amazonaws.com"
      }
      Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
      Resource = "*"
    }
  ]
}

resource "aws_secretsmanager_secret" "example" {
  name       = "my-secret"
  kms_key_id = module.secrets_kms_key.key_id
}
```

## Best Practices

### 1. Enable Key Rotation

Always enable automatic key rotation for symmetric encryption keys:

```hcl
enable_key_rotation     = true
rotation_period_in_days = 365  # or 90 for higher security requirements
```

### 2. Use Descriptive Names and Tags

```hcl
name        = "rds-production-encryption"
purpose     = "database"
environment = "production"

tags = {
  CostCenter = "Engineering"
  Compliance = "PCI-DSS"
  DataClass  = "Confidential"
}
```

### 3. Implement Least Privilege

Only grant necessary permissions in your key policies:

```hcl
additional_policy_statements = [
  {
    Sid    = "AllowSpecificRoleDecryptOnly"
    Effect = "Allow"
    Principal = {
      AWS = "arn:aws:iam::123456789012:role/MyApplicationRole"
    }
    Action   = ["kms:Decrypt", "kms:DescribeKey"]
    Resource = "*"
  }
]
```

### 4. Use KMS Grants for Service Integration

For AWS services that need temporary access:

```hcl
grants = {
  rds_encryption = {
    grantee_principal = "arn:aws:iam::123456789012:role/aws-service-role/rds.amazonaws.com/AWSServiceRoleForRDS"
    operations        = ["Decrypt", "Encrypt", "GenerateDataKey", "CreateGrant"]
  }
}
```

### 5. Set Appropriate Deletion Windows

For production keys, use longer deletion windows:

```hcl
deletion_window_in_days = 30  # Maximum allowed
```

## Security Considerations

- **Key Policies**: Always review and test key policies before applying to production
- **Multi-Region Keys**: Use for disaster recovery scenarios, but be aware of replication implications
- **Key Rotation**: Automatic rotation doesn't affect data encrypted with old key versions
- **Grants vs Policies**: Use grants for temporary or service-specific access; use policies for long-term permissions
- **Monitoring**: Enable CloudTrail logging for all KMS operations

## Troubleshooting

### Policy Lockout

If you're locked out due to a policy error, you may need to use:

```hcl
bypass_policy_lockout_safety_check = true
```

**Warning**: Only use this when you understand the implications.

### Key Cannot Be Deleted

KMS keys have a mandatory waiting period (7-30 days) before deletion. Plan accordingly.

## Contributing

Contributions are welcome! Please ensure:

1. All examples run successfully
2. Variables include proper validation
3. Documentation is updated
4. Code follows Terraform best practices

## License

MIT License - see LICENSE file for details

## Authors

Created and maintained by your team.

## Changelog

### v1.0.0
- Initial release with full KMS support
- Multi-region key support
- Flexible policy management
- Comprehensive examples
