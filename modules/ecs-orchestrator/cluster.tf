# the cluster. container insights is opt-in (per-metric cost). exec command
# logging is where auditable shell access lands.

resource "aws_ecs_cluster" "this" {
  count = local.create ? 1 : 0

  name = var.cluster_name

  setting {
    name  = "containerInsights"
    value = var.enable_container_insights ? "enabled" : "disabled"
  }

  dynamic "configuration" {
    for_each = var.execute_command_configuration != null ? [var.execute_command_configuration] : []
    content {
      execute_command_configuration {
        kms_key_id = configuration.value.kms_key_id
        logging    = configuration.value.logging

        dynamic "log_configuration" {
          for_each = configuration.value.log_configuration != null ? [configuration.value.log_configuration] : []
          content {
            cloud_watch_encryption_enabled = log_configuration.value.cloud_watch_encryption_enabled
            cloud_watch_log_group_name     = log_configuration.value.cloud_watch_log_group_name
            s3_bucket_name                 = log_configuration.value.s3_bucket_name
            s3_key_prefix                  = log_configuration.value.s3_key_prefix
            s3_bucket_encryption_enabled   = log_configuration.value.s3_bucket_encryption_enabled
          }
        }
      }
    }
  }

  dynamic "service_connect_defaults" {
    for_each = var.service_connect_namespace != null ? [1] : []
    content {
      namespace = var.service_connect_namespace
    }
  }

  tags = merge(local.common_tags, { "Name" = var.cluster_name })
}
