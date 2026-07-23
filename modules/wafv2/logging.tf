# WAF logging to a CloudWatch Logs group (name must start with aws-waf-logs-),
# Kinesis Firehose, or S3 bucket - the destination is created elsewhere and
# referenced by ARN. Redact sensitive fields; optionally filter to cut volume.

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  count = local.create && var.enable_logging ? 1 : 0

  resource_arn            = aws_wafv2_web_acl.this[0].arn
  log_destination_configs = [var.log_destination_arn]

  dynamic "redacted_fields" {
    for_each = var.log_redacted_fields
    content {
      dynamic "uri_path" {
        for_each = redacted_fields.value.type == "uri_path" ? [1] : []
        content {}
      }
      dynamic "query_string" {
        for_each = redacted_fields.value.type == "query_string" ? [1] : []
        content {}
      }
      dynamic "method" {
        for_each = redacted_fields.value.type == "method" ? [1] : []
        content {}
      }
      dynamic "single_header" {
        for_each = redacted_fields.value.type == "single_header" ? [1] : []
        content { name = lower(redacted_fields.value.header_name) }
      }
    }
  }

  dynamic "logging_filter" {
    for_each = var.log_filter != null ? [var.log_filter] : []
    content {
      default_behavior = logging_filter.value.default_behavior
      dynamic "filter" {
        for_each = logging_filter.value.filters
        content {
          behavior    = filter.value.behavior
          requirement = filter.value.requirement
          dynamic "condition" {
            for_each = filter.value.conditions
            content {
              dynamic "action_condition" {
                for_each = condition.value.action_condition != null ? [condition.value.action_condition] : []
                content { action = action_condition.value }
              }
              dynamic "label_name_condition" {
                for_each = condition.value.label_name != null ? [condition.value.label_name] : []
                content { label_name = label_name_condition.value }
              }
            }
          }
        }
      }
    }
  }
}
