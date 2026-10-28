resource "aws_cloudwatch_log_group" "this" {
  count = local.create ? 1 : 0

  name              = var.name
  retention_in_days = var.retention_days
  log_group_class   = var.log_group_class
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null
  skip_destroy      = var.skip_destroy

  tags = local.common_tags

  lifecycle {
    # A combination that is certainly wrong is a precondition: it fails the
    # plan, before anything is created, with a message naming the fix.
    precondition {
      condition     = !local.key_in_another_region
      error_message = "kms_key_arn is in another region than the log group (${local.region}); CloudWatch Logs uses only keys in its own region. Use a key, or a multi-Region replica, in ${local.region}."
    }
  }
}
