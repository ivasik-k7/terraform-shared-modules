# EFS Terraform Module

A Terraform module for provisioning AWS Elastic File System (EFS) with mount targets, security groups, access points, replication, and backup policies.

## What This Module Does

- Creates an EFS file system with configurable encryption, performance mode, and throughput settings
- Provisions mount targets across specified subnets for NFS access
- Optionally creates a dedicated security group with configurable access rules
- Supports EFS access points for application-specific mounting
- Handles automatic backups via backup policies
- Supports file system replication to other regions or zones
- Manages lifecycle policies for automatic data tiering (Standard → IA → Archive)
- Supports both one-zone and multi-zone configurations

## Basic Usage

### Minimal Configuration

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]
  security_group_ids = [aws_security_group.app.id]
}
```

### With Auto-Created Security Group

```hcl
module "efs" {
  source = "./efs"

  name                      = "my-app"
  subnet_ids                = ["subnet-12345", "subnet-67890"]
  vpc_id                    = "vpc-12345"
  create_security_group     = true
  allowed_cidr_blocks       = ["10.0.0.0/8"]
  allowed_security_group_ids = [aws_security_group.app.id]

  tags = {
    Environment = "prod"
  }
}
```

### Advanced Configuration

```hcl
module "efs" {
  source = "./efs"

  name                      = "my-app"
  encrypted                 = true
  kms_key_id                = aws_kms_key.efs.arn
  performance_mode          = "generalPurpose"  # or "maxIO"
  throughput_mode           = "provisioned"
  provisioned_throughput_in_mibps = 100

  subnet_ids           = ["subnet-12345", "subnet-67890"]
  vpc_id               = "vpc-12345"
  create_security_group = true
  allowed_cidr_blocks  = ["10.0.0.0/8"]

  # Automatic backups
  enable_backup_policy = true

  # Lifecycle policies for cost optimization
  lifecycle_policy_transition_to_ia                   = "AFTER_30_DAYS"
  lifecycle_policy_transition_to_primary_storage_class = "AFTER_1_ACCESS"

  # Replication for disaster recovery
  replication_configuration = {
    region = "us-west-2"
  }

