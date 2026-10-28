locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  is_log_bucket           = length(var.access_log_sources) > 0
  replication_without_rtc = [for k, r in var.replication.rules : k if !r.replication_time_control]
}

check "versioning_is_on" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "versioning_is_on") ? true : var.versioning)
    error_message = "versioning is off: an overwrite or a delete loses the object for good. ${local.ack_hint}"
  }
}

check "old_versions_expire" {
  assert {
    condition = !local.create ? true : (contains(local.acknowledged, "old_versions_expire") ? true : (
      !var.versioning ? true : (
        var.default_lifecycle.noncurrent_version_expiration_days > 0 ? true : anytrue([for r in values(var.lifecycle_rules) : r.noncurrent_expiration_days > 0])
      )
    ))
    error_message = "versioning is on and no rule expires noncurrent versions: every overwritten or deleted object is kept, and billed, forever. Set default_lifecycle.noncurrent_version_expiration_days. ${local.ack_hint}"
  }
}

check "access_is_logged" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "access_is_logged") ? true : (local.is_log_bucket ? true : var.access_logging.enabled))
    error_message = "server access logging is off: who read or wrote an object is recorded only if CloudTrail data events are on. Set access_logging.target_bucket. ${local.ack_hint}"
  }
}

check "data_uses_a_customer_key" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "data_uses_a_customer_key") ? true : (local.is_log_bucket ? true : local.uses_kms))
    error_message = "the bucket uses SSE-S3: access cannot be revoked by key policy, and key usage is not in CloudTrail. Set kms_key_arn. ${local.ack_hint}"
  }
}

check "the_bucket_survives_a_destroy" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "the_bucket_survives_a_destroy") ? true : !var.force_destroy)
    error_message = "force_destroy is on: terraform destroy, or a plan that replaces the bucket, deletes every object and version in it. ${local.ack_hint}"
  }
}

check "acls_are_disabled" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "acls_are_disabled") ? true : var.object_ownership == "BucketOwnerEnforced")
    error_message = "object_ownership ${var.object_ownership} re-enables ACLs: access is no longer described by the bucket policy alone. ${local.ack_hint}"
  }
}

check "replication_is_monitored" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "replication_is_monitored") ? true : length(local.replication_without_rtc) == 0)
    error_message = "replication rules without replication_time_control have no replication metrics: a stalled replication is not seen. Rules: ${join(", ", local.replication_without_rtc)}. ${local.ack_hint}"
  }
}
