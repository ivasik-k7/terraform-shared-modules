# Flow logs are opt-in. The destination (CW Logs / S3 / Firehose) and IAM
# role are owned by the caller — building log groups inside this module
# would make the module destroy a foot-gun, and the IAM role typically
# already exists in the landing zone.
#
# Cost note: ALL traffic at 60s aggregation in a busy VPC adds up. For
# regulated environments use S3 + Athena. For light visibility, switch to
# 600s aggregation (default) and ACCEPT-only.
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
