# one log group per service unless the caller points at an existing one.

resource "aws_cloudwatch_log_group" "service" {
  for_each = local.services_with_log_group

  name              = local.service_log_group[each.key]
  retention_in_days = coalesce(each.value.log_retention_days, var.log_retention_days)
  kms_key_id        = var.log_kms_key_id

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}" })
}
