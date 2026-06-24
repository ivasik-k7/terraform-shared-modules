# the asg replaces a dead box on its own, but nobody knows it happened. this
# alarm is the signal - ec2 status check failing on any instance in the group.

resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  count = local.create && var.create_cloudwatch_alarms ? 1 : 0

  alarm_name          = "${var.name}-bastion-status-check-failed"
  namespace           = "AWS/EC2"
  metric_name         = "StatusCheckFailed"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period
  statistic           = "Maximum"
  treat_missing_data  = "notBreaching"
  alarm_description   = "EC2 status check failing on the ${var.name} bastion ASG"

  # AutoScalingGroupName dimension aggregates across whatever instances exist
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.this[0].name
  }

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion-status-check-failed" })
}
