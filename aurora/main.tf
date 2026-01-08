locals {
  is_serverless = var.engine_mode == "serverless"
  default_port  = var.engine == "aurora-postgresql" ? 5432 : 3306
  port          = coalesce(var.port, local.default_port)

  cluster_parameter_group_family = coalesce(
    var.cluster_parameter_group_family,
    var.engine == "aurora-postgresql" ? "aurora-postgresql${replace(var.engine_version, "/\\..*/", "")}" :
    var.engine == "aurora-mysql" ? "aurora-mysql${split(".", var.engine_version)[0]}${split(".", var.engine_version)[1]}" : "aurora5.6"
  )

  db_parameter_group_family = coalesce(
    var.db_parameter_group_family,
    var.engine == "aurora-postgresql" ? "aurora-postgresql${replace(var.engine_version, "/\\..*/", "")}" :
    var.engine == "aurora-mysql" ? "aurora-mysql${split(".", var.engine_version)[0]}${split(".", var.engine_version)[1]}" : "aurora5.6"
  )

  security_group_name = coalesce(var.security_group_name, "${var.cluster_identifier}-sg")
  subnet_group_name   = "${var.cluster_identifier}-subnet-group"

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
  name       = local.subnet_group_name
  subnet_ids = var.subnet_ids

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
  master_password                     = var.master_password
  db_subnet_group_name                = aws_db_subnet_group.main.name
  port                                = local.port
  availability_zones                  = var.availability_zones
  db_cluster_parameter_group_name     = var.create_cluster_parameter_group ? aws_rds_cluster_parameter_group.main[0].name : var.cluster_parameter_group_name
  storage_encrypted                   = var.storage_encrypted
  kms_key_id                          = var.kms_key_id
  backup_retention_period             = var.enable_automated_backup ? var.backup_retention_period : 1
  preferred_backup_window             = var.enable_automated_backup ? var.preferred_backup_window : null
  preferred_maintenance_window        = var.preferred_maintenance_window
  skip_final_snapshot                 = var.skip_final_snapshot
  copy_tags_to_snapshot               = var.copy_tags_to_snapshot
  deletion_protection                 = var.deletion_protection
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
    for_each = local.is_serverless && var.serverless_scaling_configuration != null ? [var.serverless_scaling_configuration] : []
    content {
      max_capacity             = serverlessv2_scaling_configuration.value.max_capacity
      min_capacity             = serverlessv2_scaling_configuration.value.min_capacity
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.seconds_until_auto_pause
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
  monitoring_role_arn        = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null
  ca_cert_identifier         = each.value.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled          = each.value.performance_insights_enabled || var.performance_insights_enabled
  performance_insights_retention_period = each.value.performance_insights_enabled || var.performance_insights_enabled ? each.value.performance_insights_retention_period : null

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
  count = (var.monitoring_interval > 0 && var.create_monitoring_role) ? 1 : 0
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
  count      = (var.monitoring_interval > 0 && var.create_monitoring_role) ? 1 : 0
  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
