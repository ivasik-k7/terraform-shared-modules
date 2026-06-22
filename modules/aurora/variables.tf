# ============================================================================
# REQUIRED VARIABLES
# ============================================================================

variable "cluster_identifier" {
  description = "The cluster identifier for Aurora cluster (up to 63 chars)"
  type        = string

  validation {
    condition     = length(var.cluster_identifier) <= 63 && can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.cluster_identifier))
    error_message = "Cluster identifier must be 63 characters or less, start with a letter, and contain only alphanumeric characters and hyphens."
  }
}

variable "engine" {
  description = "The Aurora database engine to use"
  type        = string
  default     = "aurora-postgresql"

  validation {
    condition     = contains(["aurora-mysql", "aurora-postgresql"], var.engine)
    error_message = "Engine must be either 'aurora-mysql' or 'aurora-postgresql'."
  }
}

variable "engine_version" {
  description = "The engine version to use"
  type        = string

  validation {
    condition = (
      var.engine == "aurora-mysql" ? can(regex("^[0-9]\\.[0-9]", var.engine_version)) :
      var.engine == "aurora-postgresql" ? can(regex("^[0-9]+(\\.[0-9]+)?$", var.engine_version)) :
      false
    )
    error_message = "Engine version format is invalid for the specified engine."
  }
}

variable "vpc_id" {
  description = "VPC ID where the Aurora cluster will be created. Required only when create_security_group is true."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-'."
  }

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
  }
}

variable "subnet_ids" {
  description = "A list of VPC subnet IDs (minimum 2 for HA). Required only when create_db_subnet_group is true."
  type        = list(string)
  default     = []

  validation {
    condition     = !var.create_db_subnet_group || length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for Aurora high availability when create_db_subnet_group is true."
  }
}

# ============================================================================
# AURORA-SPECIFIC CONFIGURATION
# ============================================================================

variable "engine_mode" {
  description = "The database engine mode. For Aurora: 'provisioned' or 'serverless'"
  type        = string
  default     = "provisioned"

  validation {
    condition     = contains(["provisioned", "serverless"], var.engine_mode)
    error_message = "Engine mode must be either 'provisioned' or 'serverless'."
  }
}

variable "serverless_scaling_configuration" {
  description = "Aurora Serverless v2 scaling configuration. Provide this (with db.serverless instance classes) to enable Serverless v2. min_capacity must be >= 0.5 and max_capacity >= min_capacity."
  type = object({
    min_capacity             = number
    max_capacity             = number
    seconds_until_auto_pause = optional(number, 300)
  })
  default = null

  # Capacity bounds are enforced whenever a configuration is supplied,
  # regardless of engine_mode (Serverless v2 runs on a provisioned cluster).
  # min_capacity may be 0 (scale-to-zero / auto-pause) or >= 0.5 ACUs.
  validation {
    condition = (
      var.serverless_scaling_configuration == null ||
      (
        (var.serverless_scaling_configuration.min_capacity == 0 || var.serverless_scaling_configuration.min_capacity >= 0.5) &&
        var.serverless_scaling_configuration.max_capacity >= 0.5 &&
        var.serverless_scaling_configuration.max_capacity >= var.serverless_scaling_configuration.min_capacity
      )
    )
    error_message = "Serverless v2 min_capacity must be 0 (scale-to-zero) or >= 0.5, and max_capacity must be >= 0.5 and >= min_capacity."
  }

  # The legacy engine_mode = 'serverless' (Serverless v1) still requires a config.
  validation {
    condition     = var.engine_mode != "serverless" || var.serverless_scaling_configuration != null
    error_message = "A serverless_scaling_configuration is required when engine_mode is 'serverless'."
  }
}

variable "backtrack_window" {
  description = "Target backtrack window in seconds for Aurora MySQL. Only available for aurora-mysql"
  type        = number
  default     = null

  validation {
    condition = (
      var.backtrack_window == null ||
      (var.engine == "aurora-mysql" && var.backtrack_window >= 0 && var.backtrack_window <= 259200)
    )
    error_message = "Backtrack window can only be set for aurora-mysql and must be between 0 and 259200 seconds (72 hours)."
  }
}

variable "enable_http_endpoint" {
  description = "Enable the RDS Data API (HTTP endpoint). Supported on Aurora Serverless v1 (engine_mode 'serverless') and, via the newer RDS Data API, on Serverless v2 and provisioned Aurora. Engine/version/region availability is enforced by AWS."
  type        = bool
  default     = false
}

# ============================================================================
# INSTANCE CONFIGURATION
# ============================================================================

