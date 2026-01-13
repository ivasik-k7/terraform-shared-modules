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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.ecr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_ecr_lifecycle_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_lifecycle_policy) | resource |
| [aws_ecr_pull_through_cache_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_pull_through_cache_rule) | resource |
| [aws_ecr_registry_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_registry_policy) | resource |
| [aws_ecr_registry_scanning_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_registry_scanning_configuration) | resource |
| [aws_ecr_replication_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_replication_configuration) | resource |
| [aws_ecr_repository.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository) | resource |
| [aws_ecr_repository_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_principals"></a> [allowed\_principals](#input\_allowed\_principals) | AWS principals (roles, users, accounts) that should have pull/push access to the repository. Format: arn:aws:iam::ACCOUNT\_ID:role/ROLE\_NAME | `list(string)` | `[]` | no |
| <a name="input_allowed_pull_principals"></a> [allowed\_pull\_principals](#input\_allowed\_pull\_principals) | AWS principals (roles, users, accounts) that should have read-only (pull) access to the repository | `list(string)` | `[]` | no |
| <a name="input_cloudwatch_kms_key_id"></a> [cloudwatch\_kms\_key\_id](#input\_cloudwatch\_kms\_key\_id) | The KMS key ID to use for encrypting CloudWatch log data. Only used if enable\_logging is true. | `string` | `null` | no |
| <a name="input_cloudwatch_log_group_name"></a> [cloudwatch\_log\_group\_name](#input\_cloudwatch\_log\_group\_name) | CloudWatch log group name for ECR logs. Only used if enable\_logging is true. | `string` | `null` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | CloudWatch log retention period in days | `number` | `30` | no |
| <a name="input_common_tags"></a> [common\_tags](#input\_common\_tags) | Common tags to apply alongside the tags variable for consistent resource identification | `map(string)` | `{}` | no |
| <a name="input_create_repository_policy"></a> [create\_repository\_policy](#input\_create\_repository\_policy) | Whether to create and attach a repository policy | `bool` | `true` | no |
| <a name="input_enable_lifecycle_policy"></a> [enable\_lifecycle\_policy](#input\_enable\_lifecycle\_policy) | Enable lifecycle policy for automatic image cleanup and retention management | `bool` | `true` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable CloudWatch logging for ECR actions | `bool` | `false` | no |
| <a name="input_enable_registry_policy"></a> [enable\_registry\_policy](#input\_enable\_registry\_policy) | Enable registry-level policy | `bool` | `false` | no |
| <a name="input_enable_registry_scanning"></a> [enable\_registry\_scanning](#input\_enable\_registry\_scanning) | Enable enhanced scanning at the registry level | `bool` | `false` | no |
| <a name="input_enable_replication"></a> [enable\_replication](#input\_enable\_replication) | Enable repository image replication across regions or registries | `bool` | `false` | no |
| <a name="input_encryption_type"></a> [encryption\_type](#input\_encryption\_type) | The encryption type for the repository. AES256 (AWS-managed) or KMS (customer-managed key) | `string` | `"AES256"` | no |
| <a name="input_force_delete"></a> [force\_delete](#input\_force\_delete) | If true, forces the deletion of the repository even if it contains images | `bool` | `false` | no |
| <a name="input_image_tag_mutability"></a> [image\_tag\_mutability](#input\_image\_tag\_mutability) | The tag mutability setting for images. IMMUTABLE prevents tags from being overwritten, MUTABLE allows overwriting. | `string` | `"IMMUTABLE"` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | The ARN of the KMS key to use for encryption. Required when encryption\_type is KMS. Ignored for AES256. | `string` | `null` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Lifecycle policy rules | <pre>list(object({<br>    rule_priority    = number<br>    description      = string<br>    tag_status       = string<br>    tag_prefix_list  = optional(list(string), [])<br>    tag_pattern_list = optional(list(string), [])<br>    count_type       = string<br>    count_number     = number<br>    count_unit       = optional(string, "days")<br>    action_type      = string<br>  }))</pre> | `[]` | no |
| <a name="input_pull_through_cache_rules"></a> [pull\_through\_cache\_rules](#input\_pull\_through\_cache\_rules) | Pull through cache rules for upstream registries | <pre>map(object({<br>    ecr_repository_prefix = string<br>    upstream_registry_url = string<br>    credential_arn        = optional(string)<br>  }))</pre> | `{}` | no |
| <a name="input_registry_policy_json"></a> [registry\_policy\_json](#input\_registry\_policy\_json) | JSON policy document for registry-level permissions | `string` | `null` | no |
| <a name="input_registry_scan_type"></a> [registry\_scan\_type](#input\_registry\_scan\_type) | Scanning type to set for the registry (BASIC or ENHANCED) | `string` | `"ENHANCED"` | no |
| <a name="input_registry_scanning_rules"></a> [registry\_scanning\_rules](#input\_registry\_scanning\_rules) | Registry scanning rules | <pre>list(object({<br>    scan_frequency    = string<br>    repository_filter = string<br>    filter_type       = string<br>  }))</pre> | `[]` | no |
| <a name="input_replication_rules"></a> [replication\_rules](#input\_replication\_rules) | Replication rules for pushing images to other registries or regions. Each rule can replicate to multiple destinations. | <pre>list(object({<br>    destinations = list(object({<br>      region      = string<br>      registry_id = string<br>    }))<br>    repository_filters = optional(list(object({<br>      filter_type = string # PREFIX_MATCH is the only supported type<br>      filter      = string # Repository name prefix to match<br>    })), [])<br>  }))</pre> | `[]` | no |
| <a name="input_repository_name"></a> [repository\_name](#input\_repository\_name) | The name of the ECR repository | `string` | n/a | yes |
| <a name="input_repository_policy_statements"></a> [repository\_policy\_statements](#input\_repository\_policy\_statements) | Additional IAM policy statements for the repository policy. Allows fine-grained access control. | <pre>list(object({<br>    sid    = string<br>    effect = optional(string, "Allow") # Allow or Deny<br>    principals = optional(object({<br>      type        = optional(string, "AWS")<br>      identifiers = list(string)<br>    }), null)<br>    actions   = list(string)<br>    resources = optional(list(string), null) # Defaults to repository ARN<br>    conditions = optional(list(object({<br>      test     = string<br>      variable = string<br>      values   = list(string)<br>    })), [])<br>  }))</pre> | <pre>[<br>  {<br>    "actions": [<br>      "ecr:GetDownloadUrlForLayer",<br>      "ecr:BatchGetImage",<br>      "ecr:BatchCheckLayerAvailability",<br>      "ecr:PutImage",<br>      "ecr:InitiateLayerUpload",<br>      "ecr:UploadLayerPart",<br>      "ecr:CompleteLayerUpload",<br>      "ecr:DescribeRepositories",<br>      "ecr:GetRepositoryPolicy",<br>      "ecr:ListImages",<br>      "ecr:DeleteRepository",<br>      "ecr:BatchDeleteImage",<br>      "ecr:SetRepositoryPolicy",<br>      "ecr:DeleteRepositoryPolicy"<br>    ],<br>    "effect": "Allow",<br>    "principals": {<br>      "identifiers": [],<br>      "type": "AWS"<br>    },<br>    "sid": "AllowFullAccessToAccount"<br>  }<br>]</pre> | no |
| <a name="input_scan_on_push"></a> [scan\_on\_push](#input\_scan\_on\_push) | Indicates whether images are scanned for vulnerabilities after being pushed to the repository | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to the repository and all related resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_allowed_pull_principals"></a> [allowed\_pull\_principals](#output\_allowed\_pull\_principals) | AWS principals with read-only (pull) access to the repository |
| <a name="output_allowed_push_principals"></a> [allowed\_push\_principals](#output\_allowed\_push\_principals) | AWS principals with push/pull access to the repository |
| <a name="output_encryption_configuration"></a> [encryption\_configuration](#output\_encryption\_configuration) | The encryption configuration of the repository |
| <a name="output_image_scanning_configuration"></a> [image\_scanning\_configuration](#output\_image\_scanning\_configuration) | The image scanning configuration of the repository |
| <a name="output_image_tag_mutability"></a> [image\_tag\_mutability](#output\_image\_tag\_mutability) | The tag mutability setting for the repository |
| <a name="output_lifecycle_policy_created"></a> [lifecycle\_policy\_created](#output\_lifecycle\_policy\_created) | Whether a lifecycle policy was created |
| <a name="output_lifecycle_rules"></a> [lifecycle\_rules](#output\_lifecycle\_rules) | The lifecycle rules applied to the repository |
| <a name="output_log_group_arn"></a> [log\_group\_arn](#output\_log\_group\_arn) | CloudWatch log group ARN for ECR logs |
| <a name="output_log_group_name"></a> [log\_group\_name](#output\_log\_group\_name) | CloudWatch log group name for ECR logs |
| <a name="output_registry_id"></a> [registry\_id](#output\_registry\_id) | The AWS account ID (registry ID) where the repository was created |
| <a name="output_replication_configuration"></a> [replication\_configuration](#output\_replication\_configuration) | The replication configuration (if enabled) |
| <a name="output_replication_enabled"></a> [replication\_enabled](#output\_replication\_enabled) | Whether replication is enabled |
| <a name="output_repository_arn"></a> [repository\_arn](#output\_repository\_arn) | The full ARN of the repository |
| <a name="output_repository_name"></a> [repository\_name](#output\_repository\_name) | The name of the repository |
| <a name="output_repository_policy_statements"></a> [repository\_policy\_statements](#output\_repository\_policy\_statements) | The combined policy statements for the repository (custom + auto-generated) |
| <a name="output_repository_url"></a> [repository\_url](#output\_repository\_url) | The URL of the repository (format: ACCOUNT\_ID.dkr.ecr.REGION.amazonaws.com/REPOSITORY\_NAME) |
<!-- END_TF_DOCS -->