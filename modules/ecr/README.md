# ECR Module

A Terraform module for creating and managing AWS Elastic Container Registry (ECR) repositories with advanced features including lifecycle policies, replication, encryption, and access control.

## Features

- **Repository Management**: Create ECR repositories with configurable image tag mutability
- **Security**:
  - Image scanning on push for vulnerability detection
  - KMS encryption for customer-managed encryption keys
  - Fine-grained IAM repository policies
- **Lifecycle Management**: Automatic image cleanup with flexible retention policies
- **Replication**: Cross-region and cross-registry image replication
- **Logging**: CloudWatch integration for audit logging
- **Access Control**: Support for multiple principals with different access levels (push/pull vs pull-only)
- **Tagging**: Consistent tagging across all resources

## Usage

### Basic Example

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### With Image Scanning and Lifecycle Policies

```hcl
module "ecr" {
  source = "./ecr"

  repository_name         = "my-app"
  scan_on_push           = true
  image_tag_mutability   = "IMMUTABLE"
  enable_lifecycle_policy = true

  lifecycle_rules = [
    {
      rule_priority = 1
      description   = "Expire untagged images after 7 days"
      tag_status    = "untagged"
      count_type    = "sinceImagePushed"
      count_unit    = "days"
      count_number  = 7
    },
    {
      rule_priority = 2
      description   = "Keep only last 50 tagged images"
      tag_status    = "tagged"
      count_type    = "imageCountMoreThan"
      count_number  = 50
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### With Encryption and Access Control

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  # KMS Encryption
  encryption_type = "KMS"
  kms_key_arn     = aws_kms_key.ecr.arn

  # Access Control
  create_repository_policy = true
  allowed_principals       = ["arn:aws:iam::123456789012:role/eks-node-role"]
  allowed_pull_principals  = ["arn:aws:iam::123456789012:role/lambda-role"]

  tags = {
    Environment = "production"
  }
}
```