variable "instances" {
  description = "Map of Aurora instances to create. Key is instance identifier"
  type = map(object({
    instance_class                        = string
    promotion_tier                        = optional(number, 1)
    publicly_accessible                   = optional(bool, false)
    performance_insights_enabled          = optional(bool, false)
    performance_insights_retention_period = optional(number, 7)
    ca_cert_identifier                    = optional(string)
    tags                                  = optional(map(string), {})
  }))
  default = {
    "writer" = {
      instance_class      = "db.t3.medium"
      promotion_tier      = 0
      publicly_accessible = false
    }
  }

  validation {
    condition = (
      length(var.instances) > 0 &&
      anytrue([for k, v in var.instances : v.promotion_tier == 0])
    )
    error_message = "At least one instance must have promotion_tier = 0 (writer instance)."
  }
}

variable "auto_minor_version_upgrade" {
  description = "Indicates that minor engine upgrades will be applied automatically"
  type        = bool
  default     = true
}

# ============================================================================
# STORAGE & ENCRYPTION
# ============================================================================

variable "storage_encrypted" {
  description = "Specifies whether the DB cluster is encrypted"
  type        = bool
  default     = true
}

variable "kms_key_id" {
  description = "The ARN for the KMS encryption key"
  type        = string
  default     = null
}

variable "iops" {
  description = "The amount of provisioned IOPS for Aurora PostgreSQL with gp3 storage"
  type        = number
  default     = null

  validation {
    condition = (
      var.iops == null ||
      (var.engine == "aurora-postgresql" && var.iops >= 1000 && var.iops <= 256000)
    )
    error_message = "IOPS can only be set for aurora-postgresql and must be between 1000 and 256000."
  }
}

variable "storage_type" {
  description = "Aurora cluster storage type. Use 'aurora-iopt1' for Aurora I/O-Optimized, or leave null for standard Aurora storage. 'gp3' remains accepted for backward compatibility."
  type        = string
  default     = null

  validation {
    condition     = var.storage_type == null || contains(["aurora", "aurora-iopt1", "gp3"], var.storage_type)
    error_message = "Storage type must be one of: 'aurora', 'aurora-iopt1', or 'gp3'."
  }
}

# ============================================================================
# DATABASE CONFIGURATION
# ============================================================================

variable "database_name" {
  description = "The name of the database to create when the DB cluster is created"
  type        = string
  default     = null

  validation {
    condition = var.database_name == null || (
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.database_name)) &&
      length(var.database_name) <= 64
    )
    error_message = "Database name must start with a letter, contain only alphanumeric characters and underscores, and be 64 characters or less."
  }
}

variable "master_username" {
  description = "Username for the master DB user"
  type        = string
  default     = "admin"

  validation {
    condition     = length(var.master_username) >= 1 && length(var.master_username) <= 16
    error_message = "Master username must be between 1 and 16 characters."
  }
}

variable "master_password" {
  description = "Password for the master DB user"
  type        = string
  sensitive   = true
  default     = null

  validation {
    condition = var.master_password == null || (
      length(var.master_password) >= 8 &&
      can(regex("[A-Z]", var.master_password)) &&
      can(regex("[a-z]", var.master_password)) &&
      can(regex("[0-9]", var.master_password))
    )
    error_message = "Master password must be at least 8 characters and contain uppercase, lowercase, and numbers."
  }
}

variable "port" {
  description = "The port on which the DB accepts connections"
  type        = number
  default     = null

  validation {
    condition = var.port == null || (
      var.port >= 1150 && var.port <= 65535
    )
    error_message = "Port must be between 1150 and 65535."
  }
}

# ============================================================================
# NETWORK & ACCESS
# ============================================================================

variable "availability_zones" {
  description = "List of AZs for Aurora instances. If not specified, uses subnets' AZs"
  type        = list(string)
  default     = null
}

variable "publicly_accessible" {
  description = "Bool to control if cluster is publicly accessible"
  type        = bool
  default     = false
}

# ============================================================================
# PARAMETER GROUPS
# ============================================================================

variable "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group to use"
  type        = string
  default     = null
}

variable "create_cluster_parameter_group" {
  description = "Whether to create a cluster parameter group"
  type        = bool
  default     = true
}

variable "cluster_parameter_group_family" {
  description = "The family of the cluster parameter group"
  type        = string
  default     = null
}

variable "cluster_parameters" {
  description = "A list of cluster parameters to apply"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "immediate")
  }))
  default = []
}

variable "db_parameter_group_name" {
  description = "Name of the DB parameter group to use"
  type        = string
  default     = null
}