  # Application-specific access points
  access_points = {
    app_data = {
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/app"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0755"
        }
      }
    }
  }

  tags = {
    Environment = "prod"
    CostCenter  = "engineering"
  }
}
```

## Input Variables

### Required

| Name                 | Type         | Description                                           |
| -------------------- | ------------ | ----------------------------------------------------- |
| `name`               | string       | Name of the EFS file system                           |
| `subnet_ids`         | list(string) | List of subnet IDs for mount targets                  |
| `security_group_ids` | list(string) | List of security group IDs to attach to mount targets |

### Encryption

| Name         | Type   | Default | Description                                                        |
| ------------ | ------ | ------- | ------------------------------------------------------------------ |
| `encrypted`  | bool   | `true`  | Enable EFS encryption                                              |
| `kms_key_id` | string | `null`  | KMS key ARN for encryption (uses AWS managed key if not specified) |

### File System Configuration

| Name                              | Type   | Default            | Description                                                                       |
| --------------------------------- | ------ | ------------------ | --------------------------------------------------------------------------------- |
| `creation_token`                  | string | `null`             | Unique reference name for EFS creation (auto-generated from name if null)         |
| `performance_mode`                | string | `"generalPurpose"` | File system performance mode: `generalPurpose` or `maxIO`                         |
| `throughput_mode`                 | string | `"bursting"`       | Throughput mode: `bursting`, `provisioned`, or `elastic`                          |
| `provisioned_throughput_in_mibps` | number | `null`             | Throughput in MiB/s (required if throughput_mode is `provisioned`)                |
| `availability_zone_name`          | string | `null`             | Availability zone for one-zone file systems (creates multi-zone if not specified) |

### Lifecycle and Tiering

| Name                                                   | Type   | Default | Description                                                                                                            |
| ------------------------------------------------------ | ------ | ------- | ---------------------------------------------------------------------------------------------------------------------- |
| `lifecycle_policy_transition_to_ia`                    | string | `null`  | Transition to Infrequent Access: `AFTER_7_DAYS`, `AFTER_14_DAYS`, `AFTER_30_DAYS`, `AFTER_60_DAYS`, or `AFTER_90_DAYS` |
| `lifecycle_policy_transition_to_primary_storage_class` | string | `null`  | Transition from IA back to Standard: `AFTER_1_ACCESS`                                                                  |
| `lifecycle_policy_transition_to_archive`               | string | `null`  | Transition to Archive: `AFTER_1_DAY`, `AFTER_7_DAYS`, ..., `AFTER_365_DAYS`                                            |

### Mount Target Configuration

| Name                        | Type        | Default | Description                                                                |
| --------------------------- | ----------- | ------- | -------------------------------------------------------------------------- |
| `mount_target_ip_addresses` | map(string) | `{}`    | Map of subnet IDs to specific private IPs (auto-assigned if not specified) |

### Security Group

| Name                         | Type         | Default | Description                                                             |
| ---------------------------- | ------------ | ------- | ----------------------------------------------------------------------- |
| `create_security_group`      | bool         | `false` | Create a dedicated EFS security group                                   |
| `vpc_id`                     | string       | `null`  | VPC ID for security group (required if `create_security_group` is true) |
| `allowed_cidr_blocks`        | list(string) | `[]`    | CIDR blocks allowed NFS access (port 2049)                              |
| `allowed_security_group_ids` | list(string) | `[]`    | Security group IDs allowed NFS access                                   |

### Backup and Policies

| Name                                 | Type   | Default | Description                                                 |
| ------------------------------------ | ------ | ------- | ----------------------------------------------------------- |
| `enable_backup_policy`               | bool   | `true`  | Enable automatic EFS backups                                |
| `file_system_policy`                 | string | `null`  | JSON IAM policy document for the EFS file system            |
| `bypass_policy_lockout_safety_check` | bool   | `false` | Bypass safety check when updating policy (use with caution) |

### Access Points

| Name            | Type        | Default | Description                     |
| --------------- | ----------- | ------- | ------------------------------- |
| `access_points` | map(object) | `{}`    | Map of access point definitions |

Access point object structure:

```hcl
{
  posix_user = optional({
    uid            = number          # User ID
    gid            = number          # Group ID
    secondary_gids = optional(list)  # Additional group IDs
  })
  root_directory = optional({
    path = optional(string)          # Mount path within EFS
    creation_info = optional({
      owner_uid   = number           # Directory owner UID
      owner_gid   = number           # Directory owner GID
      permissions = string           # Unix permissions (e.g., "0755")
    })
  })
  tags = optional(map(string))       # Additional tags
}
```

### Replication

| Name                                      | Type   | Default | Description                                            |
| ----------------------------------------- | ------ | ------- | ------------------------------------------------------ |
| `replication_configuration`               | object | `null`  | Replication configuration for disaster recovery        |
| `enable_replication_overwrite_protection` | bool   | `false` | Prevent accidental deletion of replicated file systems |

Replication object structure:

```hcl
{
  region                 = optional(string)  # Destination region
  availability_zone_name = optional(string)  # Destination AZ (for one-zone replication)
  kms_key_id             = optional(string)  # KMS key for replica encryption
  file_system_id         = optional(string)  # Existing file system ID to replicate to
}
```

### Common

| Name   | Type        | Default | Description                   |
| ------ | ----------- | ------- | ----------------------------- |
| `tags` | map(string) | `{}`    | Tags applied to all resources |

## Outputs

| Name                                                   | Description                                             |
| ------------------------------------------------------ | ------------------------------------------------------- |
| `efs_id`                                               | The ID of the EFS file system                           |
| `efs_arn`                                              | The ARN of the EFS file system                          |
| `efs_dns_name`                                         | The DNS name for mounting via NFS                       |
| `efs_size_in_bytes`                                    | Current metered size of the file system                 |
| `efs_number_of_mount_targets`                          | Number of active mount targets                          |
| `mount_target_ids`                                     | Map of subnet IDs to mount target IDs                   |
| `mount_target_network_interface_ids`                   | Map of subnet IDs to ENI IDs                            |
| `mount_target_dns_names`                               | Map of subnet IDs to mount target DNS names             |
| `mount_target_ip_addresses`                            | Map of subnet IDs to mount target private IPs           |
| `access_point_ids`                                     | Map of access point names to IDs                        |
| `access_point_arns`                                    | Map of access point names to ARNs                       |
| `access_point_file_system_arns`                        | Map of access point names to file system ARNs           |
| `security_group_id`                                    | The ID of the auto-created security group (if created)  |
| `security_group_arn`                                   | The ARN of the auto-created security group (if created) |
| `replication_configuration_destination_file_system_id` | The file system ID of the replica (if replicated)       |

## Common Patterns

### Cost Optimization with Tiering

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]
  security_group_ids = [aws_security_group.app.id]

  # Transition unused data to cheaper tiers
  lifecycle_policy_transition_to_ia                   = "AFTER_30_DAYS"
  lifecycle_policy_transition_to_primary_storage_class = "AFTER_1_ACCESS"
  lifecycle_policy_transition_to_archive               = "AFTER_90_DAYS"
}
```

