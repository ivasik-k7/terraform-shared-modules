locals {
  default_port = var.engine == "aurora-postgresql" ? 5432 : 3306
  port         = coalesce(var.port, local.default_port)

  cluster_parameter_group_family = coalesce(
    var.cluster_parameter_group_family,
    var.engine == "aurora-postgresql" ? "aurora-postgresql${replace(var.engine_version, "/\\..*/", "")}" :
    var.engine == "aurora-mysql" ? "aurora-mysql${split(".", var.engine_version)[0]}.${split(".", var.engine_version)[1]}" : "aurora5.6"
  )

  db_parameter_group_family = coalesce(
    var.db_parameter_group_family,
    var.engine == "aurora-postgresql" ? "aurora-postgresql${replace(var.engine_version, "/\\..*/", "")}" :
    var.engine == "aurora-mysql" ? "aurora-mysql${split(".", var.engine_version)[0]}.${split(".", var.engine_version)[1]}" : "aurora5.6"
  )

  security_group_name = coalesce(var.security_group_name, "${var.cluster_identifier}-sg")
  subnet_group_name   = coalesce(var.db_subnet_group_name, "${var.cluster_identifier}-subnet-group")

  # Resolved DB subnet group name the cluster attaches to (created or pre-existing)
  db_subnet_group_name = var.create_db_subnet_group ? aws_db_subnet_group.main[0].name : var.db_subnet_group_name

  # Enhanced monitoring role resolution: create one only when monitoring is on,
  # creation is requested, and no external role ARN was supplied.
  create_monitoring_role = var.monitoring_interval > 0 && var.create_monitoring_role && var.monitoring_role_arn == null
  monitoring_role_arn    = var.monitoring_interval > 0 ? (local.create_monitoring_role ? aws_iam_role.enhanced_monitoring[0].arn : var.monitoring_role_arn) : null

  common_tags = merge(
    var.tags,
    {
      "Module"    = "Aurora"
      "Cluster"   = var.cluster_identifier
      "ManagedBy" = "Terraform"
    }
  )
}

# ============================================================================
# GLOBAL CLUSTER (OPTIONAL)
# ============================================================================

resource "aws_rds_global_cluster" "main" {
  count                     = var.enable_global_cluster ? 1 : 0
  global_cluster_identifier = var.global_cluster_identifier
  engine                    = var.engine
  engine_version            = var.engine_version
  storage_encrypted         = var.storage_encrypted
  database_name             = var.database_name

  tags = merge(
    local.common_tags,
    {
      "Name" = var.global_cluster_identifier
    }
  )
}

# ============================================================================
# DB SUBNET GROUP
# ============================================================================

