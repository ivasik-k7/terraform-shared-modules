# ============================================================================
# CLUSTER OUTPUTS
# ============================================================================

output "cluster_id" {
  description = "The RDS Cluster Identifier"
  value       = aws_rds_cluster.main.id
}

output "cluster_arn" {
  description = "Amazon Resource Name (ARN) of cluster"
  value       = aws_rds_cluster.main.arn
}

output "cluster_resource_id" {
  description = "The RDS Cluster Resource ID"
  value       = aws_rds_cluster.main.cluster_resource_id
}

output "cluster_endpoint" {
  description = "The cluster endpoint for the primary writer instance"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "The read-only endpoint for read-only replicas"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_port" {
  description = "The port on which the database accepts connections"
  value       = aws_rds_cluster.main.port
}

output "cluster_database_name" {
  description = "The database name created when the cluster was created"
  value       = aws_rds_cluster.main.database_name
  sensitive   = true
}

output "cluster_master_username" {
  description = "The master username for the database"
  value       = aws_rds_cluster.main.master_username
  sensitive   = true
}

output "cluster_engine" {
  description = "The database engine type"
  value       = aws_rds_cluster.main.engine
}

output "cluster_engine_version" {
  description = "The database engine version"
  value       = aws_rds_cluster.main.engine_version
}

output "cluster_engine_mode" {
  description = "The database engine mode (provisioned or serverless)"
  value       = aws_rds_cluster.main.engine_mode
}

# ============================================================================
# GLOBAL CLUSTER OUTPUTS
# ============================================================================

output "global_cluster_id" {
  description = "The global cluster identifier"
  value       = var.enable_global_cluster ? aws_rds_global_cluster.main[0].id : null
}

output "global_cluster_arn" {
  description = "The ARN of the global cluster"
  value       = var.enable_global_cluster ? aws_rds_global_cluster.main[0].arn : null
}

output "global_cluster_members" {
  description = "List of global cluster members"
  value       = var.enable_global_cluster ? aws_rds_global_cluster.main[0].global_cluster_members : []
}

# ============================================================================
# CLUSTER INSTANCE OUTPUTS
# ============================================================================

output "cluster_instance_ids" {
  description = "List of RDS Cluster Instance Identifiers"
  value       = [for instance in aws_rds_cluster_instance.instances : instance.id]
}

output "cluster_instance_arns" {
  description = "Amazon Resource Names (ARNs) of the cluster instances"
  value       = { for k, v in aws_rds_cluster_instance.instances : k => v.arn }
}

output "cluster_instance_endpoints" {
  description = "Endpoints of the cluster instances"
  value       = { for k, v in aws_rds_cluster_instance.instances : k => v.endpoint }
}


# ============================================================================
# CLUSTER MEMBERS
# ============================================================================

output "cluster_members" {
  description = "List of RDS Instances that are part of this cluster"
  value       = aws_rds_cluster.main.cluster_members
}

# ============================================================================
# SECURITY & NETWORKING OUTPUTS
# ============================================================================

output "security_group_id" {
  description = "Security group ID created for Aurora cluster (if created)"
  value       = var.create_security_group ? aws_security_group.aurora[0].id : null
}

output "security_group_name" {
  description = "Security group name created for Aurora cluster"
  value       = var.create_security_group ? aws_security_group.aurora[0].name : null
}

output "db_subnet_group_id" {
  description = "The database subnet group ID"
  value       = aws_db_subnet_group.main.id
}

output "db_subnet_group_name" {
  description = "The database subnet group name"
  value       = aws_db_subnet_group.main.name
}

output "db_subnet_group_arn" {
  description = "ARN of the database subnet group"
  value       = aws_db_subnet_group.main.arn
}

output "db_subnet_ids" {
  description = "List of subnet IDs in the database subnet group"
  value       = aws_db_subnet_group.main.subnet_ids
}

# ============================================================================
# PARAMETER GROUP OUTPUTS
# ============================================================================

output "cluster_parameter_group_id" {
  description = "The cluster parameter group ID"
  value       = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].id : null
}

output "cluster_parameter_group_arn" {
  description = "The ARN of the cluster parameter group"
  value       = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].arn : null
}

