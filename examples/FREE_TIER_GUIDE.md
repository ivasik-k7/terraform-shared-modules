# AWS Free Tier - ECR Module Configuration Guide

## Overview

This guide provides a cost-optimized Terraform configuration for AWS ECR in a free tier account. ECR has generous free tier limits, but certain features incur costs that should be avoided during development.

## Free Tier Benefits

AWS ECR free tier includes:

- **50 GB/month** of data storage (per region)
- **500 GB/month** of data transfer out (across all regions combined)
- All API operations are free
- No charge for the registry itself

## Free Tier Optimization Strategy

### 1. **Disable Image Scanning** ✅

**Cost Impact:** Saves $0.05 per image scan

```hcl
scan_on_push = false
```

- Image vulnerability scanning is charged per scan
- Not recommended for dev environments
- Can be enabled in production

### 2. **Use AWS-Managed Encryption (AES256)** ✅

**Cost Impact:** Saves KMS key costs (~$1/month per key)

```hcl
encryption_type = "AES256"
kms_key_arn     = null
```

- AES256 (AWS-managed) is free
- Customer-managed KMS keys incur costs
- Switch to KMS in production if needed

### 3. **Aggressive Lifecycle Policies** ✅

**Cost Impact:** Minimizes storage usage

```hcl
lifecycle_rules = [
  {
    rule_priority = 1
    description   = "Expire untagged images after 3 days"
    tag_status    = "untagged"
    count_type    = "sinceImagePushed"
    count_unit    = "days"
    count_number  = 3
    action_type   = "expire"
  },
  {
    rule_priority = 2
    description   = "Keep only last 10 tagged images"
    tag_status    = "tagged"
    count_type    = "imageCountMoreThan"
    count_number  = 10
    action_type   = "expire"
  }
]
```

- Untagged images: expire after 3 days
- Tagged images: keep only the latest 10
- Prevents accumulation of old images

### 4. **Disable Replication** ✅

**Cost Impact:** Saves data transfer costs

```hcl
enable_replication = false
```

- Cross-region replication incurs data transfer charges
- Use only for multi-region production deployments

### 5. **Disable CloudWatch Logging** ✅

**Cost Impact:** Saves CloudWatch Logs costs (~$0.50/GB ingested)

```hcl
enable_logging = false
```

- ECR audit logs can be expensive in CloudWatch
- Not necessary for development
- Enable selectively in production for compliance

## Storage Estimation

With the recommended dev configuration:

| Scenario                | Storage            | Cost                |
| ----------------------- | ------------------ | ------------------- |
| 5 images (100 MB each)  | 500 MB             | FREE                |
| 10 images (100 MB each) | 1 GB               | FREE                |
| 50 GB usage             | 50 GB              | FREE (within limit) |
| 60 GB usage             | 50 GB free + 10 GB | ~$0.10/month        |

## Usage

### Option 1: Use terraform.tfvars.dev

```bash
# Use the dev configuration
terraform plan -var-file="terraform.tfvars.dev"
terraform apply -var-file="terraform.tfvars.dev"
```

### Option 2: Use with Module

```hcl
module "ecr_dev" {
  source = "./ecr"

  repository_name      = "my-app-dev"
  scan_on_push         = false
  encryption_type      = "AES256"
  enable_replication   = false
  enable_logging       = false

  lifecycle_rules = [
    {
      rule_priority = 1
      description   = "Expire untagged images after 3 days"
      tag_status    = "untagged"
      count_type    = "sinceImagePushed"
      count_number  = 3
    },
    {
      rule_priority = 2
      description   = "Keep last 10 tagged images"
      tag_status    = "tagged"
      count_type    = "imageCountMoreThan"
      count_number  = 10
    }
  ]

  tags = {
    Environment = "development"
  }
}
```

## Progression Path: Dev → Staging → Production

### Development (Free Tier)

- ❌ Image scanning: disabled
- ❌ Logging: disabled
- ❌ Replication: disabled
- ✅ Encryption: AES256 (AWS-managed)
- ✅ Aggressive lifecycle: 3 days untagged, 10 images max

### Staging

- ✅ Image scanning: enabled
- ✅ Logging: CloudWatch with 7-day retention
- ❌ Replication: disabled
- ✅ Encryption: AES256
- ✅ Moderate lifecycle: 30 days untagged, 50 images max

### Production

- ✅ Image scanning: enabled
- ✅ Logging: CloudWatch with 30-90 day retention
- ✅ Replication: enabled (if multi-region)
- ✅ Encryption: KMS (customer-managed)
- ✅ Conservative lifecycle: 90+ days, 100+ images max

## Monitoring Free Tier Usage

Check your ECR usage in AWS Console:

1. Go to ECR → Repositories
2. View storage usage per repository
3. Monitor data transfer in CloudWatch

Estimate costs:

- Storage over 50 GB: $0.10 per GB/month
- Data transfer out: $0.02 per GB/month

## Transitioning to Paid Features

When moving to production, gradually enable features:

```hcl
# Production configuration
scan_on_push              = true        # Enable vulnerability scanning
encryption_type           = "KMS"       # Customer-managed encryption
kms_key_arn              = aws_kms_key.ecr.arn
enable_logging           = true        # Enable audit logging
cloudwatch_log_retention_days = 30
enable_replication       = true        # Cross-region replication
```

## Best Practices for Free Tier

1. **Always use lifecycle policies** - Prevent storage bloat
2. **Tag consistently** - Makes lifecycle rules more predictable
3. **Monitor regularly** - Check AWS Billing Dashboard monthly
4. **Clean up manually** - Remove old repositories regularly
5. **Use multiple repositories** - Separate by application
6. **Set up billing alerts** - Notify when spending increases

## Cost Saving Tips

| Action                      | Estimated Savings            |
| --------------------------- | ---------------------------- |
| Disable image scanning      | $0.05 per scan               |
| Use AES256 encryption       | ~$1/month per key            |
| Aggressive lifecycle policy | ~$5/month (storage)          |
| Disable replication         | ~$2-10/month (data transfer) |
| Disable logging             | ~$0.50/month                 |
| **Total potential savings** | **~$8-16/month**             |

## Troubleshooting

**Q: Images are disappearing too quickly**

- Increase lifecycle rule thresholds
- Ensure proper image tagging strategy

**Q: Storage is exceeding 50 GB**

- Review image sizes and compression
- Increase aggressiveness of lifecycle policies
- Delete unused repositories

**Q: Billing alert triggered**

- Check for data transfer costs (replication)
- Verify image scanning isn't enabled
- Review lifecycle policy effectiveness

## Additional Resources

- [AWS ECR Pricing](https://aws.amazon.com/ecr/pricing/)
- [AWS Free Tier Details](https://aws.amazon.com/free/)
- [ECR Best Practices](https://docs.aws.amazon.com/AmazonECR/latest/userguide/security-considerations.html)
- [Terraform AWS ECR Module](https://registry.terraform.io/modules/terraform-aws-modules/ecr/aws)
