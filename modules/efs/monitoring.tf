# ============================================================================
# CLOUDWATCH ALARMS FOR EFS
# ============================================================================

# Burst credit balance is only meaningful for the 'bursting' throughput mode.
resource "aws_cloudwatch_metric_alarm" "burst_credit_balance" {
  count = var.create_cloudwatch_alarms && var.throughput_mode == "bursting" ? 1 : 0

  alarm_name          = "${var.name}-efs-low-burst-credit-balance"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_burst_credit_balance_threshold
  alarm_description   = "EFS ${var.name} burst credit balance is below ${var.alarm_burst_credit_balance_threshold} bytes"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-efs-low-burst-credit-balance" })
}

# PercentIOLimit only applies to the 'generalPurpose' performance mode.
resource "aws_cloudwatch_metric_alarm" "percent_io_limit" {
  count = var.create_cloudwatch_alarms && var.performance_mode == "generalPurpose" ? 1 : 0

  alarm_name          = "${var.name}-efs-high-percent-io-limit"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "PercentIOLimit"
  namespace           = "AWS/EFS"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_percent_io_limit_threshold
  alarm_description   = "EFS ${var.name} is exceeding ${var.alarm_percent_io_limit_threshold}% of its I/O limit"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  dimensions = {
    FileSystemId = aws_efs_file_system.this.id
  }

  tags = merge(var.tags, { Name = "${var.name}-efs-high-percent-io-limit" })
}