### Multi-Zone Resilience with Backups

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = [
    "subnet-az1a",
    "subnet-az1b",
    "subnet-az1c"
  ]
  security_group_ids = [aws_security_group.app.id]
  enable_backup_policy = true
}
```

### One-Zone Filesystem (Single AZ Deployment)

```hcl
module "efs" {
  source = "./efs"

  name                    = "my-app"
  availability_zone_name  = "us-east-1a"
  subnet_ids              = ["subnet-12345"]
  security_group_ids      = [aws_security_group.app.id]
}
```

### Cross-Region Replication for DR

```hcl
module "efs_primary" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]
  security_group_ids = [aws_security_group.app.id]

  replication_configuration = {
    region = "us-west-2"
  }
}
```

### Application-Specific Access Points

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]
  security_group_ids = [aws_security_group.app.id]

  access_points = {
    app = {
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/app"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0755"
        }
      }
    }
    logs = {
      posix_user = {
        uid = 1000
        gid = 1000
      }
      root_directory = {
        path = "/logs"
        creation_info = {
          owner_uid   = 1000
          owner_gid   = 1000
          permissions = "0755"
        }
      }
    }
  }
}
```

## Important Notes

### Security Group Handling

When `create_security_group = true`:

- A security group is created and automatically attached to mount targets
- NFS traffic (port 2049) is allowed from specified CIDR blocks and security groups
- All outbound traffic is allowed
- If `security_group_ids` are also provided, they will be used in addition to the created security group

Without `create_security_group`:

- You must provide `security_group_ids` - mount targets require at least one security group
- Ensure your security groups allow inbound NFS traffic on port 2049

### Performance Considerations

- **generalPurpose mode**: Default, recommended for most workloads
- **maxIO mode**: For applications requiring higher levels of parallelism
- **bursting throughput**: Scales automatically, default option
- **provisioned throughput**: Predictable performance, recommended for consistent workloads
- **elastic throughput**: Automatic scaling with provisioning, latest option

### Lifecycle Policies

Tiering transitions are independent and can be combined:

- Enable one-way tiering with IA and Archive for cold storage cost savings
- Or enable automatic return to Standard with `AFTER_1_ACCESS` to maintain frequent access at higher tier

### Mount Target Placement

- Create at least one mount target per subnet where EFS access is needed
- All mount targets automatically join the same security group(s)
- Mount targets handle load balancing automatically

## Troubleshooting

### "Must provide at least one security group" Error

Occurs when updating mount targets. Solutions:

1. Use `create_security_group = true` to auto-create a security group, or
2. Ensure `security_group_ids` is provided and not empty, or
3. Both can be used together - the module will attach both

### Access Denied Errors

- Verify security group allows inbound port 2049 (NFS)
- Check source CIDR blocks or security groups match the client
- Verify network ACLs allow NFS traffic

### Replication Takes Time

