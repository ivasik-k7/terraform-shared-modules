resource "aws_cloudwatch_log_group" "textract" {
  count = var.enable_cloudwatch_logs ? 1 : 0

  name              = local.resource_names.log_group
  retention_in_days = var.log_retention_days
  kms_key_id        = var.enable_log_encryption ? var.kms_key_arn : null

  tags = merge(
    local.common_tags,
    {
      Name      = local.resource_names.log_group
      Purpose   = "Textract operation logs"
      DataClass = "operational"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "textract_errors" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = local.resource_names.alarm_error
  alarm_description   = "Alert when Textract error rate exceeds threshold in ${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  metric_name         = "UserErrorCount"
  namespace           = "AWS/Textract"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.error_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
    Region      = data.aws_region.current.name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(
    local.common_tags,
    {
      Name      = local.resource_names.alarm_error
      AlarmType = "error-rate"
      Severity  = "high"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "textract_throttles" {
  count = var.enable_cloudwatch_alarms ? 1 : 0

  alarm_name          = local.resource_names.alarm_throttle
  alarm_description   = "Alert when Textract throttling occurs in ${var.environment}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  datapoints_to_alarm = var.alarm_datapoints_to_alarm
  metric_name         = "ThrottledCount"
  namespace           = "AWS/Textract"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.throttle_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    Environment = var.environment
    Region      = data.aws_region.current.name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.alarm_actions

  tags = merge(
    local.common_tags,
    {
      Name      = local.resource_names.alarm_throttle
      AlarmType = "throttle"
      Severity  = "medium"
    }
  )
}