variable "create_db_parameter_group" {
  description = "Whether to create instance parameter group"
  type        = bool
  default     = true
}

variable "db_parameter_group_family" {
  description = "The family of the DB parameter group"
  type        = string
  default     = null
}

variable "db_parameters" {
  description = "A list of DB parameters to apply"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

# ============================================================================
# SECURITY
# ============================================================================

variable "create_security_group" {
  description = "Whether to create security group for Aurora"
  type        = bool
  default     = true
}

variable "security_group_name" {
  description = "Name prefix for the security group"
  type        = string
  default     = null
}

variable "vpc_security_group_ids" {
  description = "List of VPC security groups to associate"
  type        = list(string)
  default     = []
}

variable "allowed_cidr_blocks" {
  description = "IPv4 CIDR blocks allowed to access Aurora"
  type        = list(string)
  default     = []
}

variable "allowed_ipv6_cidr_blocks" {
  description = "IPv6 CIDR blocks allowed to access Aurora"
  type        = list(string)
  default     = []
}

variable "allowed_security_groups" {
  description = "Security group IDs allowed to access Aurora"
  type        = list(string)
  default     = []
}

variable "iam_database_authentication_enabled" {
  description = "Specifies whether IAM Database authentication is enabled"
  type        = bool
  default     = false
}

# ============================================================================
# BACKUP & MAINTENANCE
# ============================================================================

variable "backup_retention_period" {
  description = "The days to retain backups for"
  type        = number
  default     = 7

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35
    error_message = "Backup retention period must be between 1 and 35 days."
  }
}

variable "enable_automated_backup" {
  description = "Enable or disable automated backups"
  type        = bool
  default     = true
}

variable "preferred_backup_window" {
  description = "The daily time range during which automated backups are created"
  type        = string
  default     = "02:00-03:00"

  validation {
    condition     = can(regex("^([0-1]?[0-9]|2[0-3]):[0-5][0-9]-([0-1]?[0-9]|2[0-3]):[0-5][0-9]$", var.preferred_backup_window))
    error_message = "Backup window must be in the format 'HH:MM-HH:MM' (24-hour format)."
  }
}

variable "preferred_maintenance_window" {
  description = "The window to perform maintenance in"
  type        = string
  default     = "sun:03:00-sun:04:00"

  validation {
    condition = can(regex(
      "^(mon|tue|wed|thu|fri|sat|sun):([0-1]?[0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([0-1]?[0-9]|2[0-3]):[0-5][0-9]$",
      var.preferred_maintenance_window
    ))
    error_message = "Maintenance window must be in the format 'ddd:hh24:mi-ddd:hh24:mi' (e.g., sun:03:00-sun:04:00)."
  }
}

variable "skip_final_snapshot" {
  description = "Determines whether a final DB snapshot is created before the DB cluster is deleted"
  type        = bool
  default     = false
}

variable "copy_tags_to_snapshot" {
  description = "Copy all cluster tags to snapshots"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "If the DB cluster should have deletion protection enabled"
  type        = bool
  default     = true
}

# ============================================================================
# MONITORING & LOGGING
# ============================================================================

variable "enabled_cloudwatch_logs_exports" {
  description = "List of log types to export to CloudWatch"
  type        = list(string)
  default     = []
}

variable "cloudwatch_log_retention_days" {
  description = "CloudWatch log retention period in days"
  type        = number
  default     = 7

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.cloudwatch_log_retention_days)
    error_message = "Log retention days must be a valid CloudWatch Logs retention period."
  }
}

variable "monitoring_interval" {
  description = "The interval, in seconds, between points when Enhanced Monitoring metrics are collected"
  type        = number
  default     = 0

  validation {
    condition     = contains([0, 1, 5, 10, 15, 30, 60], var.monitoring_interval)
    error_message = "Monitoring interval must be one of: 0, 1, 5, 10, 15, 30, 60."
  }
}

variable "create_monitoring_role" {
  description = "Create IAM role for enhanced monitoring. Ignored when monitoring_role_arn is set."
  type        = bool
  default     = true
}

variable "monitoring_role_arn" {
  description = "ARN of a pre-existing IAM role for enhanced monitoring. When set, no role is created."
  type        = string
  default     = null
}

variable "performance_insights_kms_key_id" {
  description = "KMS key ID/ARN used to encrypt Performance Insights data"
  type        = string
  default     = null
}

variable "performance_insights_enabled" {
  description = "Specifies whether Performance Insights are enabled for all instances"
  type        = bool
  default     = false
}

