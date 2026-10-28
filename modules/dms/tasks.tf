resource "aws_dms_replication_task" "this" {
  for_each = local.create && local.provisioned ? var.tasks : {}

  replication_task_id      = "${var.name}-${each.key}"
  replication_instance_arn = aws_dms_replication_instance.this[0].replication_instance_arn
  migration_type           = each.value.migration_type

  source_endpoint_arn = local.endpoint_arns[each.value.source_endpoint]
  target_endpoint_arn = local.endpoint_arns[each.value.target_endpoint]

  table_mappings            = each.value.table_mappings
  replication_task_settings = local.task_settings_json[each.key]

  cdc_start_time     = each.value.cdc_start_time != "" ? each.value.cdc_start_time : null
  cdc_start_position = each.value.cdc_start_position != "" ? each.value.cdc_start_position : null

  start_replication_task = each.value.start

  tags = merge(local.common_tags, { "MigrationType" = each.value.migration_type })
}

# ValidationOnly cannot be modified after a task is created.
# https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Tasks.CustomizingTasks.TaskSettings.DataValidation.html
resource "aws_dms_replication_task" "validation" {
  for_each = local.create && local.provisioned ? var.validation_tasks : {}

  replication_task_id      = "${var.name}-${each.key}"
  replication_instance_arn = aws_dms_replication_instance.this[0].replication_instance_arn
  migration_type           = each.value.mode

  # A validation-only task runs in the same direction as the task it validates.
  # https://docs.aws.amazon.com/dms/latest/userguide/CHAP_Validating.html#CHAP_Validating.ValidationOnly
  source_endpoint_arn = local.endpoint_arns[var.tasks[each.value.task].source_endpoint]
  target_endpoint_arn = local.endpoint_arns[var.tasks[each.value.task].target_endpoint]
  table_mappings      = var.tasks[each.value.task].table_mappings

  replication_task_settings = local.validation_task_settings_json[each.key]
  start_replication_task    = each.value.start

  tags = merge(local.common_tags, { "MigrationType" = "validation-only", "Validates" = each.value.task })
}
