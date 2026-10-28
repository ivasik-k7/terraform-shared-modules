resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.create && local.lifecycle_on ? 1 : 0

  bucket                                 = aws_s3_bucket.this[0].id
  transition_default_minimum_object_size = var.transition_default_minimum_object_size

  dynamic "rule" {
    for_each = local.default_rule_on ? [var.default_lifecycle] : []
    content {
      id     = "module-defaults"
      status = "Enabled"

      filter {}

      dynamic "noncurrent_version_expiration" {
        for_each = var.versioning && rule.value.noncurrent_version_expiration_days > 0 ? [1] : []
        content {
          noncurrent_days           = rule.value.noncurrent_version_expiration_days
          newer_noncurrent_versions = rule.value.newer_noncurrent_versions > 0 ? rule.value.newer_noncurrent_versions : null
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_days > 0 ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_days
        }
      }

      dynamic "expiration" {
        for_each = var.versioning && rule.value.expired_object_delete_marker ? [1] : []
        content {
          expired_object_delete_marker = true
        }
      }
    }
  }

  dynamic "rule" {
    for_each = var.lifecycle_rules
    content {
      id     = rule.key
      status = rule.value.enabled ? "Enabled" : "Disabled"

      # A Filter holds exactly one of Prefix, Tag, ObjectSizeGreaterThan, ObjectSizeLessThan or And.
      # https://docs.aws.amazon.com/AmazonS3/latest/API/API_LifecycleRuleFilter.html
      filter {
        prefix                   = length(rule.value.tags) == 0 && rule.value.object_size_greater_than == 0 && rule.value.object_size_less_than == 0 ? rule.value.prefix : null
        object_size_greater_than = length(rule.value.tags) == 0 && rule.value.prefix == "" && rule.value.object_size_less_than == 0 && rule.value.object_size_greater_than > 0 ? rule.value.object_size_greater_than : null
        object_size_less_than    = length(rule.value.tags) == 0 && rule.value.prefix == "" && rule.value.object_size_greater_than == 0 && rule.value.object_size_less_than > 0 ? rule.value.object_size_less_than : null

        dynamic "tag" {
          for_each = length(rule.value.tags) == 1 && rule.value.prefix == "" && rule.value.object_size_greater_than == 0 && rule.value.object_size_less_than == 0 ? rule.value.tags : {}
          content {
            key   = tag.key
            value = tag.value
          }
        }

        dynamic "and" {
          for_each = local.lifecycle_filter_count[rule.key] > 1 ? [1] : []
          content {
            prefix                   = rule.value.prefix != "" ? rule.value.prefix : null
            tags                     = length(rule.value.tags) > 0 ? rule.value.tags : null
            object_size_greater_than = rule.value.object_size_greater_than > 0 ? rule.value.object_size_greater_than : null
            object_size_less_than    = rule.value.object_size_less_than > 0 ? rule.value.object_size_less_than : null
          }
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days > 0 ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_transitions
        content {
          noncurrent_days           = noncurrent_version_transition.value.days
          storage_class             = noncurrent_version_transition.value.storage_class
          newer_noncurrent_versions = noncurrent_version_transition.value.newer_versions > 0 ? noncurrent_version_transition.value.newer_versions : null
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days > 0 ? [1] : []
        content {
          noncurrent_days           = rule.value.noncurrent_expiration_days
          newer_noncurrent_versions = rule.value.noncurrent_newer_versions > 0 ? rule.value.noncurrent_newer_versions : null
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  for_each = local.create ? var.intelligent_tiering : {}

  bucket = aws_s3_bucket.this[0].id
  name   = each.key
  status = each.value.enabled ? "Enabled" : "Disabled"

  dynamic "filter" {
    for_each = each.value.prefix != "" || length(each.value.tags) > 0 ? [1] : []
    content {
      prefix = each.value.prefix != "" ? each.value.prefix : null
      tags   = length(each.value.tags) > 0 ? each.value.tags : null
    }
  }

  dynamic "tiering" {
    for_each = each.value.archive_days > 0 ? [1] : []
    content {
      access_tier = "ARCHIVE_ACCESS"
      days        = each.value.archive_days
    }
  }

  dynamic "tiering" {
    for_each = each.value.deep_archive_days > 0 ? [1] : []
    content {
      access_tier = "DEEP_ARCHIVE_ACCESS"
      days        = each.value.deep_archive_days
    }
  }
}