output "db_parameter_group_id" {
  description = "The DB parameter group ID"
  value       = var.create_db_parameter_group ? aws_db_parameter_group.main[0].id : null
}

output "db_parameter_group_arn" {
  description = "The ARN of the DB parameter group"
  value       = var.create_db_parameter_group ? aws_db_parameter_group.main[0].arn : null
}

# ============================================================================
# MONITORING & LOGGING OUTPUTS
# ============================================================================

output "enhanced_monitoring_role_arn" {
  description = "ARN of the IAM role for enhanced monitoring (if created)"
  value       = var.monitoring_interval > 0 && var.create_monitoring_role ? aws_iam_role.enhanced_monitoring[0].arn : null
}

output "enhanced_monitoring_role_name" {
  description = "Name of the IAM role for enhanced monitoring (if created)"
  value       = var.monitoring_interval > 0 && var.create_monitoring_role ? aws_iam_role.enhanced_monitoring[0].name : null
}

output "cloudwatch_log_groups" {
  description = "Map of CloudWatch log group names that are enabled"
  value       = { for k, v in aws_cloudwatch_log_group.aurora_logs : k => v.name }
}

# ============================================================================
# AVAILABILITY & REPLICATION OUTPUTS
# ============================================================================

output "availability_zones" {
  description = "Availability zones used by the cluster"
  value       = aws_rds_cluster.main.availability_zones
}

output "backup_retention_period" {
  description = "The backup retention period in days"
  value       = aws_rds_cluster.main.backup_retention_period
}

output "preferred_backup_window" {
  description = "The preferred backup window"
  value       = aws_rds_cluster.main.preferred_backup_window
}

output "preferred_maintenance_window" {
  description = "The preferred maintenance window"
  value       = aws_rds_cluster.main.preferred_maintenance_window
}

output "backup_encryption_key_id" {
  description = "The KMS key ARN used for backup encryption"
  value       = var.backup_encryption_key_id
}

# ============================================================================
# CONNECTION STRINGS
# ============================================================================

output "writer_connection_string" {
  description = "Connection string for the writer endpoint"
  value = format(
    "%s://%s@%s:%d/%s",
    var.engine == "aurora-postgresql" ? "postgresql" : "mysql",
    var.master_username,
    aws_rds_cluster.main.endpoint,
    local.port,
    var.database_name != null ? var.database_name : ""
  )
  sensitive = true
}

output "reader_connection_string" {
  description = "Connection string for the read-only endpoint"
  value = format(
    "%s://%s@%s:%d/%s",
    var.engine == "aurora-postgresql" ? "postgresql" : "mysql",
    var.master_username,
    aws_rds_cluster.main.reader_endpoint,
    local.port,
    var.database_name != null ? var.database_name : ""
  )
  sensitive = true
}

# ============================================================================
# ENCRYPTION & SECURITY OUTPUTS
# ============================================================================

output "storage_encrypted" {
  description = "Whether the database is encrypted"
  value       = aws_rds_cluster.main.storage_encrypted
}

output "kms_key_id" {
  description = "The ARN of the KMS encryption key used for encryption"
  value       = aws_rds_cluster.main.kms_key_id
}

output "iam_database_authentication_enabled" {
  description = "Whether IAM database authentication is enabled"
  value       = aws_rds_cluster.main.iam_database_authentication_enabled
}

# ============================================================================
# CLOUDWATCH ALARMS OUTPUTS
# ============================================================================

output "alarm_high_cpu" {
  description = "CloudWatch alarm for high CPU utilization"
  value       = var.create_alarms ? aws_cloudwatch_metric_alarm.cpu_utilization[0].alarm_name : null
}

output "alarm_high_connections" {
  description = "CloudWatch alarm for high database connections"
  value       = var.create_alarms ? aws_cloudwatch_metric_alarm.database_connections[0].alarm_name : null
}

output "alarm_low_storage" {
  description = "CloudWatch alarm for low free storage space"
  value       = var.create_alarms ? aws_cloudwatch_metric_alarm.database_free_storage_space[0].alarm_name : null
}

output "alarm_high_replica_lag" {
  description = "CloudWatch alarm for high replica lag"
  value       = var.create_alarms && length(var.instances) > 1 ? aws_cloudwatch_metric_alarm.database_replica_lag[0].alarm_name : null
}

