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
  description = "VPC ID where the Aurora cluster will be created"
  type        = string

  validation {
    condition     = can(regex("^vpc-", var.vpc_id))
    error_message = "VPC ID must start with 'vpc-'."
  }
}

variable "subnet_ids" {
  description = "A list of VPC subnet IDs (minimum 2 for HA)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "At least 2 subnet IDs are required for Aurora high availability."
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
  description = "Configuration for Aurora Serverless v2 scaling. Required when engine_mode = 'serverless'"
  type = object({
    min_capacity             = number
    max_capacity             = number
    auto_pause               = optional(bool, false)
    seconds_until_auto_pause = optional(number, 300)
  })
  default = null

  validation {
    condition = (
      var.engine_mode != "serverless" ||
      (var.serverless_scaling_configuration != null &&
        var.serverless_scaling_configuration.min_capacity >= 0.5 &&
      var.serverless_scaling_configuration.max_capacity >= var.serverless_scaling_configuration.min_capacity)
    )
    error_message = "Serverless scaling configuration is required when engine_mode is 'serverless'. Min capacity must be >= 0.5, max >= min."
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
  description = "Enable HTTP endpoint (Data API) for Aurora Serverless"
  type        = bool
  default     = false

  validation {
    condition     = !var.enable_http_endpoint || var.engine_mode == "serverless"
    error_message = "HTTP endpoint (Data API) is only available for serverless engine mode."
  }
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
  description = "Specifies the storage type. Only 'gp3' is supported for Aurora PostgreSQL"
  type        = string
  default     = null

  validation {
    condition     = var.storage_type == null || (var.engine == "aurora-postgresql" && var.storage_type == "gp3")
    error_message = "Storage type can only be 'gp3' and only for aurora-postgresql engine."
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
  description = "CIDR blocks allowed to access Aurora"
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
  description = "Create IAM role for enhanced monitoring"
  type        = bool
  default     = true
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
# GLOBAL DATABASE (OPTIONAL)
# ============================================================================

variable "is_global_cluster" {
  description = "Whether this is a global Aurora database"
  type        = bool
  default     = false
}

variable "global_cluster_identifier" {
  description = "The global cluster identifier for Aurora Global Database"
  type        = string
  default     = null
}

variable "source_region" {
  description = "Source region for Aurora Global Database replica"
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