variable "performance_insights_retention_period" {
  description = "Amount of time in days to retain Performance Insights data"
  type        = number
  default     = 7

  validation {
    condition = (
      !var.performance_insights_enabled ||
      var.performance_insights_retention_period == 7 ||
      var.performance_insights_retention_period == 731 ||
      (var.performance_insights_retention_period >= 31 &&
        var.performance_insights_retention_period <= 731 &&
      var.performance_insights_retention_period % 31 == 0)
    )
    error_message = "Performance insights retention period must be 7, 731, or a multiple of 31 between 31 and 731 days when enabled."
  }
}

# ============================================================================
# CLOUDWATCH ALARMS - THRESHOLDS
# ============================================================================

variable "alarm_cpu_threshold_percent" {
  description = "CPU utilization threshold for CloudWatch alarm (percent)"
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_cpu_threshold_percent > 0 && var.alarm_cpu_threshold_percent <= 100
    error_message = "CPU threshold must be between 1 and 100 percent."
  }
}

variable "alarm_connections_threshold" {
  description = "Database connections threshold for CloudWatch alarm"
  type        = number
  default     = 80

  validation {
    condition     = var.alarm_connections_threshold > 0
    error_message = "Connections threshold must be greater than 0."
  }
}

variable "alarm_free_storage_space_bytes" {
  description = "Free storage space threshold in bytes for CloudWatch alarm (default: 1 GB)"
  type        = number
  default     = 1073741824

  validation {
    condition     = var.alarm_free_storage_space_bytes > 0
    error_message = "Free storage space threshold must be greater than 0."
  }
}

variable "alarm_replica_lag_milliseconds" {
  description = "Replica lag threshold in milliseconds for CloudWatch alarm (default: 1000ms)"
  type        = number
  default     = 1000

  validation {
    condition     = var.alarm_replica_lag_milliseconds > 0
    error_message = "Replica lag threshold must be greater than 0."
  }
}

variable "create_alarms" {
  description = "Whether to create CloudWatch alarms"
  type        = bool
  default     = true
}

# ============================================================================
# GLOBAL DATABASE (OPTIONAL)
# ============================================================================

variable "enable_global_cluster" {
  description = "Whether to create a global Aurora database cluster"
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "The global cluster identifier for Aurora Global Database. Required when enable_global_cluster = true"
  type        = string
  default     = null

  validation {
    condition = var.global_cluster_identifier == null || (
      length(var.global_cluster_identifier) >= 1 &&
      length(var.global_cluster_identifier) <= 63 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9-]*$", var.global_cluster_identifier))
    )
    error_message = "Global cluster identifier must be 1-63 characters, start with a letter, and contain only alphanumeric characters and hyphens."
  }
}

variable "is_primary_region" {
  description = "Whether this is the primary region for the global cluster"
  type        = bool
  default     = true
}

variable "source_db_cluster_identifier" {
  description = "The DB cluster identifier of the source cluster for secondary region"
  type        = string
  default     = null
}

variable "source_region" {
  description = "Source region for Aurora Global Database secondary cluster"
  type        = string
  default     = null
}

# ============================================================================
# TAGS
# ============================================================================

variable "tags" {
  description = "A mapping of tags to assign to all resources"
  type        = map(string)
  default     = {}
}

variable "cluster_tags" {
  description = "Additional tags for the Aurora cluster"
  type        = map(string)
  default     = {}
}

variable "instance_tags" {
  description = "Additional tags for Aurora instances"
  type        = map(string)
  default     = {}
}

variable "security_group_tags" {
  description = "Additional tags for the security group"
  type        = map(string)
  default     = {}
}

# ============================================================================
# DB SUBNET GROUP
# ============================================================================

variable "create_db_subnet_group" {
  description = "Whether to create a DB subnet group. Set to false to attach the cluster to a pre-existing subnet group named by db_subnet_group_name."
  type        = bool
  default     = true

  validation {
    condition     = var.create_db_subnet_group || var.db_subnet_group_name != null
    error_message = "db_subnet_group_name must be provided when create_db_subnet_group is false."
  }
}

variable "db_subnet_group_name" {
  description = "Name of the DB subnet group. When create_db_subnet_group is true this overrides the generated name; when false it must reference an existing subnet group."
  type        = string
  default     = null
}

variable "db_subnet_group_description" {
  description = "Description for the created DB subnet group"
  type        = string
  default     = null
}

# ============================================================================
# MASTER CREDENTIALS MANAGEMENT (SECRETS MANAGER)
# ============================================================================

