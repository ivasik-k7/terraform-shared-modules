# BurstBalance alarm — only meaningful for gp2/st1/sc1 volumes, which rely on
# an I/O credit / throughput burst bucket. A depleting balance is an early
# warning that the volume is undersized for its workload.
resource "aws_cloudwatch_metric_alarm" "burst_balance" {
  for_each = var.create_cloudwatch_alarms ? local.burst_balance_volumes : {}

  alarm_name          = "${var.name}-${each.key}-burst-balance"
  alarm_description   = "EBS BurstBalance for ${var.name}-${each.key} is below ${var.burst_balance_alarm_threshold}%"
  namespace           = "AWS/EBS"
  metric_name         = "BurstBalance"
  statistic           = "Average"
  comparison_operator = "LessThanThreshold"
  threshold           = var.burst_balance_alarm_threshold
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "missing"

  dimensions = {
    VolumeId = aws_ebs_volume.this[each.key].id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-${each.key}-burst-balance"
    }
  )
}

# IdleTime alarm — high idle time across all volume types can flag a detached
# or unused volume that is still incurring cost (FinOps signal). This is a coarse
# heuristic: it can false-positive on legitimately quiet volumes, so it is fully
# togglable (var.enable_idle_alarm) and its threshold/sensitivity are tunable.
resource "aws_cloudwatch_metric_alarm" "idle" {
  for_each = var.create_cloudwatch_alarms && var.enable_idle_alarm ? local.volumes : {}

  alarm_name          = "${var.name}-${each.key}-idle"
  alarm_description   = "EBS volume ${var.name}-${each.key} has been idle for an extended period (possible detached/unused volume incurring cost)"
  namespace           = "AWS/EBS"
  metric_name         = "VolumeIdleTime"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.idle_alarm_threshold_seconds
  period              = 300
  evaluation_periods  = var.idle_alarm_evaluation_periods
  treat_missing_data  = "notBreaching"

  dimensions = {
    VolumeId = aws_ebs_volume.this[each.key].id
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(
    var.tags,
    {
      Name = "${var.name}-${each.key}-idle"
    }
  )
}
