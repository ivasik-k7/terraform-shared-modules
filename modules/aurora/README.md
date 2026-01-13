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
| [aws_rds_cluster_instance.instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_instance) | resource |
| [aws_rds_cluster_parameter_group.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_cluster_parameter_group) | resource |
| [aws_rds_global_cluster.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/rds_global_cluster) | resource |
| [aws_security_group.aurora](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.allow_all](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_cidr](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_security_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_alarm_connections_threshold"></a> [alarm\_connections\_threshold](#input\_alarm\_connections\_threshold) | Database connections threshold for CloudWatch alarm | `number` | `80` | no |
| <a name="input_alarm_cpu_threshold_percent"></a> [alarm\_cpu\_threshold\_percent](#input\_alarm\_cpu\_threshold\_percent) | CPU utilization threshold for CloudWatch alarm (percent) | `number` | `80` | no |
| <a name="input_alarm_free_storage_space_bytes"></a> [alarm\_free\_storage\_space\_bytes](#input\_alarm\_free\_storage\_space\_bytes) | Free storage space threshold in bytes for CloudWatch alarm (default: 1 GB) | `number` | `1073741824` | no |
| <a name="input_alarm_replica_lag_milliseconds"></a> [alarm\_replica\_lag\_milliseconds](#input\_alarm\_replica\_lag\_milliseconds) | Replica lag threshold in milliseconds for CloudWatch alarm (default: 1000ms) | `number` | `1000` | no |
| <a name="input_allowed_cidr_blocks"></a> [allowed\_cidr\_blocks](#input\_allowed\_cidr\_blocks) | CIDR blocks allowed to access Aurora | `list(string)` | `[]` | no |
| <a name="input_allowed_security_groups"></a> [allowed\_security\_groups](#input\_allowed\_security\_groups) | Security group IDs allowed to access Aurora | `list(string)` | `[]` | no |
| <a name="input_auto_minor_version_upgrade"></a> [auto\_minor\_version\_upgrade](#input\_auto\_minor\_version\_upgrade) | Indicates that minor engine upgrades will be applied automatically | `bool` | `true` | no |
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of AZs for Aurora instances. If not specified, uses subnets' AZs | `list(string)` | `null` | no |
| <a name="input_backtrack_window"></a> [backtrack\_window](#input\_backtrack\_window) | Target backtrack window in seconds for Aurora MySQL. Only available for aurora-mysql | `number` | `null` | no |
| <a name="input_backup_encryption_key_id"></a> [backup\_encryption\_key\_id](#input\_backup\_encryption\_key\_id) | The KMS key ARN for encrypting backups | `string` | `null` | no |
| <a name="input_backup_retention_period"></a> [backup\_retention\_period](#input\_backup\_retention\_period) | The days to retain backups for | `number` | `7` | no |
| <a name="input_cloudwatch_log_retention_days"></a> [cloudwatch\_log\_retention\_days](#input\_cloudwatch\_log\_retention\_days) | CloudWatch log retention period in days | `number` | `7` | no |
| <a name="input_cluster_identifier"></a> [cluster\_identifier](#input\_cluster\_identifier) | The cluster identifier for Aurora cluster (up to 63 chars) | `string` | n/a | yes |
| <a name="input_cluster_parameter_group_family"></a> [cluster\_parameter\_group\_family](#input\_cluster\_parameter\_group\_family) | The family of the cluster parameter group | `string` | `null` | no |
| <a name="input_cluster_parameter_group_name"></a> [cluster\_parameter\_group\_name](#input\_cluster\_parameter\_group\_name) | Name of the cluster parameter group to use | `string` | `null` | no |
| <a name="input_cluster_parameters"></a> [cluster\_parameters](#input\_cluster\_parameters) | A list of cluster parameters to apply | <pre>list(object({<br>    name         = string<br>    value        = string<br>    apply_method = optional(string, "immediate")<br>  }))</pre> | `[]` | no |
| <a name="input_cluster_tags"></a> [cluster\_tags](#input\_cluster\_tags) | Additional tags for the Aurora cluster | `map(string)` | `{}` | no |
| <a name="input_copy_tags_to_snapshot"></a> [copy\_tags\_to\_snapshot](#input\_copy\_tags\_to\_snapshot) | Copy all cluster tags to snapshots | `bool` | `true` | no |
| <a name="input_create_alarms"></a> [create\_alarms](#input\_create\_alarms) | Whether to create CloudWatch alarms | `bool` | `true` | no |
| <a name="input_create_cluster_parameter_group"></a> [create\_cluster\_parameter\_group](#input\_create\_cluster\_parameter\_group) | Whether to create a cluster parameter group | `bool` | `true` | no |
| <a name="input_create_db_parameter_group"></a> [create\_db\_parameter\_group](#input\_create\_db\_parameter\_group) | Whether to create instance parameter group | `bool` | `true` | no |
| <a name="input_create_monitoring_role"></a> [create\_monitoring\_role](#input\_create\_monitoring\_role) | Create IAM role for enhanced monitoring | `bool` | `true` | no |
| <a name="input_create_security_group"></a> [create\_security\_group](#input\_create\_security\_group) | Whether to create security group for Aurora | `bool` | `true` | no |
| <a name="input_database_name"></a> [database\_name](#input\_database\_name) | The name of the database to create when the DB cluster is created | `string` | `null` | no |
| <a name="input_db_parameter_group_family"></a> [db\_parameter\_group\_family](#input\_db\_parameter\_group\_family) | The family of the DB parameter group | `string` | `null` | no |
| <a name="input_db_parameter_group_name"></a> [db\_parameter\_group\_name](#input\_db\_parameter\_group\_name) | Name of the DB parameter group to use | `string` | `null` | no |
| <a name="input_db_parameters"></a> [db\_parameters](#input\_db\_parameters) | A list of DB parameters to apply | <pre>list(object({<br>    name         = string<br>    value        = string<br>    apply_method = optional(string, "pending-reboot")<br>  }))</pre> | `[]` | no |
| <a name="input_deletion_protection"></a> [deletion\_protection](#input\_deletion\_protection) | If the DB cluster should have deletion protection enabled | `bool` | `true` | no |
| <a name="input_enable_automated_backup"></a> [enable\_automated\_backup](#input\_enable\_automated\_backup) | Enable or disable automated backups | `bool` | `true` | no |
| <a name="input_enable_global_cluster"></a> [enable\_global\_cluster](#input\_enable\_global\_cluster) | Whether to create a global Aurora database cluster | `bool` | `false` | no |
| <a name="input_enable_http_endpoint"></a> [enable\_http\_endpoint](#input\_enable\_http\_endpoint) | Enable HTTP endpoint (Data API) for Aurora Serverless | `bool` | `false` | no |
| <a name="input_enabled_cloudwatch_logs_exports"></a> [enabled\_cloudwatch\_logs\_exports](#input\_enabled\_cloudwatch\_logs\_exports) | List of log types to export to CloudWatch | `list(string)` | `[]` | no |
| <a name="input_engine"></a> [engine](#input\_engine) | The Aurora database engine to use | `string` | `"aurora-postgresql"` | no |
| <a name="input_engine_mode"></a> [engine\_mode](#input\_engine\_mode) | The database engine mode. For Aurora: 'provisioned' or 'serverless' | `string` | `"provisioned"` | no |
| <a name="input_engine_version"></a> [engine\_version](#input\_engine\_version) | The engine version to use | `string` | n/a | yes |
| <a name="input_global_cluster_identifier"></a> [global\_cluster\_identifier](#input\_global\_cluster\_identifier) | The global cluster identifier for Aurora Global Database. Required when enable\_global\_cluster = true | `string` | `null` | no |
| <a name="input_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#input\_iam\_database\_authentication\_enabled) | Specifies whether IAM Database authentication is enabled | `bool` | `false` | no |
| <a name="input_instance_tags"></a> [instance\_tags](#input\_instance\_tags) | Additional tags for Aurora instances | `map(string)` | `{}` | no |
| <a name="input_instances"></a> [instances](#input\_instances) | Map of Aurora instances to create. Key is instance identifier | <pre>map(object({<br>    instance_class                        = string<br>    promotion_tier                        = optional(number, 1)<br>    publicly_accessible                   = optional(bool, false)<br>    performance_insights_enabled          = optional(bool, false)<br>    performance_insights_retention_period = optional(number, 7)<br>    ca_cert_identifier                    = optional(string)<br>    tags                                  = optional(map(string), {})<br>  }))</pre> | <pre>{<br>  "writer": {<br>    "instance_class": "db.t3.medium",<br>    "promotion_tier": 0,<br>    "publicly_accessible": false<br>  }<br>}</pre> | no |
| <a name="input_iops"></a> [iops](#input\_iops) | The amount of provisioned IOPS for Aurora PostgreSQL with gp3 storage | `number` | `null` | no |
| <a name="input_is_primary_region"></a> [is\_primary\_region](#input\_is\_primary\_region) | Whether this is the primary region for the global cluster | `bool` | `true` | no |
| <a name="input_kms_key_id"></a> [kms\_key\_id](#input\_kms\_key\_id) | The ARN for the KMS encryption key | `string` | `null` | no |
| <a name="input_master_password"></a> [master\_password](#input\_master\_password) | Password for the master DB user | `string` | `null` | no |
| <a name="input_master_username"></a> [master\_username](#input\_master\_username) | Username for the master DB user | `string` | `"admin"` | no |
| <a name="input_monitoring_interval"></a> [monitoring\_interval](#input\_monitoring\_interval) | The interval, in seconds, between points when Enhanced Monitoring metrics are collected | `number` | `0` | no |
| <a name="input_performance_insights_enabled"></a> [performance\_insights\_enabled](#input\_performance\_insights\_enabled) | Specifies whether Performance Insights are enabled for all instances | `bool` | `false` | no |
| <a name="input_performance_insights_retention_period"></a> [performance\_insights\_retention\_period](#input\_performance\_insights\_retention\_period) | Amount of time in days to retain Performance Insights data | `number` | `7` | no |
| <a name="input_port"></a> [port](#input\_port) | The port on which the DB accepts connections | `number` | `null` | no |
| <a name="input_preferred_backup_window"></a> [preferred\_backup\_window](#input\_preferred\_backup\_window) | The daily time range during which automated backups are created | `string` | `"02:00-03:00"` | no |
| <a name="input_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#input\_preferred\_maintenance\_window) | The window to perform maintenance in | `string` | `"sun:03:00-sun:04:00"` | no |
| <a name="input_publicly_accessible"></a> [publicly\_accessible](#input\_publicly\_accessible) | Bool to control if cluster is publicly accessible | `bool` | `false` | no |
| <a name="input_security_group_name"></a> [security\_group\_name](#input\_security\_group\_name) | Name prefix for the security group | `string` | `null` | no |
| <a name="input_security_group_tags"></a> [security\_group\_tags](#input\_security\_group\_tags) | Additional tags for the security group | `map(string)` | `{}` | no |
| <a name="input_serverless_scaling_configuration"></a> [serverless\_scaling\_configuration](#input\_serverless\_scaling\_configuration) | Configuration for Aurora Serverless v2 scaling. Required when engine\_mode = 'serverless' | <pre>object({<br>    min_capacity             = number<br>    max_capacity             = number<br>    auto_pause               = optional(bool, false)<br>    seconds_until_auto_pause = optional(number, 300)<br>  })</pre> | `null` | no |
| <a name="input_skip_final_snapshot"></a> [skip\_final\_snapshot](#input\_skip\_final\_snapshot) | Determines whether a final DB snapshot is created before the DB cluster is deleted | `bool` | `false` | no |
| <a name="input_source_db_cluster_identifier"></a> [source\_db\_cluster\_identifier](#input\_source\_db\_cluster\_identifier) | The DB cluster identifier of the source cluster for secondary region | `string` | `null` | no |
| <a name="input_source_region"></a> [source\_region](#input\_source\_region) | Source region for Aurora Global Database secondary cluster | `string` | `null` | no |
| <a name="input_storage_encrypted"></a> [storage\_encrypted](#input\_storage\_encrypted) | Specifies whether the DB cluster is encrypted | `bool` | `true` | no |
| <a name="input_storage_type"></a> [storage\_type](#input\_storage\_type) | Specifies the storage type. Only 'gp3' is supported for Aurora PostgreSQL | `string` | `null` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | A list of VPC subnet IDs (minimum 2 for HA) | `list(string)` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to all resources | `map(string)` | `{}` | no |
| <a name="input_timeouts"></a> [timeouts](#input\_timeouts) | Define timeouts for Aurora operations | <pre>object({<br>    create = optional(string, "120m")<br>    update = optional(string, "120m")<br>    delete = optional(string, "120m")<br>  })</pre> | <pre>{<br>  "create": "120m",<br>  "delete": "120m",<br>  "update": "120m"<br>}</pre> | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID where the Aurora cluster will be created | `string` | n/a | yes |
| <a name="input_vpc_security_group_ids"></a> [vpc\_security\_group\_ids](#input\_vpc\_security\_group\_ids) | List of VPC security groups to associate | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_high_connections"></a> [alarm\_high\_connections](#output\_alarm\_high\_connections) | CloudWatch alarm for high database connections |
| <a name="output_alarm_high_cpu"></a> [alarm\_high\_cpu](#output\_alarm\_high\_cpu) | CloudWatch alarm for high CPU utilization |
| <a name="output_alarm_high_replica_lag"></a> [alarm\_high\_replica\_lag](#output\_alarm\_high\_replica\_lag) | CloudWatch alarm for high replica lag |
| <a name="output_alarm_low_storage"></a> [alarm\_low\_storage](#output\_alarm\_low\_storage) | CloudWatch alarm for low free storage space |
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | Availability zones used by the cluster |
| <a name="output_backup_encryption_key_id"></a> [backup\_encryption\_key\_id](#output\_backup\_encryption\_key\_id) | The KMS key ARN used for backup encryption |
| <a name="output_backup_retention_period"></a> [backup\_retention\_period](#output\_backup\_retention\_period) | The backup retention period in days |
| <a name="output_cloudwatch_log_groups"></a> [cloudwatch\_log\_groups](#output\_cloudwatch\_log\_groups) | Map of CloudWatch log group names that are enabled |
| <a name="output_cluster_arn"></a> [cluster\_arn](#output\_cluster\_arn) | Amazon Resource Name (ARN) of cluster |
| <a name="output_cluster_database_name"></a> [cluster\_database\_name](#output\_cluster\_database\_name) | The database name created when the cluster was created |
| <a name="output_cluster_endpoint"></a> [cluster\_endpoint](#output\_cluster\_endpoint) | The cluster endpoint for the primary writer instance |
| <a name="output_cluster_engine"></a> [cluster\_engine](#output\_cluster\_engine) | The database engine type |
| <a name="output_cluster_engine_mode"></a> [cluster\_engine\_mode](#output\_cluster\_engine\_mode) | The database engine mode (provisioned or serverless) |
| <a name="output_cluster_engine_version"></a> [cluster\_engine\_version](#output\_cluster\_engine\_version) | The database engine version |
| <a name="output_cluster_id"></a> [cluster\_id](#output\_cluster\_id) | The RDS Cluster Identifier |
| <a name="output_cluster_instance_arns"></a> [cluster\_instance\_arns](#output\_cluster\_instance\_arns) | Amazon Resource Names (ARNs) of the cluster instances |
| <a name="output_cluster_instance_endpoints"></a> [cluster\_instance\_endpoints](#output\_cluster\_instance\_endpoints) | Endpoints of the cluster instances |
| <a name="output_cluster_instance_ids"></a> [cluster\_instance\_ids](#output\_cluster\_instance\_ids) | List of RDS Cluster Instance Identifiers |
| <a name="output_cluster_master_username"></a> [cluster\_master\_username](#output\_cluster\_master\_username) | The master username for the database |
| <a name="output_cluster_members"></a> [cluster\_members](#output\_cluster\_members) | List of RDS Instances that are part of this cluster |
| <a name="output_cluster_parameter_group_arn"></a> [cluster\_parameter\_group\_arn](#output\_cluster\_parameter\_group\_arn) | The ARN of the cluster parameter group |
| <a name="output_cluster_parameter_group_id"></a> [cluster\_parameter\_group\_id](#output\_cluster\_parameter\_group\_id) | The cluster parameter group ID |
| <a name="output_cluster_port"></a> [cluster\_port](#output\_cluster\_port) | The port on which the database accepts connections |
| <a name="output_cluster_reader_endpoint"></a> [cluster\_reader\_endpoint](#output\_cluster\_reader\_endpoint) | The read-only endpoint for read-only replicas |
| <a name="output_cluster_resource_id"></a> [cluster\_resource\_id](#output\_cluster\_resource\_id) | The RDS Cluster Resource ID |
| <a name="output_db_parameter_group_arn"></a> [db\_parameter\_group\_arn](#output\_db\_parameter\_group\_arn) | The ARN of the DB parameter group |
| <a name="output_db_parameter_group_id"></a> [db\_parameter\_group\_id](#output\_db\_parameter\_group\_id) | The DB parameter group ID |
| <a name="output_db_subnet_group_arn"></a> [db\_subnet\_group\_arn](#output\_db\_subnet\_group\_arn) | ARN of the database subnet group |
| <a name="output_db_subnet_group_id"></a> [db\_subnet\_group\_id](#output\_db\_subnet\_group\_id) | The database subnet group ID |
| <a name="output_db_subnet_group_name"></a> [db\_subnet\_group\_name](#output\_db\_subnet\_group\_name) | The database subnet group name |
| <a name="output_db_subnet_ids"></a> [db\_subnet\_ids](#output\_db\_subnet\_ids) | List of subnet IDs in the database subnet group |
| <a name="output_enhanced_monitoring_role_arn"></a> [enhanced\_monitoring\_role\_arn](#output\_enhanced\_monitoring\_role\_arn) | ARN of the IAM role for enhanced monitoring (if created) |
| <a name="output_enhanced_monitoring_role_name"></a> [enhanced\_monitoring\_role\_name](#output\_enhanced\_monitoring\_role\_name) | Name of the IAM role for enhanced monitoring (if created) |
| <a name="output_global_cluster_arn"></a> [global\_cluster\_arn](#output\_global\_cluster\_arn) | The ARN of the global cluster |
| <a name="output_global_cluster_id"></a> [global\_cluster\_id](#output\_global\_cluster\_id) | The global cluster identifier |
| <a name="output_global_cluster_members"></a> [global\_cluster\_members](#output\_global\_cluster\_members) | List of global cluster members |
| <a name="output_iam_database_authentication_enabled"></a> [iam\_database\_authentication\_enabled](#output\_iam\_database\_authentication\_enabled) | Whether IAM database authentication is enabled |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | The ARN of the KMS encryption key used for encryption |
| <a name="output_preferred_backup_window"></a> [preferred\_backup\_window](#output\_preferred\_backup\_window) | The preferred backup window |
| <a name="output_preferred_maintenance_window"></a> [preferred\_maintenance\_window](#output\_preferred\_maintenance\_window) | The preferred maintenance window |
| <a name="output_reader_connection_string"></a> [reader\_connection\_string](#output\_reader\_connection\_string) | Connection string for the read-only endpoint |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | Security group ID created for Aurora cluster (if created) |
| <a name="output_security_group_name"></a> [security\_group\_name](#output\_security\_group\_name) | Security group name created for Aurora cluster |
| <a name="output_storage_encrypted"></a> [storage\_encrypted](#output\_storage\_encrypted) | Whether the database is encrypted |
| <a name="output_writer_connection_string"></a> [writer\_connection\_string](#output\_writer\_connection\_string) | Connection string for the writer endpoint |
<!-- END_TF_DOCS -->