variable "manage_master_user_password" {
  description = "Let RDS generate and manage the master user password in AWS Secrets Manager. Mutually exclusive with master_password."
  type        = bool
  default     = false

  validation {
    condition     = !var.manage_master_user_password || var.master_password == null
    error_message = "master_password must be null when manage_master_user_password is true."
  }
}

variable "master_user_secret_kms_key_id" {
  description = "KMS key ID/ARN to encrypt the RDS-managed master user secret. Defaults to the AWS-managed aws/secretsmanager key when null."
  type        = string
  default     = null
}

# ============================================================================
# SNAPSHOT / RESTORE
# ============================================================================

variable "snapshot_identifier" {
  description = "Snapshot or cluster snapshot ARN to restore the cluster from on creation"
  type        = string
  default     = null
}

variable "final_snapshot_identifier" {
  description = "Name of the final snapshot taken on deletion. Defaults to '<cluster_identifier>-final-snapshot' when skip_final_snapshot is false."
  type        = string
  default     = null
}

# ============================================================================
# OPERATIONAL TOGGLES
# ============================================================================

variable "apply_immediately" {
  description = "Apply changes immediately instead of during the next maintenance window"
  type        = bool
  default     = false
}

variable "allow_major_version_upgrade" {
  description = "Allow major engine version upgrades when changing engine_version"
  type        = bool
  default     = false
}

variable "enable_local_write_forwarding" {
  description = "Enable local write forwarding so reader instances forward writes to the writer (Aurora MySQL and PostgreSQL)"
  type        = bool
  default     = false
}

variable "network_type" {
  description = "Network type of the cluster: 'IPV4' or 'DUAL' (dual-stack)"
  type        = string
  default     = null

  validation {
    condition     = var.network_type == null || contains(["IPV4", "DUAL"], var.network_type)
    error_message = "Network type must be either 'IPV4' or 'DUAL'."
  }
}

# ============================================================================
# CUSTOM CLUSTER ENDPOINTS
# ============================================================================

variable "cluster_endpoints" {
  description = "Map of additional custom Aurora cluster endpoints (e.g. dedicated analytics readers). Key becomes the endpoint identifier suffix. Use either static_members or excluded_members, not both. Members are full instance identifiers (e.g. '<cluster_identifier>-<instance_key>')."
  type = map(object({
    type             = string
    static_members   = optional(list(string), [])
    excluded_members = optional(list(string), [])
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.cluster_endpoints : contains(["READER", "ANY"], v.type)])
    error_message = "Custom endpoint type must be 'READER' or 'ANY'."
  }

  validation {
    condition     = alltrue([for k, v in var.cluster_endpoints : !(length(v.static_members) > 0 && length(v.excluded_members) > 0)])
    error_message = "A custom endpoint may set either static_members or excluded_members, not both."
  }
}

# ============================================================================
# IAM ROLE ASSOCIATIONS (S3 IMPORT/EXPORT, ETC.)
# ============================================================================

variable "iam_role_associations" {
  description = "Map of IAM roles to associate with the cluster for Aurora features such as S3 import/export. Key is a free-form label; feature_name is the Aurora feature (e.g. 's3Import', 's3Export')."
  type = map(object({
    role_arn     = string
    feature_name = string
  }))
  default = {}
}

# ============================================================================
# DATABASE ACTIVITY STREAM
# ============================================================================

variable "enable_activity_stream" {
  description = "Enable a Database Activity Stream for the cluster (provisioned Aurora only)"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_activity_stream || var.activity_stream_kms_key_id != null
    error_message = "activity_stream_kms_key_id is required when enable_activity_stream is true."
  }
}

variable "activity_stream_mode" {
  description = "Activity stream mode: 'async' (lower latency, best effort) or 'sync' (guaranteed delivery)"
  type        = string
  default     = "async"

  validation {
    condition     = contains(["async", "sync"], var.activity_stream_mode)
    error_message = "Activity stream mode must be either 'async' or 'sync'."
  }
}

variable "activity_stream_kms_key_id" {
  description = "KMS key ID/ARN used to encrypt the activity stream. Required when enable_activity_stream is true."
  type        = string
  default     = null
}

variable "activity_stream_audit_fields_included" {
  description = "Whether engine-native audit fields are included in the activity stream"
  type        = bool
  default     = false
}

# ============================================================================
# TIMEOUTS
# ============================================================================

variable "timeouts" {
  description = "Define timeouts for Aurora operations"
  type = object({
    create = optional(string, "120m")
    update = optional(string, "120m")
    delete = optional(string, "120m")
  })
  default = {
    create = "120m"
    update = "120m"
    delete = "120m"
  }
}
