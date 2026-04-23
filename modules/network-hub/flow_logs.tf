# Flow logs are on by choice: they cost money and most of the value shows up
# when someone's actually analyzing them. The caller owns the destination
# (CW log group / S3 bucket / Firehose stream) and the publishing IAM role,
# so the module doesn't create either.
resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = local.vpc_id
  traffic_type             = var.flow_log_traffic_type
  log_destination_type     = var.flow_log_destination_type
  log_destination          = var.flow_log_destination_arn
  iam_role_arn             = var.flow_log_iam_role_arn
  log_format               = var.flow_log_log_format
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  tags = merge(local.base_tags, {
    Name = "${var.name}-flow-logs"
  })
}
