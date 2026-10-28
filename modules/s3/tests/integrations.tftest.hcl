mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/orders-data-eu-west-2-s3-replication" }
  }
}

variables {
  name           = "orders-data"
  kms_key_arn    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  access_logging = { target_bucket = "central-logs-111122223333-eu-west-2" }
  dr_key         = "arn:aws:kms:eu-west-1:111122223333:key/22222222-2222-3333-4444-555555555555"
}

run "the_default_rule_bounds_what_grows_unseen" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].id == "module-defaults",
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].noncurrent_version_expiration[0].noncurrent_days == 90,
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].abort_incomplete_multipart_upload[0].days_after_initiation == 7,
      aws_s3_bucket_lifecycle_configuration.this[0].rule[0].expiration[0].expired_object_delete_marker == true,
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule[0].filter) == 1,
    ])
    error_message = "old versions expire after 90 days, abandoned uploads after 7, orphan delete markers go, and the rule has the filter element S3 needs."
  }
}

run "no_expiry_of_old_versions_warns" {
  command = plan

  variables {
    default_lifecycle = { noncurrent_version_expiration_days = 0 }
  }

  expect_failures = [check.old_versions_expire]
}

run "a_caller_rule_filters_and_transitions" {
  command = plan

  variables {
    lifecycle_rules = {
      archive-exports = {
        prefix      = "exports/"
        tags        = { class = "archive" }
        transitions = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 180, storage_class = "DEEP_ARCHIVE" }]
      }
      tmp = {
        prefix          = "tmp/"
        expiration_days = 7
      }
    }
  }

  assert {
    condition = alltrue([
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule) == 3,
      aws_s3_bucket_lifecycle_configuration.this[0].rule[1].filter[0].and[0].prefix == "exports/",
      aws_s3_bucket_lifecycle_configuration.this[0].rule[1].filter[0].and[0].tags["class"] == "archive",
      length(aws_s3_bucket_lifecycle_configuration.this[0].rule[1].transition) == 2,
      aws_s3_bucket_lifecycle_configuration.this[0].rule[2].filter[0].prefix == "tmp/",
      aws_s3_bucket_lifecycle_configuration.this[0].rule[2].expiration[0].days == 7,
      aws_s3_bucket_lifecycle_configuration.this[0].transition_default_minimum_object_size == "all_storage_classes_128K",
    ])
    error_message = "a prefix with a tag goes under and; a lone prefix stands alone; small objects are not transitioned."
  }
}

run "a_rule_that_does_nothing_is_rejected" {
  command = plan

  variables {
    lifecycle_rules = { noop = { prefix = "x/" } }
  }

  expect_failures = [var.lifecycle_rules]
}

run "intelligent_tiering_archives_on_request" {
  command = plan

  variables {
    intelligent_tiering = { cold = { archive_days = 90, deep_archive_days = 180 } }
  }

  assert {
    condition     = length(aws_s3_bucket_intelligent_tiering_configuration.this["cold"].tiering) == 2
    error_message = "both archive tiers configured."
  }
}

run "deep_archive_before_archive_is_rejected" {
  command = plan

  variables {
    intelligent_tiering = { cold = { archive_days = 200, deep_archive_days = 180 } }
  }

  expect_failures = [var.intelligent_tiering]
}

run "replication_gets_a_scoped_role_and_kms_replicas" {
  command = apply

  variables {
    replication = {
      rules = {
        dr = {
          destination_bucket_arn   = "arn:aws:s3:::orders-dr-111122223333-eu-west-1"
          replica_kms_key_arn      = var.dr_key
          replication_time_control = true
          priority                 = 1
        }
      }
    }
  }

  assert {
    condition = alltrue([
      aws_iam_role.replication[0].name == "orders-data-eu-west-2-s3-replication",
      jsondecode(aws_iam_role.replication[0].assume_role_policy).Statement[0].Principal.Service == "s3.amazonaws.com",
      anytrue([for st in jsondecode(aws_iam_role_policy.replication[0].policy).Statement : st.Sid == "ReplicateToDestinations" ? jsonencode(st.Resource) == jsonencode(["arn:aws:s3:::orders-dr-111122223333-eu-west-1/*"]) : false]),
      anytrue([for st in jsondecode(aws_iam_role_policy.replication[0].policy).Statement : st.Sid == "DecryptSourceObjects" ? st.Condition.StringLike["kms:ViaService"] == ["s3.eu-west-2.amazonaws.com"] : false]),
      anytrue([for st in jsondecode(aws_iam_role_policy.replication[0].policy).Statement : startswith(st.Sid, "EncryptReplicas") ? st.Condition.StringLike["kms:ViaService"] == ["s3.eu-west-1.amazonaws.com"] : false]),
    ])
    error_message = "the role reads this bucket, writes the destination, decrypts through S3 here and encrypts through S3 in the destination's region."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_replication_configuration.this[0].rule[0].source_selection_criteria[0].sse_kms_encrypted_objects[0].status == "Enabled",
      aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].encryption_configuration[0].replica_kms_key_id == var.dr_key,
      aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].replication_time[0].time[0].minutes == 15,
      aws_s3_bucket_replication_configuration.this[0].rule[0].destination[0].metrics[0].event_threshold[0].minutes == 15,
      aws_s3_bucket_replication_configuration.this[0].rule[0].delete_marker_replication[0].status == "Enabled",
    ])
    error_message = "SSE-KMS objects replicate under the replica key, with RTC at its only value, and delete markers."
  }

  assert {
    condition     = can(jsondecode(output.replication_destination_requirements["arn:aws:s3:::orders-dr-111122223333-eu-west-1"].bucket_policy_statements))
    error_message = "the destination owner is told what to add."
  }
}