### With Cross-Region Replication

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  enable_replication = true

  replication_rules = [
    {
      destinations = [
        {
          region      = "eu-west-1"
          registry_id = "123456789012"
        }
      ]
      repository_filters = [
        {
          filter_type = "PREFIX_MATCH"
          filter      = "prod-"
        }
      ]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

### Repository Configuration

| Name                   | Description                                   | Type     | Default       | Required |
| ---------------------- | --------------------------------------------- | -------- | ------------- | :------: |
| `repository_name`      | The name of the ECR repository                | `string` | -             |   yes    |
| `image_tag_mutability` | Tag mutability setting (IMMUTABLE or MUTABLE) | `string` | `"IMMUTABLE"` |    no    |

### Image Scanning

| Name           | Description                           | Type   | Default | Required |
| -------------- | ------------------------------------- | ------ | ------- | :------: |
| `scan_on_push` | Enable vulnerability scanning on push | `bool` | `true`  |    no    |

### Encryption

| Name              | Description                                        | Type     | Default    | Required |
| ----------------- | -------------------------------------------------- | -------- | ---------- | :------: |
| `encryption_type` | Encryption type (AES256 or KMS)                    | `string` | `"AES256"` |    no    |
| `kms_key_arn`     | KMS key ARN (required when encryption_type is KMS) | `string` | `null`     |    no    |

### Lifecycle Management

| Name                      | Description                                 | Type                | Default           | Required |
| ------------------------- | ------------------------------------------- | ------------------- | ----------------- | :------: |
| `enable_lifecycle_policy` | Enable lifecycle policy for image cleanup   | `bool`              | `true`            |    no    |
| `lifecycle_rules`         | List of lifecycle rules for image retention | `list(object(...))` | See default rules |    no    |

### Repository Access Control

| Name                           | Description                                      | Type                | Default             | Required |
| ------------------------------ | ------------------------------------------------ | ------------------- | ------------------- | :------: |
| `create_repository_policy`     | Whether to create and attach a repository policy | `bool`              | `true`              |    no    |
| `repository_policy_statements` | Additional IAM policy statements                 | `list(object(...))` | Account root access |    no    |
| `allowed_principals`           | Principals with push/pull access                 | `list(string)`      | `[]`                |    no    |
| `allowed_pull_principals`      | Principals with pull-only access                 | `list(string)`      | `[]`                |    no    |

### Replication

| Name                 | Description                                      | Type                | Default | Required |
| -------------------- | ------------------------------------------------ | ------------------- | ------- | :------: |
| `enable_replication` | Enable repository replication                    | `bool`              | `false` |    no    |
| `replication_rules`  | Replication rules for cross-region/registry sync | `list(object(...))` | `[]`    |    no    |

### Logging

| Name                            | Description                               | Type     | Default                      | Required |
| ------------------------------- | ----------------------------------------- | -------- | ---------------------------- | :------: |
| `enable_logging`                | Enable CloudWatch logging for ECR actions | `bool`   | `false`                      |    no    |
| `cloudwatch_log_group_name`     | CloudWatch log group name                 | `string` | `/aws/ecr/{repository_name}` |    no    |
| `cloudwatch_log_retention_days` | Log retention period in days              | `number` | `30`                         |    no    |

### Tags

| Name          | Description                         | Type          | Default | Required |
| ------------- | ----------------------------------- | ------------- | ------- | :------: |
| `tags`        | Tags to apply to all resources      | `map(string)` | `{}`    |    no    |
| `common_tags` | Common tags alongside tags variable | `map(string)` | `{}`    |    no    |

## Outputs

| Name                           | Description                              |
| ------------------------------ | ---------------------------------------- |
| `repository_url`               | The URL of the repository                |
| `repository_arn`               | The ARN of the repository                |
| `repository_name`              | The name of the repository               |
| `registry_id`                  | The AWS account ID (registry ID)         |
| `image_tag_mutability`         | The tag mutability setting               |
| `image_scanning_configuration` | The image scanning configuration         |
| `encryption_configuration`     | The encryption configuration (sensitive) |
| `repository_policy_arn`        | The ARN of the repository policy         |
| `repository_policy_created`    | Whether a repository policy was created  |
| `lifecycle_policy_created`     | Whether a lifecycle policy was created   |
| `lifecycle_rules`              | The applied lifecycle rules              |
| `replication_enabled`          | Whether replication is enabled           |
| `replication_configuration`    | The replication configuration            |
| `log_group_name`               | CloudWatch log group name                |
| `log_group_arn`                | CloudWatch log group ARN                 |
| `allowed_push_principals`      | Principals with push/pull access         |
| `allowed_pull_principals`      | Principals with read-only access         |

## Lifecycle Rules

Default lifecycle rules expire untagged images older than 7 days and keep the latest 100 tagged images. Customize with the `lifecycle_rules` variable:

```hcl
lifecycle_rules = [
  {
    rule_priority   = 1
    description     = "Your rule description"
    tag_status      = "untagged"        # untagged, tagged, or any
    tag_prefix_list = ["v"]             # Optional: filter by tag prefix
    count_type      = "sinceImagePushed" # or imageCountMoreThan
    count_unit      = "days"            # or imageCountMoreThan (for count_type=imageCountMoreThan)
    count_number    = 7
    action_type     = "expire"          # or copy
  }
]
```

## Repository Policy

By default, the module creates a repository policy granting full access to the AWS account root. Add additional principals for:

- **Push/Pull Access**: Use `allowed_principals`
- **Pull-Only Access**: Use `allowed_pull_principals`

Or customize completely with `repository_policy_statements`.

## Encryption

Choose between:

- **AES256**: AWS-managed encryption (default, no additional cost)
- **KMS**: Customer-managed encryption with `kms_key_arn`

## Requirements

- Terraform >= 1.5.0
- AWS Provider >= 5.0

## Notes

- Repository names must start with lowercase letter/number and contain only lowercase letters, numbers, hyphens, underscores, and forward slashes
- Image tag mutability cannot be changed after repository creation
- Lifecycle policies cannot be modified while replication is active
- CloudWatch logging requires appropriate IAM permissions
- Repository policies are account-wide and affect all access to the repository
