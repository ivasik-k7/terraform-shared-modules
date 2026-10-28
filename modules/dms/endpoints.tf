resource "aws_dms_endpoint" "this" {
  for_each = local.create ? var.endpoints : {}

  endpoint_id   = each.key
  endpoint_type = each.value.role
  engine_name   = each.value.engine

  # The provider refuses server_name, port, username and password alongside secrets_manager_arn.
  # https://github.com/hashicorp/terraform-provider-aws/blob/v5.100.0/internal/service/dms/endpoint.go
  server_name   = each.value.secret_arn == "" && each.value.server_name != "" ? each.value.server_name : null
  port          = each.value.secret_arn == "" && each.value.port != 0 ? each.value.port : null
  database_name = each.value.database_name != "" ? each.value.database_name : null

  secrets_manager_arn             = each.value.secret_arn != "" ? each.value.secret_arn : null
  secrets_manager_access_role_arn = each.value.secret_arn != "" ? local.endpoint_secret_role_arns[each.key] : null
  username                        = each.value.secret_arn == "" && each.value.username != "" ? each.value.username : null
  password                        = each.value.secret_arn == "" && each.value.password != "" ? each.value.password : null

  ssl_mode        = each.value.ssl_mode
  certificate_arn = local.endpoint_certificate_arns[each.key] != "" ? local.endpoint_certificate_arns[each.key] : null

  kms_key_arn = each.value.kms_key_arn != "" ? each.value.kms_key_arn : (var.kms_key_arn != "" ? var.kms_key_arn : null)

  extra_connection_attributes = each.value.extra_connection_attributes != "" ? each.value.extra_connection_attributes : null

  dynamic "postgres_settings" {
    for_each = contains(["postgres", "aurora-postgresql"], each.value.engine) && each.value.role == "source" ? [1] : []

    content {
      heartbeat_enable             = each.value.postgres.heartbeat_enable
      heartbeat_frequency          = each.value.postgres.heartbeat_frequency
      heartbeat_schema             = each.value.postgres.heartbeat_schema
      capture_ddls                 = each.value.postgres.capture_ddls
      slot_name                    = each.value.postgres.slot_name != "" ? each.value.postgres.slot_name : null
      map_boolean_as_boolean       = each.value.postgres.map_boolean_as_boolean
      fail_tasks_on_lob_truncation = each.value.postgres.fail_tasks_on_lob_truncation
      after_connect_script         = each.value.postgres.after_connect_script != "" ? each.value.postgres.after_connect_script : null
      execute_timeout              = each.value.postgres.execute_timeout
    }
  }

  dynamic "postgres_settings" {
    for_each = contains(["postgres", "aurora-postgresql"], each.value.engine) && each.value.role == "target" ? [1] : []

    content {
      map_boolean_as_boolean       = each.value.postgres.map_boolean_as_boolean
      fail_tasks_on_lob_truncation = each.value.postgres.fail_tasks_on_lob_truncation
      after_connect_script         = each.value.postgres.after_connect_script != "" ? each.value.postgres.after_connect_script : null
      execute_timeout              = each.value.postgres.execute_timeout
      max_file_size                = each.value.postgres.max_file_size
    }
  }

  tags = merge(local.common_tags, { "EndpointRole" = each.value.role })

  depends_on = [aws_iam_role_policy.endpoint_secret]

  lifecycle {
    # Provider 5.x sends postgres_settings on create only; its update path does not read them.
    # https://github.com/hashicorp/terraform-provider-aws/blob/v5.100.0/internal/service/dms/endpoint.go
    replace_triggered_by = [terraform_data.postgres_settings[each.key]]

    precondition {
      condition     = var.require_cmk ? length(local.endpoints_without_cmk) == 0 : true
      error_message = "require_cmk = true but these endpoints resolve to the AWS-managed DMS key: ${join(", ", local.endpoints_without_cmk)}. Set kms_key_arn on the module or on the endpoint."
    }
  }
}

resource "terraform_data" "postgres_settings" {
  for_each = local.create ? var.endpoints : {}

  # A conditional converts both of its results to one type, so each branch is encoded first.
  input = !contains(["postgres", "aurora-postgresql"], each.value.engine) ? "" : sha256(
    each.value.role == "source" ? jsonencode({
      heartbeat_enable             = each.value.postgres.heartbeat_enable
      heartbeat_frequency          = each.value.postgres.heartbeat_frequency
      heartbeat_schema             = each.value.postgres.heartbeat_schema
      capture_ddls                 = each.value.postgres.capture_ddls
      slot_name                    = each.value.postgres.slot_name
      map_boolean_as_boolean       = each.value.postgres.map_boolean_as_boolean
      fail_tasks_on_lob_truncation = each.value.postgres.fail_tasks_on_lob_truncation
      after_connect_script         = each.value.postgres.after_connect_script
      execute_timeout              = each.value.postgres.execute_timeout
      }) : jsonencode({
      map_boolean_as_boolean       = each.value.postgres.map_boolean_as_boolean
      fail_tasks_on_lob_truncation = each.value.postgres.fail_tasks_on_lob_truncation
      after_connect_script         = each.value.postgres.after_connect_script
      execute_timeout              = each.value.postgres.execute_timeout
      max_file_size                = each.value.postgres.max_file_size
    })
  )
}

resource "aws_dms_s3_endpoint" "this" {
  for_each = local.create ? var.s3_targets : {}

  endpoint_id   = each.key
  endpoint_type = "target"

  bucket_name   = each.value.bucket_name
  bucket_folder = each.value.bucket_folder != "" ? each.value.bucket_folder : null

  service_access_role_arn = local.s3_target_role_arns[each.key]

  data_format      = each.value.data_format
  compression_type = each.value.compression_type
  parquet_version  = each.value.data_format == "parquet" ? each.value.parquet_version : null

  encryption_mode                   = each.value.encryption_mode
  server_side_encryption_kms_key_id = each.value.encryption_mode == "SSE_KMS" && each.value.kms_key_arn != "" ? each.value.kms_key_arn : null

  date_partition_enabled  = each.value.date_partition_enabled
  date_partition_sequence = each.value.date_partition_enabled ? each.value.date_partition_sequence : null
  cdc_path                = each.value.cdc_path != "" ? each.value.cdc_path : null

  include_op_for_full_load = each.value.include_op_for_full_load
  timestamp_column_name    = each.value.timestamp_column_name != "" ? each.value.timestamp_column_name : null

  glue_catalog_generation = each.value.glue_catalog_generation

  tags = merge(local.common_tags, { "EndpointRole" = "target" })

  depends_on = [aws_iam_role_policy.s3_target]

  lifecycle {
    precondition {
      condition     = var.require_cmk ? length(local.s3_targets_without_cmk) == 0 : true
      error_message = "require_cmk = true but these S3 targets are not encrypted with a customer-managed key: ${join(", ", local.s3_targets_without_cmk)}. Set encryption_mode = \"SSE_KMS\" and kms_key_arn."
    }
  }
}

resource "aws_dms_certificate" "this" {
  for_each = local.create ? var.certificates : {}

  certificate_id     = "${var.name}-${each.key}-${local.certificate_digests[each.key]}"
  certificate_pem    = each.value.pem != "" ? each.value.pem : null
  certificate_wallet = each.value.wallet != "" ? each.value.wallet : null

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
