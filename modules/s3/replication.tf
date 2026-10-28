resource "aws_iam_role" "replication" {
  count = local.create_replication_role ? 1 : 0

  name        = local.replication_role_name
  description = "S3 replication from ${local.bucket_name}"

  # The trust policy S3 documents for replication has no Condition element.
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/setting-repl-config-perm-overview.html
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "S3Replication"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "replication" {
  count = local.create_replication_role ? 1 : 0

  name = "replicate"
  role = aws_iam_role.replication[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [for s in local.replication_statements : merge(
      { Sid = s.sid, Effect = "Allow", Action = s.actions, Resource = s.resources },
      length(s.condition) == 0 ? {} : {
        Condition = { for test in distinct([for c in s.condition : c.test]) : test => {
          for c in s.condition : c.variable => c.values if c.test == test
        } }
      },
    )]
  })
}

resource "aws_s3_bucket_replication_configuration" "this" {
  count = local.create && local.replication_on ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  role   = local.replication_role_arn

  dynamic "rule" {
    for_each = var.replication.rules
    content {
      id       = rule.key
      status   = rule.value.enabled ? "Enabled" : "Disabled"
      priority = rule.value.priority

      filter {
        prefix = length(rule.value.tags) == 0 ? rule.value.prefix : null

        dynamic "tag" {
          for_each = length(rule.value.tags) == 1 && rule.value.prefix == "" ? rule.value.tags : {}
          content {
            key   = tag.key
            value = tag.value
          }
        }

        dynamic "and" {
          for_each = length(rule.value.tags) > 1 || (length(rule.value.tags) == 1 && rule.value.prefix != "") ? [1] : []
          content {
            prefix = rule.value.prefix != "" ? rule.value.prefix : null
            tags   = rule.value.tags
          }
        }
      }

      delete_marker_replication {
        # Delete marker replication isn't supported for tag-based rules.
        # https://docs.aws.amazon.com/AmazonS3/latest/userguide/delete-marker-replication.html
        status = rule.value.delete_markers && length(rule.value.tags) == 0 ? "Enabled" : "Disabled"
      }

      dynamic "source_selection_criteria" {
        for_each = rule.value.replica_kms_key_arn != "" ? [1] : []
        content {
          sse_kms_encrypted_objects {
            status = "Enabled"
          }
        }
      }

      destination {
        bucket        = rule.value.destination_bucket_arn
        storage_class = rule.value.storage_class != "" ? rule.value.storage_class : null

        dynamic "encryption_configuration" {
          for_each = rule.value.replica_kms_key_arn != "" ? [1] : []
          content {
            replica_kms_key_id = rule.value.replica_kms_key_arn
          }
        }

        # 15 is the only valid value for Time and EventThreshold minutes.
        # https://docs.aws.amazon.com/AmazonS3/latest/API/API_ReplicationTimeValue.html
        dynamic "replication_time" {
          for_each = rule.value.replication_time_control ? [1] : []
          content {
            status = "Enabled"
            time {
              minutes = 15
            }
          }
        }

        dynamic "metrics" {
          for_each = rule.value.replication_time_control ? [1] : []
          content {
            status = "Enabled"
            event_threshold {
              minutes = 15
            }
          }
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this, aws_iam_role_policy.replication]
}