run "a_brought_replication_role_needs_create_role_false" {
  command = plan

  variables {
    replication = {
      role_arn = "arn:aws:iam::111122223333:role/replication"
      rules    = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr-111122223333-eu-west-1", replica_kms_key_arn = var.dr_key } }
    }
  }

  expect_failures = [var.replication]
}

run "a_brought_replication_role_is_used_and_none_is_created" {
  command = plan

  variables {
    replication = {
      create_role = false
      role_arn    = "arn:aws:iam::111122223333:role/replication"
      rules       = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr-111122223333-eu-west-1", replica_kms_key_arn = var.dr_key, replication_time_control = true } }
    }
  }

  assert {
    condition     = length(aws_iam_role.replication) != 0 ? false : aws_s3_bucket_replication_configuration.this[0].role == "arn:aws:iam::111122223333:role/replication"
    error_message = "the brought role replicates, and no second role is created."
  }
}

run "the_replication_role_arn_is_known_at_plan" {
  command = plan

  variables {
    replication = { rules = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr-111122223333-eu-west-1", replica_kms_key_arn = var.dr_key, replication_time_control = true } } }
  }

  assert {
    condition     = output.replication_role_arn == "arn:aws:iam::111122223333:role/orders-data-eu-west-2-s3-replication"
    error_message = "the role ARN is built from its name, so the destination contracts are known at plan."
  }
}

run "logging_switched_on_without_a_target_is_rejected" {
  command = plan

  variables {
    access_logging = {}
  }

  expect_failures = [var.access_logging]
}

run "kms_objects_without_a_replica_key_are_refused" {
  command = plan

  variables {
    acknowledged_checks = ["replication_is_monitored"]
    replication         = { rules = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr" } } }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "replication_without_versioning_is_refused" {
  command = plan

  variables {
    versioning          = false
    acknowledged_checks = ["versioning_is_on", "replication_is_monitored"]
    replication         = { rules = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr", replica_kms_key_arn = var.dr_key } } }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "replication_without_rtc_warns" {
  command = plan

  variables {
    replication = { rules = { dr = { destination_bucket_arn = "arn:aws:s3:::orders-dr", replica_kms_key_arn = var.dr_key } } }
  }

  expect_failures = [check.replication_is_monitored]
}

run "tag_filtered_rules_do_not_replicate_delete_markers" {
  command = plan

  variables {
    acknowledged_checks = ["replication_is_monitored"]
    replication         = { rules = { tagged = { destination_bucket_arn = "arn:aws:s3:::orders-dr", replica_kms_key_arn = var.dr_key, tags = { replicate = "yes" } } } }
  }

  assert {
    condition     = aws_s3_bucket_replication_configuration.this[0].rule[0].delete_marker_replication[0].status == "Disabled"
    error_message = "S3 replicates delete markers only for rules without a tag filter."
  }
}

run "duplicate_replication_priorities_are_rejected" {
  command = plan

  variables {
    replication = { rules = {
      a = { destination_bucket_arn = "arn:aws:s3:::dr-a", replica_kms_key_arn = var.dr_key }
      b = { destination_bucket_arn = "arn:aws:s3:::dr-b", replica_kms_key_arn = var.dr_key }
    } }
  }

  expect_failures = [var.replication]
}

run "access_logs_are_partitioned_under_the_bucket_name" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_logging.this[0].target_prefix == "orders-data-111122223333-eu-west-2/",
      aws_s3_bucket_logging.this[0].target_object_key_format[0].partitioned_prefix[0].partition_date_source == "EventTime",
    ])
    error_message = "logs go under the bucket's own folder, partitioned by event time."
  }
}

run "logging_into_itself_is_refused" {
  command = plan

  variables {
    access_logging = { target_bucket = "orders-data-111122223333-eu-west-2" }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_log_bucket_admits_its_sources_and_uses_sse_s3" {
  command = plan

  variables {
    name               = "central-logs"
    kms_key_arn        = ""
    access_logging     = { enabled = false }
    access_log_sources = ["arn:aws:s3:::orders-data-111122223333-eu-west-2"]
  }

  assert {
    condition = anytrue([for st in jsondecode(aws_s3_bucket_policy.this[0].policy).Statement :
      st.Sid != "ServerAccessLogDelivery" ? false : (
        st.Principal.Service != ["logging.s3.amazonaws.com"] ? false : (
          st.Condition.ArnLike["aws:SourceArn"] != ["arn:aws:s3:::orders-data-111122223333-eu-west-2"] ? false :
          st.Condition.StringEquals["aws:SourceAccount"] == ["111122223333"]
        )
      )
    ])
    error_message = "the logging service may write for those sources from this account; a log bucket is exempt from the logging and key checks."
  }
}

run "a_log_bucket_with_a_customer_key_is_refused" {
  command = plan

  variables {
    access_logging     = { enabled = false }
    access_log_sources = ["arn:aws:s3:::orders-data-111122223333-eu-west-2"]
  }

  expect_failures = [aws_s3_bucket.this]
}

run "no_access_logging_warns" {
  command = plan

  variables {
    access_logging = { enabled = false }
  }

  expect_failures = [check.access_is_logged]
}

run "notifications_go_to_eventbridge_and_a_queue" {
  command = plan

  variables {
    notifications = {
      eventbridge = true
      queues      = { ingest = { arn = "arn:aws:sqs:eu-west-2:111122223333:ingest", events = ["s3:ObjectCreated:*"], prefix = "incoming/" } }
    }
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_notification.this[0].eventbridge == true,
      aws_s3_bucket_notification.this[0].queue[0].filter_prefix == "incoming/",
      jsondecode(output.notification_destination_requirements.queues["ingest"]).Condition.ArnEquals["aws:SourceArn"] == "arn:aws:s3:::orders-data-111122223333-eu-west-2",
    ])
    error_message = "one notification resource, and the queue owner is told the statement S3 needs."
  }
}

