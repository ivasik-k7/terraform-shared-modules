# Aurora

A focused, production-ready Terraform module for **Amazon Aurora** (PostgreSQL and
MySQL compatible). It manages an Aurora DB cluster, its instances, networking
(DB subnet group + security group), parameter groups, observability, and the
higher-order Aurora features — and deliberately nothing else. The surface area
stays Aurora-shaped so the module is easy to reason about and safe to upgrade.

## Features

- **Provisioned and Serverless v2** clusters (`engine_mode`, `serverless_scaling_configuration`).
- **PostgreSQL and MySQL** compatibility with sensible engine-aware defaults (port, parameter-group family).
- **Flexible instance topology** — any number of writer/reader instances via the `instances` map, with per-instance class, promotion tier, Performance Insights, and CA certificate.
- **Networking** — creates a DB subnet group and a least-privilege security group, or **bring your own** of either.
- **Custom cluster endpoints** — dedicated `READER`/`ANY` endpoints (e.g. an analytics reader pool).
- **Credentials** — supply a master password, or let **RDS manage it in Secrets Manager** (`manage_master_user_password`).
- **Parameter groups** — cluster- and instance-level, created by the module or referenced externally.
- **Backups & restore** — automated backups, restore from snapshot, and named final snapshots.
- **Security** — encryption at rest (KMS), IAM database authentication, IPv4 + IPv6 ingress, deletion protection.
- **Observability** — Enhanced Monitoring (created or BYO role), Performance Insights, CloudWatch log exports, and opinionated CloudWatch alarms.
- **Aurora extras** — Global Database, IAM role associations (S3 import/export), I/O-Optimized storage, local write forwarding, and Database Activity Streams.

## Resources created

Depending on the inputs, the module manages: `aws_rds_cluster`,
`aws_rds_cluster_instance` (per instance), `aws_db_subnet_group`,
`aws_rds_cluster_parameter_group`, `aws_db_parameter_group`,
`aws_security_group` + ingress/egress rules, `aws_rds_cluster_endpoint` (custom
endpoints), `aws_rds_cluster_role_association`, `aws_rds_cluster_activity_stream`,
`aws_rds_global_cluster`, `aws_iam_role` (+ attachment) for Enhanced Monitoring,
`aws_cloudwatch_metric_alarm` (×4), and `aws_cloudwatch_log_group` (per exported log).

## Usage

### Minimal PostgreSQL cluster

```hcl
module "aurora" {
  source = "../../modules/aurora"

  cluster_identifier = "app-postgres"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]

  master_username = "app_admin"
  master_password = var.db_password # mark sensitive in the caller

  instances = {
    writer = { instance_class = "db.r6g.large", promotion_tier = 0 }
  }
}
```

### Production HA cluster with managed credentials and observability

```hcl
module "aurora" {
  source = "../../modules/aurora"

  cluster_identifier = "payments-prod"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  storage_type       = "aurora-iopt1" # I/O-Optimized

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.database_subnet_ids

  # Let RDS create & rotate the master secret in Secrets Manager
  manage_master_user_password   = true
  master_user_secret_kms_key_id = module.kms.key_arn

  storage_encrypted = true
  kms_key_id        = module.kms.key_arn

  instances = {
    writer  = { instance_class = "db.r6g.2xlarge", promotion_tier = 0 }
    reader1 = { instance_class = "db.r6g.2xlarge", promotion_tier = 1 }
    reader2 = { instance_class = "db.r6g.2xlarge", promotion_tier = 2 }
  }

  # Access control
  allowed_security_groups = [module.app.security_group_id]

  # Observability
  monitoring_interval             = 60
  performance_insights_enabled    = true
  performance_insights_kms_key_id = module.kms.key_arn
  enabled_cloudwatch_logs_exports = ["postgresql"]
  create_alarms                   = true

  deletion_protection = true

  tags = {
    Environment = "prod"
    CostCenter  = "payments"
  }
}
```

### Aurora Serverless v2

Serverless v2 runs on a **provisioned** cluster (leave `engine_mode` at its
default) using `db.serverless` instance classes plus a scaling configuration:

```hcl
module "aurora_serverless" {
  source = "../../modules/aurora"

  cluster_identifier = "reporting"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"

  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.database_subnet_ids

  serverless_scaling_configuration = {
    min_capacity = 0.5
    max_capacity = 16
  }

  instances = {
    writer = { instance_class = "db.serverless", promotion_tier = 0 }
  }
}
```

