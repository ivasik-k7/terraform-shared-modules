# EFS Terraform Module

A Terraform module for provisioning AWS Elastic File System (EFS) with mount targets, security groups, access points, replication, and backup policies.

## What This Module Does

- Creates an EFS file system with configurable encryption, performance mode, and throughput settings
- Provisions mount targets across specified subnets for NFS access
- Optionally creates a dedicated security group with IPv4 **and IPv6** access rules
- Supports EFS access points for application-specific mounting
- Handles automatic backups via backup policies
- Supports file system replication to other regions or zones
- Manages lifecycle policies for automatic data tiering (Standard → IA → Archive)
- Supports both one-zone and multi-zone configurations
- Can attach a **TLS-enforcement file system policy** (`enforce_in_transit_encryption`)
- Optionally creates **CloudWatch alarms** (burst credit balance, percent IO limit)

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

| Name   | Type   | Description                 |
| ------ | ------ | --------------------------- |
| `name` | string | Name of the EFS file system |

> **Note:** `subnet_ids` and `security_group_ids` were previously required and
> are now **optional** (both default to `[]`). Existing callers are unaffected.
> Leave `subnet_ids` empty to create a file system with no mount targets (e.g. a
> replication destination). Provide mount-target security groups either via
> `security_group_ids` or by setting `create_security_group = true`.

### Networking

| Name                 | Type         | Default | Description                                                                       |
| -------------------- | ------------ | ------- | --------------------------------------------------------------------------------- |
| `subnet_ids`         | list(string) | `[]`    | Subnets to place mount targets in (one mount target per subnet)                   |
| `security_group_ids` | list(string) | `[]`    | Existing security groups to attach to mount targets (in addition to a created one) |

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
| `allowed_cidr_blocks`        | list(string) | `[]`    | IPv4 CIDR blocks allowed NFS access (port 2049)                         |
| `allowed_ipv6_cidr_blocks`   | list(string) | `[]`    | IPv6 CIDR blocks allowed NFS access (port 2049)                         |
| `allowed_security_group_ids` | list(string) | `[]`    | Security group IDs allowed NFS access                                   |

### In-Transit Encryption Policy

| Name                            | Type | Default | Description                                                                                          |
| ------------------------------- | ---- | ------- | ---------------------------------------------------------------------------------------------------- |
| `enforce_in_transit_encryption` | bool | `false` | Attach a file system policy denying any non-TLS access. Mutually exclusive with `file_system_policy`. |

### CloudWatch Alarms

| Name                                   | Type         | Default        | Description                                                                  |
| -------------------------------------- | ------------ | -------------- | ---------------------------------------------------------------------------- |
| `create_cloudwatch_alarms`             | bool         | `false`        | Create EFS CloudWatch alarms                                                 |
| `alarm_burst_credit_balance_threshold` | number       | `206158430208` | Alarm when BurstCreditBalance (bytes) drops below this (bursting mode only)  |
| `alarm_percent_io_limit_threshold`     | number       | `95`           | Alarm when PercentIOLimit exceeds this percent (generalPurpose mode only)    |
| `alarm_evaluation_periods`             | number       | `3`            | Evaluation periods for the alarms                                            |
| `alarm_period`                         | number       | `300`          | Period (seconds) for each alarm statistic                                    |
| `alarm_actions`                        | list(string) | `[]`           | ARNs notified on ALARM (e.g. SNS topics)                                     |
| `ok_actions`                           | list(string) | `[]`           | ARNs notified on OK                                                          |

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
| `file_system_id`                                       | Alias of `efs_id`                                       |
| `file_system_arn`                                      | Alias of `efs_arn`                                      |
| `file_system_dns_name`                                 | Alias of `efs_dns_name`                                 |
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
| `replication_configuration_destination_region`         | The region of the replica file system (if replicated)   |
| `file_system_policy`                                   | The effective file system policy JSON applied (or null) |
| `backup_policy_enabled`                                | Whether a backup policy is managed by this module       |
| `cloudwatch_alarm_names`                               | Names of the CloudWatch alarms created                  |

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

### Enforce In-Transit Encryption (TLS)

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]

  create_security_group = true
  vpc_id                = "vpc-12345"
  allowed_cidr_blocks   = ["10.0.0.0/16"]

  # Deny any mount/read/write that is not over TLS.
  enforce_in_transit_encryption = true
}
```

### Operational Alarms

```hcl
module "efs" {
  source = "./efs"

  name       = "my-app"
  subnet_ids = ["subnet-12345", "subnet-67890"]

  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
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

### Upgrade Notes

The security group rules were migrated from the legacy `aws_security_group_rule`
resource to the modern `aws_vpc_security_group_ingress_rule` /
`aws_vpc_security_group_egress_rule` resources (consistent with the rest of the
repo, and individually taggable). Because Terraform cannot `moved`-migrate
across resource *types*, the **first apply after upgrading recreates the EFS
ingress/egress rules** (the security group itself and the file system are
untouched). Each allowed CIDR/security group now produces its own rule. To
avoid any momentary gap in NFS reachability, apply during a maintenance window
or pre-create equivalent rules. Callers that pass their own `security_group_ids`
(i.e. `create_security_group = false`) are unaffected.

### Security Group Handling

When `create_security_group = true`:

- A security group is created and automatically attached to mount targets
- NFS traffic (port 2049) is allowed from specified CIDR blocks and security groups
- All outbound traffic is allowed
- If `security_group_ids` are also provided, they will be used in addition to the created security group

Without `create_security_group`:

- Any mount target needs at least one security group, so when `subnet_ids` is
  non-empty you must provide `security_group_ids` (or set `create_security_group = true`)
- Ensure your security groups allow inbound NFS traffic on port 2049
- IPv6 clients: add their ranges via `allowed_ipv6_cidr_blocks`

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
