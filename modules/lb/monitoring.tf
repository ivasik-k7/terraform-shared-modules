# ============================================================================
# CLOUDWATCH ALARMS
# ============================================================================

# Per-target-group unhealthy host count (applies to ALB and NLB).
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  for_each = local.create && var.create_cloudwatch_alarms ? aws_lb_target_group.this : {}

  alarm_name          = "${var.name}-${each.key}-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "UnHealthyHostCount"
  namespace           = local.is_application ? "AWS/ApplicationELB" : "AWS/NetworkELB"
  period              = var.alarm_period
  statistic           = "Maximum"
  threshold           = var.alarm_unhealthy_host_threshold
  alarm_description   = "Target group ${each.key} has unhealthy hosts"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  dimensions = {
    TargetGroup  = each.value.arn_suffix
    LoadBalancer = aws_lb.this[0].arn_suffix
  }

  tags = merge(local.common_tags, { "Name" = "${var.name}-${each.key}-unhealthy-hosts" })
}

# ALB-only: load-balancer-generated 5XX responses.
resource "aws_cloudwatch_metric_alarm" "elb_5xx" {
  count = local.create && var.create_cloudwatch_alarms && local.is_application ? 1 : 0

  alarm_name          = "${var.name}-elb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "HTTPCode_ELB_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Sum"
  threshold           = var.alarm_5xx_threshold
  alarm_description   = "Application LB ${var.name} is returning 5XX responses"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  dimensions = {
    LoadBalancer = aws_lb.this[0].arn_suffix
  }

  tags = merge(local.common_tags, { "Name" = "${var.name}-elb-5xx" })
}

# ALB-only: target response time.
resource "aws_cloudwatch_metric_alarm" "target_response_time" {
  count = local.create && var.create_cloudwatch_alarms && local.is_application ? 1 : 0

  alarm_name          = "${var.name}-target-response-time"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = var.alarm_evaluation_periods
  metric_name         = "TargetResponseTime"
  namespace           = "AWS/ApplicationELB"
  period              = var.alarm_period
  statistic           = "Average"
  threshold           = var.alarm_target_response_time_threshold
  alarm_description   = "Application LB ${var.name} target response time is high"
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_actions
  ok_actions    = var.ok_actions

  dimensions = {
    LoadBalancer = aws_lb.this[0].arn_suffix
  }

  tags = merge(local.common_tags, { "Name" = "${var.name}-target-response-time" })
}