### Reuse an existing DB subnet group and security group

```hcl
module "aurora" {
  source = "../../modules/aurora"

  cluster_identifier = "shared-db"
  engine             = "aurora-mysql"
  engine_version     = "8.0"

  # Don't create networking — attach to existing infra
  create_db_subnet_group = false
  db_subnet_group_name   = "platform-db-subnets"

  create_security_group  = false
  vpc_security_group_ids = ["sg-0123456789abcdef0"]

  master_password = var.db_password
}
```

### Custom reader endpoint + S3 import role

```hcl
module "aurora" {
  source = "../../modules/aurora"

  cluster_identifier = "analytics"
  engine             = "aurora-postgresql"
  engine_version     = "15.4"
  vpc_id             = module.network.vpc_id
  subnet_ids         = module.network.database_subnet_ids
  master_password    = var.db_password

  instances = {
    writer = { instance_class = "db.r6g.large", promotion_tier = 0 }
    bi     = { instance_class = "db.r6g.xlarge", promotion_tier = 5 }
  }

  # A dedicated endpoint that only routes to the BI reader
  cluster_endpoints = {
    bi = { type = "READER", static_members = ["analytics-bi"] }
  }

  # Allow the cluster to COPY from S3
  iam_role_associations = {
    s3import = {
      role_arn     = aws_iam_role.aurora_s3.arn
      feature_name = "s3Import"
    }
  }
}
```

### Global Database (primary region)

```hcl
module "aurora_primary" {
  source = "../../modules/aurora"

  cluster_identifier        = "global-primary"
  engine                    = "aurora-postgresql"
  engine_version            = "15.4"
  vpc_id                    = module.network.vpc_id
  subnet_ids                = module.network.database_subnet_ids
  master_password           = var.db_password

  enable_global_cluster     = true
  global_cluster_identifier = "my-global-db"
  is_primary_region         = true
}
```

## Backward compatibility & upgrade notes

This module preserves its existing input contract — no previously required
variable was removed or renamed, and defaults are unchanged. Enrichments are
additive and opt-in:

- **DB subnet group is now conditional.** A `moved` block migrates the existing
  `aws_db_subnet_group.main` to `aws_db_subnet_group.main[0]` automatically, so
  upgrading callers see **no replacement** on the next plan.
- **`vpc_id` and `subnet_ids` are now optional**, validated only when the module
  actually needs them (`create_security_group` / `create_db_subnet_group`).
  Existing callers that pass them keep working.
- **`storage_type` validation was relaxed** to accept `aurora`, `aurora-iopt1`,
  and the previously allowed `gp3`.
- **Enhanced Monitoring** now accepts a pre-existing `monitoring_role_arn`;
  behaviour is unchanged when it is left `null`.

Two corrections were also made that may affect callers:

- **`backup_encryption_key_id` was removed.** It was never wired to any
  resource — Aurora backups are encrypted with the cluster's `kms_key_id`.
  Remove it from any call that still sets it.
- **`enable_http_endpoint` no longer requires `engine_mode = "serverless"`.**
  The RDS Data API now works on provisioned and Serverless v2 clusters, so the
  module defers engine/region eligibility to AWS.
- **`serverless_scaling_configuration.auto_pause` was removed.** Serverless v2
  has no such argument — auto-pause is expressed by `min_capacity = 0` plus
  `seconds_until_auto_pause`. Drop `auto_pause` from any call that set it.

## Security notes

- Storage encryption is **on by default** (`storage_encrypted = true`); supply
  `kms_key_id` to use a customer-managed key.
- Prefer `manage_master_user_password = true` so the credential never lives in
  Terraform state; otherwise mark `master_password` as sensitive in the caller.
- `deletion_protection` defaults to `true`. The module also writes a final
  snapshot on destroy unless `skip_final_snapshot = true`.
- The created security group is least-privilege: ingress only from
  `allowed_cidr_blocks` / `allowed_ipv6_cidr_blocks` / `allowed_security_groups`
  on the database port.

## Testing

Native `terraform test` suites live in [`tests/`](./tests) and run fully offline
(mocked AWS provider — no account or credentials needed):

- `tests/aurora.tftest.hcl` — plan-only happy paths and every input validation.
- `tests/apply.tftest.hcl` — full-stack apply against a mocked provider.