run "a_fifo_queue_destination_is_rejected" {
  command = plan

  variables {
    notifications = { queues = { ingest = { arn = "arn:aws:sqs:eu-west-2:111122223333:ingest.fifo", events = ["s3:ObjectCreated:*"] } } }
  }

  expect_failures = [var.notifications]
}

run "inventory_reports_are_encrypted_explicitly" {
  command = plan

  variables {
    inventory = { weekly = { destination_bucket_arn = "arn:aws:s3:::inventory-reports" } }
  }

  assert {
    condition = alltrue([
      length(aws_s3_bucket_inventory.this["weekly"].destination[0].bucket[0].encryption[0].sse_s3) == 1,
      aws_s3_bucket_inventory.this["weekly"].destination[0].bucket[0].format == "Parquet",
      jsondecode(output.inventory_destination_requirements["weekly"].bucket_policy_statement).Condition.StringEquals["s3:x-amz-acl"] == "bucket-owner-full-control",
    ])
    error_message = "reports are encrypted explicitly (not by the destination's default key), and the destination is told its policy."
  }
}

run "the_small_features_are_off_unless_asked" {
  command = plan

  assert {
    condition = alltrue([
      length(aws_s3_bucket_cors_configuration.this) == 0,
      length(aws_s3_bucket_accelerate_configuration.this) == 0,
      length(aws_s3_bucket_request_payment_configuration.this) == 0,
      length(aws_s3_bucket_metric.this) == 0,
      length(aws_s3_bucket_notification.this) == 0,
      length(aws_s3_bucket_replication_configuration.this) == 0,
    ])
    error_message = "nothing billable or behaviour-changing is on by default."
  }
}

run "features_are_configured_when_asked" {
  command = plan

  variables {
    cors_rules            = [{ allowed_methods = ["GET"], allowed_origins = ["https://app.example.com"], max_age_seconds = 3600 }]
    transfer_acceleration = true
    request_metrics       = { all = {} }
  }

  assert {
    condition = alltrue([
      length(aws_s3_bucket_cors_configuration.this[0].cors_rule) == 1,
      aws_s3_bucket_accelerate_configuration.this[0].status == "Enabled",
      length(aws_s3_bucket_metric.this["all"].filter) == 0,
    ])
    error_message = "CORS, acceleration and a whole-bucket request metric."
  }
}
