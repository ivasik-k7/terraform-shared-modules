resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.create && length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      id              = cors_rule.value.id != "" ? cors_rule.value.id : null
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      allowed_headers = length(cors_rule.value.allowed_headers) > 0 ? cors_rule.value.allowed_headers : null
      expose_headers  = length(cors_rule.value.expose_headers) > 0 ? cors_rule.value.expose_headers : null
      max_age_seconds = cors_rule.value.max_age_seconds > 0 ? cors_rule.value.max_age_seconds : null
    }
  }
}

resource "aws_s3_bucket_accelerate_configuration" "this" {
  count = local.create && var.transfer_acceleration ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  status = "Enabled"
}

resource "aws_s3_bucket_request_payment_configuration" "this" {
  count = local.create && var.requester_pays ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  payer  = "Requester"
}

resource "aws_s3_bucket_metric" "this" {
  for_each = local.create ? var.request_metrics : {}

  bucket = aws_s3_bucket.this[0].id
  name   = each.key

  dynamic "filter" {
    for_each = each.value.prefix != "" || length(each.value.tags) > 0 ? [1] : []
    content {
      prefix = each.value.prefix != "" ? each.value.prefix : null
      tags   = length(each.value.tags) > 0 ? each.value.tags : null
    }
  }
}

resource "aws_s3_bucket_inventory" "this" {
  for_each = local.create ? var.inventory : {}

  bucket                   = aws_s3_bucket.this[0].id
  name                     = each.key
  enabled                  = each.value.enabled
  included_object_versions = each.value.include_versions
  optional_fields          = each.value.optional_fields

  schedule {
    frequency = each.value.frequency
  }

  dynamic "filter" {
    for_each = each.value.prefix != "" ? [1] : []
    content {
      prefix = each.value.prefix
    }
  }

  destination {
    bucket {
      bucket_arn = each.value.destination_bucket_arn
      account_id = each.value.destination_account_id != "" ? each.value.destination_account_id : null
      prefix     = each.value.destination_prefix != "" ? each.value.destination_prefix : null
      format     = each.value.format

      encryption {
        dynamic "sse_kms" {
          for_each = each.value.destination_kms_key != "" ? [1] : []
          content {
            key_id = each.value.destination_kms_key
          }
        }
        dynamic "sse_s3" {
          for_each = each.value.destination_kms_key == "" ? [1] : []
          content {}
        }
      }
    }
  }
}
