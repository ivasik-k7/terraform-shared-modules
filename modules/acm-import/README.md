# AWS ACM Certificate Import Module

A flexible Terraform module for importing one or multiple external SSL/TLS certificates into AWS Certificate Manager (ACM).

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Usage](#usage)
  - [Basic Examples](#basic-examples)
  - [Advanced Examples](#advanced-examples)
- [Inputs](#inputs)
- [Outputs](#outputs)
- [Certificate File Format](#certificate-file-format)
- [Best Practices](#best-practices)
- [Important Notes](#important-notes)

## Features

✅ **Bulk Import** - Import multiple certificates in a single module call  
✅ **Flexible Input** - Support for file paths or inline content  
✅ **Individual Configuration** - Per-certificate tags and names  
✅ **Comprehensive Outputs** - Access certificates by key with rich metadata  
✅ **Input Validation** - Prevents common configuration mistakes  
✅ **Secure** - Sensitive data handling for private keys  
✅ **Multi-Region Ready** - Easy deployment across AWS regions

## Requirements

| Name      | Version |
| --------- | ------- |
| terraform | >= 1.0  |
| aws       | >= 5.0  |

## Usage

### Basic Examples

#### Single Certificate Import

```hcl
module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    primary = {
      certificate_body_path  = "${path.module}/certs/certificate.pem"
      private_key_path       = "${path.module}/certs/private-key.pem"
      certificate_chain_path = "${path.module}/certs/ca-bundle.pem"
      name                   = "example.com"
    }
  }

  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
  }
}
```

#### Multiple Certificates Import

```hcl
module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    web = {
      certificate_body_path  = "${path.module}/certs/web/cert.pem"
      private_key_path       = "${path.module}/certs/web/key.pem"
      certificate_chain_path = "${path.module}/certs/web/chain.pem"
      name                   = "www.example.com"
      tags = {
        Service = "web"
      }
    }

    api = {
      certificate_body_path  = "${path.module}/certs/api/cert.pem"
      private_key_path       = "${path.module}/certs/api/key.pem"
      certificate_chain_path = "${path.module}/certs/api/chain.pem"
      name                   = "api.example.com"
      tags = {
        Service = "api"
      }
    }
  }

  tags = {
    Environment = "production"
    Project     = "platform"
  }
}
```

#### Using Inline Content

```hcl
module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    secure = {
      certificate_body  = var.cert_body_pem
      private_key       = var.cert_private_key_pem
      certificate_chain = var.cert_chain_pem
      name              = "secure.example.com"
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### Advanced Examples

#### Dynamic Certificate Import from Directory

```hcl
locals {
  # Assuming naming convention: web-cert.pem, web-key.pem, web-chain.pem
  cert_files = fileset("${path.module}/certs", "*.pem")

  cert_names = distinct([
    for file in local.cert_files :
    replace(file, "/-(cert|key|chain)\\.pem$/", "")
  ])

  certificates = {
    for name in local.cert_names : name => {
      certificate_body_path  = "${path.module}/certs/${name}-cert.pem"
      private_key_path       = "${path.module}/certs/${name}-key.pem"
      certificate_chain_path = fileexists("${path.module}/certs/${name}-chain.pem") ?
                               "${path.module}/certs/${name}-chain.pem" : null
      name = name
    }
  }
}

module "acm_import" {
  source = "./modules/acm-import"

  certificates = local.certificates

  tags = {
    Environment = "production"
    Source      = "dynamic-import"
  }
}
```

#### Integration with AWS Secrets Manager

```hcl
data "aws_secretsmanager_secret_version" "certificates" {
  for_each  = toset(["web", "api", "admin"])
  secret_id = "prod/${each.key}-ssl-certificate"
}

locals {
  cert_secrets = {
    for key, secret in data.aws_secretsmanager_secret_version.certificates :
    key => jsondecode(secret.secret_string)
  }
}

module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    for key, cert_data in local.cert_secrets : key => {
      certificate_body  = cert_data.certificate
      private_key       = cert_data.private_key
      certificate_chain = cert_data.chain
      name              = "${key}.example.com"
      tags = {
        Source = "secrets-manager"
      }
    }
  }

  tags = {
    Environment = "production"
  }
}
```

#### Multi-Region Deployment

```hcl
# us-east-1 (required for CloudFront)
module "acm_import_us_east_1" {
  source = "./modules/acm-import"

  providers = {
    aws = aws.us_east_1
  }

  certificates = var.certificates

  tags = {
    Region      = "us-east-1"
    Environment = "production"
  }
}

# eu-west-1 (for regional resources)
module "acm_import_eu_west_1" {
  source = "./modules/acm-import"

  providers = {
    aws = aws.eu_west_1
  }

  certificates = var.certificates

  tags = {
    Region      = "eu-west-1"
    Environment = "production"
  }
}
```

#### Mixed Sources (Files + Secrets)

```hcl
module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    # From local files
    internal = {
      certificate_body_path  = "${path.module}/certs/internal.pem"
      private_key_path       = "${path.module}/certs/internal-key.pem"
      certificate_chain_path = "${path.module}/certs/ca-bundle.pem"
      name                   = "internal.example.local"
    }

    # From Secrets Manager
    external = {
      certificate_body  = data.aws_secretsmanager_secret_version.external_cert.secret_string
      private_key       = data.aws_secretsmanager_secret_version.external_key.secret_string
      certificate_chain = data.aws_secretsmanager_secret_version.external_chain.secret_string
      name              = "external.example.com"
    }
  }
}
```

## Inputs

### Required Inputs

| Name         | Description                   | Type          |
| ------------ | ----------------------------- | ------------- |
| certificates | Map of certificates to import | `map(object)` |

### Certificate Object Structure

Each certificate in the `certificates` map should have the following structure:

```hcl
{
  certificate_body_path  = optional(string)  # Path to certificate PEM file
  certificate_body       = optional(string)  # Certificate PEM content (sensitive)
  private_key_path       = optional(string)  # Path to private key PEM file
  private_key            = optional(string)  # Private key PEM content (sensitive)
  certificate_chain_path = optional(string)  # Path to certificate chain PEM file
  certificate_chain      = optional(string)  # Certificate chain PEM content (sensitive)
  name                   = optional(string)  # Name tag for the certificate
  tags                   = optional(map(string), {})  # Additional tags
}
```

**Rules:**

- Either `certificate_body` OR `certificate_body_path` must be provided (not both)
- Either `private_key` OR `private_key_path` must be provided (not both)
- Either `certificate_chain` OR `certificate_chain_path` can be provided (not both)
- `certificate_chain` is optional for self-signed certificates
- `name` is optional; defaults to the certificate key if not provided
- `tags` are optional and merged with global tags

### Optional Inputs

| Name     | Description                               | Type          | Default |
| -------- | ----------------------------------------- | ------------- | ------- |
| tags     | Map of tags to assign to all certificates | `map(string)` | `{}`    |
| tags_all | Map of tags assigned to all resources     | `map(string)` | `{}`    |

## Outputs

### Map Outputs (Access by Certificate Key)

| Name                                  | Description                                 | Type                |
| ------------------------------------- | ------------------------------------------- | ------------------- |
| certificates                          | Complete details for all certificates       | `map(object)`       |
| certificate_arns                      | Map of certificate keys to ARNs             | `map(string)`       |
| certificate_ids                       | Map of certificate keys to IDs              | `map(string)`       |
| certificate_domain_names              | Map of certificate keys to domain names     | `map(string)`       |
| certificate_expiration_dates          | Map of certificate keys to expiration dates | `map(string)`       |
| certificate_subject_alternative_names | Map of certificate keys to SANs             | `map(list(string))` |
| certificate_key_algorithms            | Map of certificate keys to key algorithms   | `map(string)`       |

### List Outputs

| Name                  | Description                           | Type           |
| --------------------- | ------------------------------------- | -------------- |
| certificate_arns_list | List of all certificate ARNs          | `list(string)` |
| certificate_count     | Total number of certificates imported | `number`       |

### Output Usage Examples

```hcl
# Get specific certificate ARN
output "web_cert_arn" {
  value = module.acm_import.certificate_arns["web"]
}

# Get all certificate ARNs
output "all_cert_arns" {
  value = module.acm_import.certificate_arns
}

# Get complete details for a certificate
output "web_cert_details" {
  value = module.acm_import.certificates["web"]
}

# Use in ALB listener
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = module.acm_import.certificate_arns["web"]

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }
}

# Use in CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  # ... other configuration ...

  viewer_certificate {
    acm_certificate_arn = module.acm_import.certificate_arns["web"]
    ssl_support_method  = "sni-only"
  }
}
```

## Certificate File Format

All certificates must be in PEM format.

### Certificate Body (certificate.pem)

```
-----BEGIN CERTIFICATE-----
MIIDXTCCAkWgAwIBAgIJAKJ...
[certificate content]
...
-----END CERTIFICATE-----
```

### Private Key (private-key.pem)

Supported formats:

- RSA Private Key
- EC Private Key
- PKCS#8 Private Key

```
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA3...
[private key content]
...
-----END RSA PRIVATE KEY-----
```

or

```
-----BEGIN EC PRIVATE KEY-----
MHcCAQEEIIGlRPKD...
[private key content]
...
-----END EC PRIVATE KEY-----
```

or

```
-----BEGIN PRIVATE KEY-----
MIIEvgIBADANBgkq...
[private key content]
...
-----END PRIVATE KEY-----
```

### Certificate Chain (ca-bundle.pem or chain.pem)

Include intermediate certificates in order (optional for self-signed):

```
-----BEGIN CERTIFICATE-----
[Intermediate Certificate 1]
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
[Intermediate Certificate 2]
-----END CERTIFICATE-----
-----BEGIN CERTIFICATE-----
[Root Certificate - optional]
-----END CERTIFICATE-----
```

## Best Practices

### Security

1. **Never commit private keys to version control**

   ```bash
   # Add to .gitignore
   *.pem
   *.key
   certs/
   ```

2. **Use secret management systems**

   - AWS Secrets Manager
   - HashiCorp Vault
   - Terraform Cloud/Enterprise sensitive variables
   - AWS Systems Manager Parameter Store

3. **Encrypt sensitive data at rest**

   ```hcl
   # Use encrypted S3 bucket for cert storage
   # Use AWS KMS for key encryption
   ```

4. **Rotate certificates before expiration**
   - Set up CloudWatch alarms for expiration
   - Implement automated renewal processes

### File Organization

#### Recommended Directory Structure

```
project/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── modules/
│       └── acm-import/
│           ├── main.tf
│           ├── variables.tf
│           ├── outputs.tf
│           ├── versions.tf
│           └── README.md
└── certs/                    # Add to .gitignore!
    ├── web/
    │   ├── cert.pem
    │   ├── key.pem
    │   └── chain.pem
    ├── api/
    │   ├── cert.pem
    │   ├── key.pem
    │   └── chain.pem
    └── admin/
        ├── cert.pem
        ├── key.pem
        └── chain.pem
```

#### Alternative: Flat Structure with Naming Convention

```
certs/
├── web-cert.pem
├── web-key.pem
├── web-chain.pem
├── api-cert.pem
├── api-key.pem
├── api-chain.pem
├── admin-cert.pem
├── admin-key.pem
└── admin-chain.pem
```

### Tagging Strategy

```hcl
module "acm_import" {
  source = "./modules/acm-import"

  certificates = {
    web = {
      # ... certificate config ...
      tags = {
        Service     = "web-frontend"
        CostCenter  = "engineering"
        Compliance  = "pci-dss"
      }
    }
  }

  # Global tags applied to all certificates
  tags = {
    Environment = "production"
    ManagedBy   = "terraform"
    Team        = "platform"
    Project     = "main-website"
  }
}
```

### Certificate Monitoring

Set up CloudWatch alarms for certificate expiration:

```hcl
resource "aws_cloudwatch_metric_alarm" "cert_expiration" {
  for_each = module.acm_import.certificate_arns

  alarm_name          = "acm-cert-expiration-${each.key}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "DaysToExpiry"
  namespace           = "AWS/CertificateManager"
  period              = "86400"  # 1 day
  statistic           = "Minimum"
  threshold           = "30"     # Alert 30 days before expiration
  alarm_description   = "Certificate ${each.key} expires in less than 30 days"

  dimensions = {
    CertificateArn = each.value
  }
}
```

## Important Notes

### Certificate Renewal

⚠️ **Important**: ACM does NOT automatically renew imported certificates. You must:

- Track expiration dates
- Renew certificates with your CA
- Re-import updated certificates before expiration
- Plan for zero-downtime certificate updates

### Regional Considerations

- ACM certificates are **region-specific**
- For **CloudFront**: certificates must be in `us-east-1`
- For **regional resources** (ALB, API Gateway): import to the resource region
- Use the multi-region pattern for global deployments

### Supported Resources

Imported ACM certificates can be used with:

- Application Load Balancer (ALB)
- Network Load Balancer (NLB)
- CloudFront Distributions
- API Gateway
- Elastic Beanstalk
- CloudFormation

### Limitations

- Maximum certificate size: 2048 bytes (including chain)
- Private keys must be unencrypted
- Supported key algorithms: RSA (1024, 2048, 3072, 4096), ECDSA (P-256, P-384, P-521)
- No automated renewal for imported certificates
- Certificate chain order matters (intermediate → root)

### Migration from Existing Certificates

When replacing existing certificates:

```hcl
resource "aws_lb_listener" "https" {
  # ... other config ...

  certificate_arn = module.acm_import.certificate_arns["new"]

  lifecycle {
    create_before_destroy = true
  }
}

# Add old certificate as additional certificate during migration
resource "aws_lb_listener_certificate" "old_cert" {
  listener_arn    = aws_lb_listener.https.arn
  certificate_arn = var.old_certificate_arn
}
```

## Troubleshooting

### Common Issues

**Error: Invalid certificate format**

- Ensure certificates are in PEM format
- Check for proper BEGIN/END markers
- Verify no extra whitespace or newlines

**Error: Private key doesn't match certificate**

- Verify you're using the correct private key file
- Check key wasn't re-generated after certificate creation

**Error: Certificate chain validation failed**

- Ensure intermediate certificates are in correct order
- Verify chain includes all necessary intermediates
- Check that chain matches the certificate

**Certificate not appearing in ACM console**

- Verify you're checking the correct AWS region
- Check IAM permissions for ACM
- Review Terraform state

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## Acknowledgments

- AWS Certificate Manager documentation
- Terraform AWS Provider documentation
- Community contributors

---

For questions or issues, please open an issue in the GitHub repository.