```bash
cd modules/aurora
terraform init -backend=false
terraform test
```

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
| [aws_cloudwatch_log_group.aurora_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_metric_alarm.cpu_utilization](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.database_connections](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.database_free_storage_space](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.database_replica_lag](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_db_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_parameter_group) | resource |
| [aws_db_subnet_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/db_subnet_group) | resource |
| [aws_iam_role.enhanced_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.enhanced_monitoring](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_rds_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster) | resource |
| [aws_rds_cluster_activity_stream.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_activity_stream) | resource |
| [aws_rds_cluster_endpoint.custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_endpoint) | resource |
| [aws_rds_cluster_instance.instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_parameter_group) | resource |
| [aws_rds_cluster_role_association.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_role_association) | resource |
| [aws_rds_global_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_security_group.aurora](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.allow_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_ipv6_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_activity_stream_audit_fields_included"></a> [activity\_stream\_audit\_fields\_included](#input\_activity_stream_audit_fields_included) | Whether engine-native audit fields are included in the activity stream | `bool` | `false` | no |
| <a name="input_activity_stream_kms_key_id"></a> [activity\_stream\_kms\_key\_id](#input\_activity_stream_kms_key_id) | KMS key ID/ARN used to encrypt the activity stream. Required when enable_activity_stream is true. | `string` | `null` | no |
| <a name="input_activity_stream_mode"></a> [activity\_stream\_mode](#input\_activity_stream_mode) | Activity stream mode: 'async' (lower latency, best effort) or 'sync' (guaranteed delivery) | `string` | `"async"` | no |
| <a name="input_alarm_connections_threshold"></a> [alarm\_connections\_threshold](#input\_alarm_connections_threshold) | Database connections threshold for CloudWatch alarm | `number` | `80` | no |
| <a name="input_alarm_cpu_threshold_percent"></a> [alarm\_cpu\_threshold\_percent](#input\_alarm_cpu_threshold_percent) | CPU utilization threshold for CloudWatch alarm (percent) | `number` | `80` | no |
| <a name="input_alarm_free_storage_space_bytes"></a> [alarm\_free\_storage\_space\_bytes](#input\_alarm_free_storage_space_bytes) | Free storage space threshold in bytes for CloudWatch alarm (default: 1 GB) | `number` | `1073741824` | no |
| <a name="input_alarm_replica_lag_milliseconds"></a> [alarm\_replica\_lag\_milliseconds](#input\_alarm_replica_lag_milliseconds) | Replica lag threshold in milliseconds for CloudWatch alarm (default: 1000ms) | `number` | `1000` | no |
| <a name="input_allow_major_version_upgrade"></a> [allow\_major\_version\_upgrade](#input\_allow_major_version_upgrade) | Allow major engine version upgrades when changing engine_version | `bool` | `false` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed_cidr_blocks) | IPv4 CIDR blocks allowed to access Aurora | `list(string)` | `[]` | no |
| <a name="input_allowed_ipv6_cidr_blocks"></a> [allowed\_ipv6\_cidr\_blocks](#input\_allowed_ipv6_cidr_blocks) | IPv6 CIDR blocks allowed to access Aurora | `list(string)` | `[]` | no |
| <a name="input_allowed_security_groups"></a> [allowed\_security\_groups](#input\_allowed_security_groups) | Security group IDs allowed to access Aurora | `list(string)` | `[]` | no |
| <a name="input_apply_immediately"></a> [apply\_immediately](#input\_apply_immediately) | Apply changes immediately instead of during the next maintenance window | `bool` | `false` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto_minor_version_upgrade) | Indicates that minor engine upgrades will be applied automatically | `bool` | `true` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability_zones) | List of AZs for Aurora instances. If not specified, uses subnets' AZs | `list(string)` | `null` | no |
| <a name="input_backtrack_window"></a> [backtrack\_window](#input\_backtrack_window) | Target backtrack window in seconds for Aurora MySQL. Only available for aurora-mysql | `number` | `null` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup_retention_period) | The days to retain backups for | `number` | `7` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch_log_retention_days) | CloudWatch log retention period in days | `number` | `7` | no |
| <a name="input_cluster_endpoints"></a> [cluster\_endpoints](#input\_cluster_endpoints) | Map of additional custom Aurora cluster endpoints (e.g. dedicated analytics readers). Key becomes the endpoint identifier suffix. Use either static_members or excluded_members, not both. Members are full instance identifiers (e.g. '<cluster_identifier>-<instance_key>'). | <pre>map(object({<br>&nbsp;&nbsp;&nbsp;&nbsp;type&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = string<br>&nbsp;&nbsp;&nbsp;&nbsp;static_members&nbsp;&nbsp; = optional(list(string), [])<br>&nbsp;&nbsp;&nbsp;&nbsp;excluded_members = optional(list(string), [])<br>&nbsp;&nbsp;}))</pre> | `{}` | no |
| <a name="input_cluster_identifier"></a> [cluster\_identifier](#input\_cluster_identifier) | The cluster identifier for Aurora cluster (up to 63 chars) | `string` | n/a | yes |
| <a name="input_cluster_parameter_group_family"></a> [cluster\_parameter\_group\_family](#input\_cluster_parameter_group_family) | The family of the cluster parameter group | `string` | `null` | no |
| <a name="input_cluster_parameter_group_name"></a> [cluster\_parameter\_group\_name](#input\_cluster_parameter_group_name) | Name of the cluster parameter group to use | `string` | `null` | no |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster_parameters) | A list of cluster parameters to apply | <pre>list(object({<br>&nbsp;&nbsp;&nbsp;&nbsp;name&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = string<br>&nbsp;&nbsp;&nbsp;&nbsp;value&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= string<br>&nbsp;&nbsp;&nbsp;&nbsp;apply_method = optional(string, "immediate")<br>&nbsp;&nbsp;}))</pre> | `[]` | no |
| <a name="input_cluster_tags"></a> [cluster\_tags](#input\_cluster_tags) | Additional tags for the Aurora cluster | `map(string)` | `{}` | no |
| <a name="input_copy_tags_to_snapshot"></a> [copy\_tags\_to\_snapshot](#input\_copy_tags_to_snapshot) | Copy all cluster tags to snapshots | `bool` | `true` | no |
| <a name="input_create_alarms"></a> [create\_alarms](#input\_create_alarms) | Whether to create CloudWatch alarms | `bool` | `true` | no |
| <a name="input_create_cluster_parameter_group"></a> [create\_cluster\_parameter\_group](#input\_create_cluster_parameter_group) | Whether to create a cluster parameter group | `bool` | `true` | no |
| <a name="input_create_db_parameter_group"></a> [create\_db\_parameter\_group](#input\_create_db_parameter_group) | Whether to create instance parameter group | `bool` | `true` | no |
| <a name="input_create_db_subnet_group"></a> [create\_db\_subnet\_group](#input\_create_db_subnet_group) | Whether to create a DB subnet group. Set to false to attach the cluster to a pre-existing subnet group named by db_subnet_group_name. | `bool` | `true` | no |
| <a name="input_create_monitoring_role"></a> [create\_monitoring\_role](#input\_create_monitoring_role) | Create IAM role for enhanced monitoring. Ignored when monitoring_role_arn is set. | `bool` | `true` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create_security_group) | Whether to create security group for Aurora | `bool` | `true` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database_name) | The name of the database to create when the DB cluster is created | `string` | `null` | no |
| <a name="input_db_parameter_group_family"></a> [db\_parameter\_group\_family](#input\_db_parameter_group_family) | The family of the DB parameter group | `string` | `null` | no |
| <a name="input_db_parameter_group_name"></a> [db\_parameter\_group\_name](#input\_db_parameter_group_name) | Name of the DB parameter group to use | `string` | `null` | no |
| <a name="input_db_parameters"></a> [db\_parameters](#input\_db_parameters) | A list of DB parameters to apply | <pre>list(object({<br>&nbsp;&nbsp;&nbsp;&nbsp;name&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = string<br>&nbsp;&nbsp;&nbsp;&nbsp;value&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= string<br>&nbsp;&nbsp;&nbsp;&nbsp;apply_method = optional(string, "pending-reboot")<br>&nbsp;&nbsp;}))</pre> | `[]` | no |
| <a name="input_db_subnet_group_description"></a> [db\_subnet\_group\_description](#input\_db_subnet_group_description) | Description for the created DB subnet group | `string` | `null` | no |
| <a name="input_db_subnet_group_name"></a> [db\_subnet\_group\_name](#input\_db_subnet_group_name) | Name of the DB subnet group. When create_db_subnet_group is true this overrides the generated name; when false it must reference an existing subnet group. | `string` | `null` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion_protection) | If the DB cluster should have deletion protection enabled | `bool` | `true` | no |
| <a name="input_enable_activity_stream"></a> [enable\_activity\_stream](#input\_enable_activity_stream) | Enable a Database Activity Stream for the cluster (provisioned Aurora only) | `bool` | `false` | no |
| <a name="input_enable_automated_backup"></a> [enable\_automated\_backup](#input\_enable_automated_backup) | Enable or disable automated backups | `bool` | `true` | no |
| <a name="input_enable_global_cluster"></a> [enable\_global\_cluster](#input\_enable_global_cluster) | Whether to create a global Aurora database cluster | `bool` | `false` | no |
| <a name="input_enable_http_endpoint"></a> [enable\_http\_endpoint](#input\_enable_http_endpoint) | Enable the RDS Data API (HTTP endpoint). Supported on Aurora Serverless v1 (engine_mode 'serverless') and, via the newer RDS Data API, on Serverless v2 and provisioned Aurora. Engine/version/region availability is enforced by AWS. | `bool` | `false` | no |
| <a name="input_enable_local_write_forwarding"></a> [enable\_local\_write\_forwarding](#input\_enable_local_write_forwarding) | Enable local write forwarding so reader instances forward writes to the writer (Aurora MySQL and PostgreSQL) | `bool` | `false` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled_cloudwatch_logs_exports) | List of log types to export to CloudWatch | `list(string)` | `[]` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | The Aurora database engine to use | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_mode"></a> [engine\_mode](#input\_engine_mode) | The database engine mode. For Aurora: 'provisioned' or 'serverless' | `string` | `"provisioned"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine_version) | The engine version to use | `string` | n/a | yes |
| <a name="input_final_snapshot_identifier"></a> [final\_snapshot\_identifier](#input\_final_snapshot_identifier) | Name of the final snapshot taken on deletion. Defaults to '<cluster_identifier>-final-snapshot' when skip_final_snapshot is false. | `string` | `null` | no |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global_cluster_identifier) | The global cluster identifier for Aurora Global Database. Required when enable_global_cluster = true | `string` | `null` | no |
| <a name="input_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#input\_iam_database_authentication_enabled) | Specifies whether IAM Database authentication is enabled | `bool` | `false` | no |
| <a name="input_iam_role_associations"></a> [iam\_role\_associations](#input\_iam_role_associations) | Map of IAM roles to associate with the cluster for Aurora features such as S3 import/export. Key is a free-form label; feature_name is the Aurora feature (e.g. 's3Import', 's3Export'). | <pre>map(object({<br>&nbsp;&nbsp;&nbsp;&nbsp;role_arn&nbsp;&nbsp;&nbsp;&nbsp; = string<br>&nbsp;&nbsp;&nbsp;&nbsp;feature_name = string<br>&nbsp;&nbsp;}))</pre> | `{}` | no |
| <a name="input_instance_tags"></a> [instance\_tags](#input\_instance_tags) | Additional tags for Aurora instances | `map(string)` | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of Aurora instances to create. Key is instance identifier | <pre>map(object({<br>&nbsp;&nbsp;&nbsp;&nbsp;instance_class&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= string<br>&nbsp;&nbsp;&nbsp;&nbsp;promotion_tier&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= optional(number, 1)<br>&nbsp;&nbsp;&nbsp;&nbsp;publicly_accessible&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = optional(bool, false)<br>&nbsp;&nbsp;&nbsp;&nbsp;performance_insights_enabled&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= optional(bool, false)<br>&nbsp;&nbsp;&nbsp;&nbsp;performance_insights_retention_period = optional(number, 7)<br>&nbsp;&nbsp;&nbsp;&nbsp;ca_cert_identifier&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= optional(string)<br>&nbsp;&nbsp;&nbsp;&nbsp;tags&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= optional(map(string), {})<br>&nbsp;&nbsp;}))</pre> | <pre>{<br>&nbsp;&nbsp;&nbsp;&nbsp;"writer" = {<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;instance_class&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= "db.t3.medium"<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;promotion_tier&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;= 0<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;publicly_accessible = false<br>&nbsp;&nbsp;&nbsp;&nbsp;}<br>&nbsp;&nbsp;}</pre> | no |
| <a name="input_iops"></a> [iops](#input\_iops) | The amount of provisioned IOPS for Aurora PostgreSQL with gp3 storage | `number` | `null` | no |
| <a name="input_is_primary_region"></a> [is\_primary\_region](#input\_is_primary_region) | Whether this is the primary region for the global cluster | `bool` | `true` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms_key_id) | The ARN for the KMS encryption key | `string` | `null` | no |
| <a name="input_manage_master_user_password"></a> [manage\_master\_user\_password](#input\_manage_master_user_password) | Let RDS generate and manage the master user password in AWS Secrets Manager. Mutually exclusive with master_password. | `bool` | `false` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master_password) | Password for the master DB user | `string` | `null` | no |
| <a name="input_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#input\_master_user_secret_kms_key_id) | KMS key ID/ARN to encrypt the RDS-managed master user secret. Defaults to the AWS-managed aws/secretsmanager key when null. | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master_username) | Username for the master DB user | `string` | `"admin"` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring_interval) | The interval, in seconds, between points when Enhanced Monitoring metrics are collected | `number` | `0` | no |
| <a name="input_monitoring_role_arn"></a> [monitoring\_role\_arn](#input\_monitoring_role_arn) | ARN of a pre-existing IAM role for enhanced monitoring. When set, no role is created. | `string` | `null` | no |
| <a name="input_network_type"></a> [network\_type](#input\_network_type) | Network type of the cluster: 'IPV4' or 'DUAL' (dual-stack) | `string` | `null` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance_insights_enabled) | Specifies whether Performance Insights are enabled for all instances | `bool` | `false` | no |
| <a name="input_performance_insights_kms_key_id"></a> [performance\_insights\_kms\_key\_id](#input\_performance_insights_kms_key_id) | KMS key ID/ARN used to encrypt Performance Insights data | `string` | `null` | no |
| <a name="input_performance_insights_retention_period"></a> [performance\_insights\_retention\_period](#input\_performance_insights_retention_period) | Amount of time in days to retain Performance Insights data | `number` | `7` | no |
| <a name="input_port"></a> [port](#input\_port) | The port on which the DB accepts connections | `number` | `null` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred_backup_window) | The daily time range during which automated backups are created | `string` | `"02:00-03:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred_maintenance_window) | The window to perform maintenance in | `string` | `"sun:03:00-sun:04:00"` | no |
| <a name="input_publicly_accessible"></a> [publicly\_accessible](#input\_publicly_accessible) | Bool to control if cluster is publicly accessible | `bool` | `false` | no |
| <a name="input_security_group_name"></a> [security\_group\_name](#input\_security_group_name) | Name prefix for the security group | `string` | `null` | no |
| <a name="input_security_group_tags"></a> [security\_group\_tags](#input\_security_group_tags) | Additional tags for the security group | `map(string)` | `{}` | no |
| <a name="input_serverless_scaling_configuration"></a> [serverless\_scaling\_configuration](#input\_serverless_scaling_configuration) | Aurora Serverless v2 scaling configuration. Provide this (with db.serverless instance classes) to enable Serverless v2. min_capacity must be >= 0.5 and max_capacity >= min_capacity. | <pre>object({<br>&nbsp;&nbsp;&nbsp;&nbsp;min_capacity&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = number<br>&nbsp;&nbsp;&nbsp;&nbsp;max_capacity&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; = number<br>&nbsp;&nbsp;&nbsp;&nbsp;seconds_until_auto_pause = optional(number, 300)<br>&nbsp;&nbsp;})</pre> | `null` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip_final_snapshot) | Determines whether a final DB snapshot is created before the DB cluster is deleted | `bool` | `false` | no |
| <a name="input_snapshot_identifier"></a> [snapshot\_identifier](#input\_snapshot_identifier) | Snapshot or cluster snapshot ARN to restore the cluster from on creation | `string` | `null` | no |
| <a name="input_source_db_cluster_identifier"></a> [source\_db\_cluster\_identifier](#input\_source_db_cluster_identifier) | The DB cluster identifier of the source cluster for secondary region | `string` | `null` | no |
| <a name="input_source_region"></a> [source\_region](#input\_source_region) | Source region for Aurora Global Database secondary cluster | `string` | `null` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage_encrypted) | Specifies whether the DB cluster is encrypted | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage_type) | Aurora cluster storage type. Use 'aurora-iopt1' for Aurora I/O-Optimized, or leave null for standard Aurora storage. 'gp3' remains accepted for backward compatibility. | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet_ids) | A list of VPC subnet IDs (minimum 2 for HA). Required only when create_db_subnet_group is true. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to all resources | `map(string)` | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Define timeouts for Aurora operations | <pre>object({<br>&nbsp;&nbsp;&nbsp;&nbsp;create = optional(string, "120m")<br>&nbsp;&nbsp;&nbsp;&nbsp;update = optional(string, "120m")<br>&nbsp;&nbsp;&nbsp;&nbsp;delete = optional(string, "120m")<br>&nbsp;&nbsp;})</pre> | <pre>{<br>&nbsp;&nbsp;&nbsp;&nbsp;create = "120m"<br>&nbsp;&nbsp;&nbsp;&nbsp;update = "120m"<br>&nbsp;&nbsp;&nbsp;&nbsp;delete = "120m"<br>&nbsp;&nbsp;}</pre> | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc_id) | VPC ID where the Aurora cluster will be created. Required only when create_security_group is true. | `string` | `null` | no |
| <a name="input_vpc_security_group_ids"></a> [vpc\_security\_group\_ids](#input\_vpc_security_group_ids) | List of VPC security groups to associate | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_activity_stream_kinesis_stream_name"></a> [activity\_stream\_kinesis\_stream\_name](#output\_activity_stream_kinesis_stream_name) | Name of the Kinesis stream backing the database activity stream (null when disabled) |
| <a name="output_alarm_high_connections"></a> [alarm\_high\_connections](#output\_alarm_high_connections) | CloudWatch alarm for high database connections |
| <a name="output_alarm_high_cpu"></a> [alarm\_high\_cpu](#output\_alarm_high_cpu) | CloudWatch alarm for high CPU utilization |
| <a name="output_alarm_high_replica_lag"></a> [alarm\_high\_replica\_lag](#output\_alarm_high_replica_lag) | CloudWatch alarm for high replica lag |
| <a name="output_alarm_low_storage"></a> [alarm\_low\_storage](#output\_alarm_low_storage) | CloudWatch alarm for low free storage space |
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability_zones) | Availability zones used by the cluster |
| <a name="output_backup_retention_period"></a> [backup\_retention\_period](#output\_backup_retention_period) | The backup retention period in days |
| <a name="output_cloudwatch_log_groups"></a> [cloudwatch\_log\_groups](#output\_cloudwatch_log_groups) | Map of CloudWatch log group names that are enabled |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster_arn) | Amazon Resource Name (ARN) of cluster |
| <a name="output_cluster_database_name"></a> [cluster\_database\_name](#output\_cluster_database_name) | The database name created when the cluster was created |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster_endpoint) | The cluster endpoint for the primary writer instance |
| <a name="output_cluster_engine"></a> [cluster\_engine](#output\_cluster_engine) | The database engine type |
| <a name="output_cluster_engine_mode"></a> [cluster\_engine\_mode](#output\_cluster_engine_mode) | The database engine mode (provisioned or serverless) |
| <a name="output_cluster_engine_version"></a> [cluster\_engine\_version](#output\_cluster_engine_version) | The database engine version |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster_id) | The RDS Cluster Identifier |
| <a name="output_cluster_instance_arns"></a> [cluster\_instance\_arns](#output\_cluster_instance_arns) | Amazon Resource Names (ARNs) of the cluster instances |
| <a name="output_cluster_instance_endpoints"></a> [cluster\_instance\_endpoints](#output\_cluster_instance_endpoints) | Endpoints of the cluster instances |
| <a name="output_cluster_instance_ids"></a> [cluster\_instance\_ids](#output\_cluster_instance_ids) | List of RDS Cluster Instance Identifiers |
| <a name="output_cluster_master_username"></a> [cluster\_master\_username](#output\_cluster_master_username) | The master username for the database |
| <a name="output_cluster_members"></a> [cluster\_members](#output\_cluster_members) | List of RDS Instances that are part of this cluster |
| <a name="output_cluster_parameter_group_arn"></a> [cluster\_parameter\_group\_arn](#output\_cluster_parameter_group_arn) | The ARN of the cluster parameter group |
| <a name="output_cluster_parameter_group_id"></a> [cluster\_parameter\_group\_id](#output\_cluster_parameter_group_id) | The cluster parameter group ID |
| <a name="output_cluster_port"></a> [cluster\_port](#output\_cluster_port) | The port on which the database accepts connections |
| <a name="output_cluster_reader_endpoint"></a> [cluster\_reader\_endpoint](#output\_cluster_reader_endpoint) | The read-only endpoint for read-only replicas |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster_resource_id) | The RDS Cluster Resource ID |
| <a name="output_custom_endpoint_arns"></a> [custom\_endpoint\_arns](#output\_custom_endpoint_arns) | Map of custom cluster endpoint identifiers to their ARNs |
| <a name="output_custom_endpoints"></a> [custom\_endpoints](#output\_custom_endpoints) | Map of custom cluster endpoint identifiers to their DNS addresses |
| <a name="output_db_parameter_group_arn"></a> [db\_parameter\_group\_arn](#output\_db_parameter_group_arn) | The ARN of the DB parameter group |
| <a name="output_db_parameter_group_id"></a> [db\_parameter\_group\_id](#output\_db_parameter_group_id) | The DB parameter group ID |
| <a name="output_db_subnet_group_arn"></a> [db\_subnet\_group\_arn](#output\_db_subnet_group_arn) | ARN of the database subnet group (null when an existing subnet group is reused) |
| <a name="output_db_subnet_group_id"></a> [db\_subnet\_group\_id](#output\_db_subnet_group_id) | The database subnet group ID (null when an existing subnet group is reused) |
| <a name="output_db_subnet_group_name"></a> [db\_subnet\_group\_name](#output\_db_subnet_group_name) | The database subnet group name the cluster is attached to |
| <a name="output_db_subnet_ids"></a> [db\_subnet\_ids](#output\_db_subnet_ids) | List of subnet IDs in the database subnet group (empty when an existing subnet group is reused) |
| <a name="output_enhanced_monitoring_role_arn"></a> [enhanced\_monitoring\_role\_arn](#output\_enhanced_monitoring_role_arn) | ARN of the IAM role used for enhanced monitoring (created or provided) |
| <a name="output_enhanced_monitoring_role_name"></a> [enhanced\_monitoring\_role\_name](#output\_enhanced_monitoring_role_name) | Name of the IAM role for enhanced monitoring (only when created by this module) |
| <a name="output_global_cluster_arn"></a> [global\_cluster\_arn](#output\_global_cluster_arn) | The ARN of the global cluster |
| <a name="output_global_cluster_id"></a> [global\_cluster\_id](#output\_global_cluster_id) | The global cluster identifier |
| <a name="output_global_cluster_members"></a> [global\_cluster\_members](#output\_global_cluster_members) | List of global cluster members |
| <a name="output_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#output\_iam_database_authentication_enabled) | Whether IAM database authentication is enabled |
| <a name="output_iam_role_associations"></a> [iam\_role\_associations](#output\_iam_role_associations) | Map of associated IAM role labels to their role ARNs |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms_key_id) | The ARN of the KMS encryption key used for encryption |
| <a name="output_master_user_secret_arn"></a> [master\_user\_secret\_arn](#output\_master_user_secret_arn) | ARN of the RDS-managed master user secret in Secrets Manager (null unless manage_master_user_password is true) |
| <a name="output_master_user_secret_kms_key_id"></a> [master\_user\_secret\_kms\_key\_id](#output\_master_user_secret_kms_key_id) | KMS key ID used to encrypt the RDS-managed master user secret |
| <a name="output_preferred_backup_window"></a> [preferred\_backup\_window](#output\_preferred_backup_window) | The preferred backup window |
| <a name="output_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#output\_preferred_maintenance_window) | The preferred maintenance window |
| <a name="output_reader_connection_string"></a> [reader\_connection\_string](#output\_reader_connection_string) | Connection string for the read-only endpoint |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security_group_id) | Security group ID created for Aurora cluster (if created) |
| <a name="output_security_group_name"></a> [security\_group\_name](#output\_security_group_name) | Security group name created for Aurora cluster |
| <a name="output_storage_encrypted"></a> [storage\_encrypted](#output\_storage_encrypted) | Whether the database is encrypted |
| <a name="output_writer_connection_string"></a> [writer\_connection\_string](#output\_writer_connection_string) | Connection string for the writer endpoint |
<!-- END_TF_DOCS -->