- Initial replication can take hours for large file systems
- Replica is read-only until replication completes
- Check AWS console for replication status

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
| [aws_efs_access_point.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_access_point) | resource |
| [aws_efs_backup_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_backup_policy) | resource |
| [aws_efs_file_system.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system) | resource |
| [aws_efs_file_system_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_file_system_policy) | resource |
| [aws_efs_mount_target.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_mount_target) | resource |
| [aws_efs_replication_configuration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/efs_replication_configuration) | resource |
| [aws_security_group.efs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.efs_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.efs_ingress_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.efs_ingress_sg](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_points"></a> [access\_points](#input\_access\_points) | Map of access point definitions to create | <pre>map(object({<br>    posix_user = optional(object({<br>      gid            = number<br>      uid            = number<br>      secondary_gids = optional(list(number))<br>    }))<br>    root_directory = optional(object({<br>      path = optional(string)<br>      creation_info = optional(object({<br>        owner_gid   = number<br>        owner_uid   = number<br>        permissions = string<br>      }))<br>    }))<br>    tags = optional(map(string))<br>  }))</pre> | `{}` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | List of CIDR blocks allowed to access EFS | `list(string)` | `[]` | no |
| <a name="input_allowed_security_group_ids"></a> [allowed\_security\_group\_ids](#input\_allowed\_security\_group\_ids) | List of security group IDs allowed to access EFS | `list(string)` | `[]` | no |
| <a name="input_availability_zone_name"></a> [availability\_zone\_name](#input\_availability\_zone\_name) | The AWS Availability Zone in which to create the file system. Used to create a one-zone file system | `string` | `null` | no |
| <a name="input_bypass_policy_lockout_safety_check"></a> [bypass\_policy\_lockout\_safety\_check](#input\_bypass\_policy\_lockout\_safety\_check) | Whether to bypass the policy lockout safety check. Set to true only if you intend to prevent the principal making the API call from making future PutFileSystemPolicy calls | `bool` | `false` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Whether to create a security group for EFS | `bool` | `false` | no |
| <a name="input_creation_token"></a> [creation\_token](#input\_creation\_token) | A unique name used as reference when creating the EFS. If not provided, uses the name variable | `string` | `null` | no |
| <a name="input_enable_backup_policy"></a> [enable\_backup\_policy](#input\_enable\_backup\_policy) | Whether to enable automatic backups | `bool` | `true` | no |
| <a name="input_enable_replication_overwrite_protection"></a> [enable\_replication\_overwrite\_protection](#input\_enable\_replication\_overwrite\_protection) | Enable replication overwrite protection to prevent accidental deletion of replicated file systems | `bool` | `false` | no |
| <a name="input_encrypted"></a> [encrypted](#input\_encrypted) | Whether to encrypt the file system | `bool` | `true` | no |
| <a name="input_file_system_policy"></a> [file\_system\_policy](#input\_file\_system\_policy) | JSON formatted file system policy for the EFS file system | `string` | `null` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | ARN of the KMS key to use for encryption. If not specified, uses the default AWS EFS KMS key | `string` | `null` | no |
| <a name="input_lifecycle_policy_transition_to_archive"></a> [lifecycle\_policy\_transition\_to\_archive](#input\_lifecycle\_policy\_transition\_to\_archive) | Indicates how long it takes to transition files to Archive storage class. Valid values: AFTER\_1\_DAY, AFTER\_7\_DAYS, AFTER\_14\_DAYS, AFTER\_30\_DAYS, AFTER\_60\_DAYS, AFTER\_90\_DAYS, AFTER\_180\_DAYS, AFTER\_270\_DAYS, or AFTER\_365\_DAYS | `string` | `null` | no |
| <a name="input_lifecycle_policy_transition_to_ia"></a> [lifecycle\_policy\_transition\_to\_ia](#input\_lifecycle\_policy\_transition\_to\_ia) | Indicates how long it takes to transition files to the IA storage class. Valid values: AFTER\_7\_DAYS, AFTER\_14\_DAYS, AFTER\_30\_DAYS, AFTER\_60\_DAYS, or AFTER\_90\_DAYS | `string` | `null` | no |
| <a name="input_lifecycle_policy_transition_to_primary_storage_class"></a> [lifecycle\_policy\_transition\_to\_primary\_storage\_class](#input\_lifecycle\_policy\_transition\_to\_primary\_storage\_class) | Describes the policy used to transition a file from IA storage to primary storage. Valid values: AFTER\_1\_ACCESS | `string` | `null` | no |
| <a name="input_mount_target_ip_addresses"></a> [mount\_target\_ip\_addresses](#input\_mount\_target\_ip\_addresses) | Map of subnet IDs to specific IP addresses for mount targets. If not specified, an available IP is automatically assigned | `map(string)` | `{}` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the EFS file system | `string` | n/a | yes |
| <a name="input_performance_mode"></a> [performance\_mode](#input\_performance\_mode) | The file system performance mode. Can be either generalPurpose or maxIO | `string` | `"generalPurpose"` | no |
| <a name="input_provisioned_throughput_in_mibps"></a> [provisioned\_throughput\_in\_mibps](#input\_provisioned\_throughput\_in\_mibps) | The throughput, measured in MiB/s, to provision for the file system. Only applicable with throughput\_mode set to provisioned | `number` | `null` | no |
| <a name="input_replication_configuration"></a> [replication\_configuration](#input\_replication\_configuration) | Replication configuration for the EFS file system. Specify region or availability\_zone\_name (for One Zone file systems) | <pre>object({<br>    region                 = optional(string)<br>    availability_zone_name = optional(string)<br>    kms_key_id             = optional(string)<br>    file_system_id         = optional(string)<br>  })</pre> | `null` | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | List of security group IDs to attach to mount targets | `list(string)` | n/a | yes |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | List of subnet IDs for mount targets | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all resources | `map(string)` | `{}` | no |
| <a name="input_throughput_mode"></a> [throughput\_mode](#input\_throughput\_mode) | Throughput mode for the file system. Valid values: bursting, provisioned, or elastic | `string` | `"bursting"` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the security group will be created. Required if create\_security\_group is true | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_access_point_arns"></a> [access\_point\_arns](#output\_access\_point\_arns) | Map of access point names to their ARNs |
| <a name="output_access_point_file_system_arns"></a> [access\_point\_file\_system\_arns](#output\_access\_point\_file\_system\_arns) | Map of access point names to their file system ARNs |
| <a name="output_access_point_ids"></a> [access\_point\_ids](#output\_access\_point\_ids) | Map of access point names to their IDs |
| <a name="output_efs_arn"></a> [efs\_arn](#output\_efs\_arn) | The ARN of the EFS file system |
| <a name="output_efs_dns_name"></a> [efs\_dns\_name](#output\_efs\_dns\_name) | The DNS name for the EFS file system |
| <a name="output_efs_id"></a> [efs\_id](#output\_efs\_id) | The ID of the EFS file system |
| <a name="output_efs_number_of_mount_targets"></a> [efs\_number\_of\_mount\_targets](#output\_efs\_number\_of\_mount\_targets) | The current number of mount targets that the file system has |
| <a name="output_efs_size_in_bytes"></a> [efs\_size\_in\_bytes](#output\_efs\_size\_in\_bytes) | The latest known metered size (in bytes) of data stored in the file system |
| <a name="output_mount_target_dns_names"></a> [mount\_target\_dns\_names](#output\_mount\_target\_dns\_names) | Map of subnet IDs to mount target DNS names |
| <a name="output_mount_target_ids"></a> [mount\_target\_ids](#output\_mount\_target\_ids) | Map of subnet IDs to mount target IDs |
| <a name="output_mount_target_ip_addresses"></a> [mount\_target\_ip\_addresses](#output\_mount\_target\_ip\_addresses) | Map of subnet IDs to mount target IP addresses |
| <a name="output_mount_target_network_interface_ids"></a> [mount\_target\_network\_interface\_ids](#output\_mount\_target\_network\_interface\_ids) | Map of subnet IDs to mount target network interface IDs |
| <a name="output_replication_configuration_destination_file_system_id"></a> [replication\_configuration\_destination\_file\_system\_id](#output\_replication\_configuration\_destination\_file\_system\_id) | The file system ID of the replica |
| <a name="output_security_group_arn"></a> [security\_group\_arn](#output\_security\_group\_arn) | The ARN of the security group (if created) |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The ID of the security group (if created) |
<!-- END_TF_DOCS -->