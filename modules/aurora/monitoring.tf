# ============================================================================
# CLOUDWATCH ALARMS FOR AURORA
# ============================================================================

resource "aws_cloudwatch_metric_alarm" "database_connections" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-high-database-connections"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_connections_threshold
  alarm_description   = "Alert when database connections exceed ${var.alarm_connections_threshold}"
  treat_missing_data  = "notBreaching"

  dimensions = {
    "DBClusterIdentifier" = aws_rds_cluster.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "cpu_utilization" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-high-cpu-utilization"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_cpu_threshold_percent
  alarm_description   = "Alert when CPU utilization exceeds ${var.alarm_cpu_threshold_percent}%"
  treat_missing_data  = "notBreaching"

  dimensions = {
    "DBClusterIdentifier" = aws_rds_cluster.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_free_storage_space" {
  count               = var.create_alarms ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-low-free-storage-space"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_free_storage_space_bytes
  alarm_description   = "Alert when free storage space is below ${var.alarm_free_storage_space_bytes} bytes"
  treat_missing_data  = "notBreaching"

  dimensions = {
    "DBClusterIdentifier" = aws_rds_cluster.main.id
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "database_replica_lag" {
  count               = var.create_alarms && length(var.instances) > 1 ? 1 : 0
  alarm_name          = "${var.cluster_identifier}-high-replica-lag"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "AuroraBinlogReplicaLag"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = var.alarm_replica_lag_milliseconds
  alarm_description   = "Alert when replica lag exceeds ${var.alarm_replica_lag_milliseconds}ms"
  treat_missing_data  = "notBreaching"

  dimensions = {
    "DBClusterIdentifier" = aws_rds_cluster.main.id
  }

  tags = local.common_tags
}

# ============================================================================
# CLOUDWATCH LOG GROUPS
# ============================================================================

resource "aws_cloudwatch_log_group" "aurora_logs" {
  for_each = toset(var.enabled_cloudwatch_logs_exports)

  name              = "/aws/rds/cluster/${var.cluster_identifier}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days

  tags = merge(
    local.common_tags,
    {
      "Name" = "${var.cluster_identifier}-${each.value}-logs"
    }
  )
}