resource "aws_db_subnet_group" "main" {
  count       = var.create_db_subnet_group ? 1 : 0
  name        = local.subnet_group_name
  description = coalesce(var.db_subnet_group_description, "Subnet group for ${var.cluster_identifier}")
  subnet_ids  = var.subnet_ids

  tags = merge(
    local.common_tags,
    {
      "Name" = local.subnet_group_name
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# Preserve state for callers upgrading from the pre-count subnet group resource.
moved {
  from = aws_db_subnet_group.main
  to   = aws_db_subnet_group.main[0]
}

# ============================================================================
# CLUSTER PARAMETER GROUP
# ============================================================================

resource "aws_rds_cluster_parameter_group" "main" {
  count       = var.create_cluster_parameter_group ? 1 : 0
  name_prefix = "${var.cluster_identifier}-cpg-"
  description = "Cluster parameter group for ${var.cluster_identifier}"
  family      = local.cluster_parameter_group_family

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.cluster_identifier}-cpg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# DB PARAMETER GROUP
# ============================================================================

resource "aws_db_parameter_group" "main" {
  count       = var.create_db_parameter_group ? 1 : 0
  name_prefix = "${var.cluster_identifier}-pg-"
  description = "Parameter group for ${var.cluster_identifier}"
  family      = local.db_parameter_group_family

  dynamic "parameter" {
    for_each = var.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.cluster_identifier}-pg"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ============================================================================
# RDS CLUSTER
# ============================================================================

resource "aws_rds_cluster" "main" {
  cluster_identifier                  = var.cluster_identifier
  engine                              = var.engine
  engine_version                      = var.engine_version
  engine_mode                         = var.engine_mode
  database_name                       = var.database_name
  master_username                     = var.master_username
  master_password                     = var.manage_master_user_password ? null : var.master_password
  manage_master_user_password         = var.manage_master_user_password ? true : null
  master_user_secret_kms_key_id       = var.manage_master_user_password ? var.master_user_secret_kms_key_id : null
  db_subnet_group_name                = local.db_subnet_group_name
  port                                = local.port
  availability_zones                  = var.availability_zones
  db_cluster_parameter_group_name     = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].name : var.cluster_parameter_group_name
  storage_encrypted                   = var.storage_encrypted
  kms_key_id                          = var.kms_key_id
  backup_retention_period             = var.enable_automated_backup ? var.backup_retention_period : 1
  preferred_backup_window             = var.enable_automated_backup ? var.preferred_backup_window : null
  preferred_maintenance_window        = var.preferred_maintenance_window
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : coalesce(var.final_snapshot_identifier, "${var.cluster_identifier}-final-snapshot")
  snapshot_identifier                 = var.snapshot_identifier
  copy_tags_to_snapshot               = var.copy_tags_to_snapshot
  deletion_protection                 = var.deletion_protection
  apply_immediately                   = var.apply_immediately
  allow_major_version_upgrade         = var.allow_major_version_upgrade
  enable_local_write_forwarding       = var.enable_local_write_forwarding
  network_type                        = var.network_type
  enable_http_endpoint                = var.enable_http_endpoint
  iam_database_authentication_enabled = var.iam_database_authentication_enabled
  enabled_cloudwatch_logs_exports     = var.enabled_cloudwatch_logs_exports
  backtrack_window                    = var.backtrack_window
  iops                                = var.iops
  storage_type                        = var.storage_type
  global_cluster_identifier           = var.enable_global_cluster ? aws_rds_global_cluster.main[0].id : null
  source_region                       = !var.is_primary_region ? var.source_region : null

  vpc_security_group_ids = concat(
    var.create_security_group ? [aws_security_group.aurora[0].id] : [],
    var.vpc_security_group_ids
  )


  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverless_scaling_configuration != null ? [var.serverless_scaling_configuration] : []
    content {
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      # Auto-pause only applies when min_capacity is 0; otherwise leave it unset.
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.min_capacity == 0 ? serverlessv2_scaling_configuration.value.seconds_until_auto_pause : null
    }
  }

  tags = merge(
    local.common_tags,
    var.cluster_tags,
    {
      "Name" = var.cluster_identifier
    }
  )

  timeouts {
    create = var.timeouts.create
    update = var.timeouts.update
    delete = var.timeouts.delete
  }

  depends_on = [
    aws_db_subnet_group.main,
    aws_security_group.aurora
  ]
}

# ============================================================================
# RDS CLUSTER INSTANCES
# ============================================================================

resource "aws_rds_cluster_instance" "instances" {
  for_each = var.instances

  identifier                 = "${var.cluster_identifier}-${each.key}"
  cluster_identifier         = aws_rds_cluster.main.id
  instance_class             = each.value.instance_class
  engine                     = var.engine
  engine_version             = var.engine_version
  promotion_tier             = each.value.promotion_tier
  publicly_accessible        = each.value.publicly_accessible
  db_parameter_group_name    = var.create_db_parameter_group ? aws_db_parameter_group.main[0].name : var.db_parameter_group_name
  monitoring_interval        = var.monitoring_interval
  monitoring_role_arn        = local.monitoring_role_arn
  ca_cert_identifier         = each.value.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled          = each.value.performance_insights_enabled || var.performance_insights_enabled
  performance_insights_retention_period = each.value.performance_insights_enabled || var.performance_insights_enabled ? each.value.performance_insights_retention_period : null
  performance_insights_kms_key_id       = (each.value.performance_insights_enabled || var.performance_insights_enabled) ? var.performance_insights_kms_key_id : null

  tags = merge(
    local.common_tags,
    var.instance_tags,
    each.value.tags,
    {
      "Name" = "${var.cluster_identifier}-${each.key}"
    }
  )

  depends_on = [
    aws_rds_cluster.main,
    aws_db_parameter_group.main
  ]

  lifecycle {
    ignore_changes = [
      engine_version
    ]
  }
}

# ============================================================================
# MONITORING ROLE FOR ENHANCED MONITORING
# ============================================================================

resource "aws_iam_role" "enhanced_monitoring" {
  count = local.create_monitoring_role ? 1 : 0
  name  = "${var.cluster_identifier}-rds-monitoring-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "monitoring.rds.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.cluster_identifier}-rds-monitoring-role"
    }
  )
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count      = local.create_monitoring_role ? 1 : 0
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ============================================================================
# CUSTOM CLUSTER ENDPOINTS
# ============================================================================

resource "aws_rds_cluster_endpoint" "custom" {
  for_each = var.cluster_endpoints

  cluster_identifier          = aws_rds_cluster.main.id
  cluster_endpoint_identifier = "${var.cluster_identifier}-${each.key}"
  custom_endpoint_type        = each.value.type
  static_members              = length(each.value.static_members) > 0 ? each.value.static_members : null
  excluded_members            = length(each.value.excluded_members) > 0 ? each.value.excluded_members : null

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.cluster_identifier}-${each.key}"
    }
  )

  depends_on = [aws_rds_cluster_instance.instances]
}

# ============================================================================
# IAM ROLE ASSOCIATIONS (S3 IMPORT/EXPORT, ETC.)
# ============================================================================

resource "aws_rds_cluster_role_association" "this" {
  for_each = var.iam_role_associations

  db_cluster_identifier = aws_rds_cluster.main.id
  feature_name          = each.value.feature_name
  role_arn              = each.value.role_arn
}

# ============================================================================
# DATABASE ACTIVITY STREAM
# ============================================================================

resource "aws_rds_cluster_activity_stream" "this" {
  count = var.enable_activity_stream ? 1 : 0

  resource_arn                        = aws_rds_cluster.main.arn
  mode                                = var.activity_stream_mode
  kms_key_id                          = var.activity_stream_kms_key_id
  engine_native_audit_fields_included = var.activity_stream_audit_fields_included

  depends_on = [aws_rds_cluster_instance.instances]
}
