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
}

variables {
  name           = "orders-data"
  kms_key_arn    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  access_logging = { target_bucket = "central-logs-111122223333-eu-west-2" }
  partner        = "arn:aws:iam::444455556666:role/analytics"
}

run "an_unknown_name_suffix_is_rejected" {
  command = plan

  variables {
    name_suffix = "region"
  }

  expect_failures = [var.name_suffix]
}

run "acknowledging_a_check_that_does_not_exist_is_rejected" {
  command = plan

  variables {
    acknowledged_checks = ["versioning_is_off"]
  }

  expect_failures = [var.acknowledged_checks]
}

run "a_key_alias_instead_of_a_key_arn_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:alias/orders"
  }

  expect_failures = [var.kms_key_arn]
}

run "an_object_lock_mode_s3_does_not_offer_is_rejected" {
  command = plan

  variables {
    object_lock = { enabled = true, mode = "LEGAL_HOLD", days = 30 }
  }

  expect_failures = [var.object_lock]
}

run "object_lock_retention_in_days_and_years_is_rejected" {
  command = plan

  variables {
    object_lock = { enabled = true, days = 30, years = 1 }
  }

  expect_failures = [var.object_lock]
}

run "an_object_ownership_s3_does_not_offer_is_rejected" {
  command = plan

  variables {
    object_ownership = "BucketOwnerOnly"
  }

  expect_failures = [var.object_ownership]
}

run "a_minimum_tls_below_1_2_is_rejected" {
  command = plan

  variables {
    minimum_tls_version = "1.1"
  }

  expect_failures = [var.minimum_tls_version]
}

run "a_grant_key_that_is_not_a_statement_id_is_rejected" {
  command = plan

  variables {
    grants = {
      "partner-read" = { principals = [var.partner], access = "read" }
    }
  }

  expect_failures = [var.grants]
}

run "a_grant_to_everyone_is_rejected" {
  command = plan

  variables {
    grants = {
      Partner = { principals = ["*"], access = "read" }
    }
  }

  expect_failures = [var.grants]
}

run "an_origin_access_identity_instead_of_a_distribution_is_rejected" {
  command = plan

  variables {
    cloudfront_distribution_arns = ["arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity E2QWRUHAPOMQZL"]
  }

  expect_failures = [var.cloudfront_distribution_arns]
}

run "a_log_source_given_by_name_is_rejected" {
  command = plan

  variables {
    kms_key_arn        = ""
    access_log_sources = ["orders-data-111122223333-eu-west-2"]
  }

  expect_failures = [var.access_log_sources]
}

run "a_vpc_id_instead_of_an_endpoint_id_is_rejected" {
  command = plan

  variables {
    vpc_endpoint_ids = ["vpc-0123456789abcdef0"]
  }

  expect_failures = [var.vpc_endpoint_ids]
}

run "an_account_id_instead_of_an_organization_id_is_rejected" {
  command = plan

  variables {
    organization_id = "111122223333"
  }

  expect_failures = [var.organization_id]
}

run "a_policy_over_20_kb_is_refused" {
  command = plan

  variables {
    grants = {
      Partner = {
        principals = [var.partner]
        access     = "read"
        prefixes   = [for i in range(300) : "tenants/tenant-${format("%04d", i)}/reports/"]
      }
    }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_log_bucket_with_object_lock_is_refused" {
  command = plan

  variables {
    kms_key_arn        = ""
    access_logging     = { enabled = false }
    access_log_sources = ["arn:aws:s3:::orders-data-111122223333-eu-west-2"]
    object_lock        = { enabled = true, days = 30 }
  }

  expect_failures = [aws_s3_bucket.this]
}

run "a_log_bucket_with_requester_pays_is_refused" {
  command = plan

  variables {
    kms_key_arn        = ""
    access_logging     = { enabled = false }
    access_log_sources = ["arn:aws:s3:::orders-data-111122223333-eu-west-2"]
    requester_pays     = true
  }

  expect_failures = [aws_s3_bucket.this]
}

run "more_than_100_newer_noncurrent_versions_is_rejected" {
  command = plan

  variables {
    default_lifecycle = { newer_noncurrent_versions = 101 }
  }

  expect_failures = [var.default_lifecycle]
}

run "a_lifecycle_rule_named_like_the_module_rule_is_rejected" {
  command = plan

  variables {
    lifecycle_rules = {
      "module-defaults" = { expiration_days = 30 }
    }
  }

  expect_failures = [var.lifecycle_rules]
}

run "a_transition_storage_class_s3_does_not_offer_is_rejected" {
  command = plan

  variables {
    lifecycle_rules = {
      archive = { transitions = [{ days = 30, storage_class = "GLACIER_FLEXIBLE_RETRIEVAL" }] }
    }
  }

  expect_failures = [var.lifecycle_rules]
}

run "a_size_filter_that_matches_nothing_is_rejected" {
  command = plan

  variables {
    lifecycle_rules = {
      large = { object_size_greater_than = 1048576, object_size_less_than = 1024, expiration_days = 30 }
    }
  }

  expect_failures = [var.lifecycle_rules]
}

run "an_unknown_transition_minimum_size_is_rejected" {
  command = plan

  variables {
    transition_default_minimum_object_size = "128K"
  }

  expect_failures = [var.transition_default_minimum_object_size]
}

run "an_unknown_log_partition_date_source_is_rejected" {
  command = plan

  variables {
    access_logging = { target_bucket = "central-logs-111122223333-eu-west-2", partition_date_source = "ArrivalTime" }
  }

  expect_failures = [var.access_logging]
}

run "a_log_target_given_as_an_arn_is_rejected" {
  command = plan

  variables {
    access_logging = { target_bucket = "arn:aws:s3:::central-logs-111122223333-eu-west-2" }
  }

  expect_failures = [var.access_logging]
}

run "a_replication_role_that_is_not_a_role_arn_is_rejected" {
  command = plan

  variables {
    replication = { create_role = false, role_arn = "orders-replication" }
  }

  expect_failures = [var.replication]
}

run "a_replication_destination_given_by_name_is_rejected" {
  command = plan

  variables {
    replication = {
      rules = { dr = { destination_bucket_arn = "orders-data-dr", priority = 1 } }
    }
  }

  expect_failures = [var.replication]
}

run "a_notification_event_without_the_s3_prefix_is_rejected" {
  command = plan

  variables {
    notifications = {
      topics = { audit = { arn = "arn:aws:sns:eu-west-2:111122223333:audit", events = ["ObjectCreated:*"] } }
    }
  }

  expect_failures = [var.notifications]
}

run "an_inventory_format_s3_does_not_offer_is_rejected" {
  command = plan

  variables {
    inventory = {
      weekly = { destination_bucket_arn = "arn:aws:s3:::inventory-reports", format = "JSON" }
    }
  }

  expect_failures = [var.inventory]
}

run "a_request_metric_name_with_spaces_is_rejected" {
  command = plan

  variables {
    request_metrics = {
      "whole bucket" = {}
    }
  }

  expect_failures = [var.request_metrics]
}

run "a_cors_method_s3_does_not_offer_is_rejected" {
  command = plan

  variables {
    cors_rules = [{ allowed_methods = ["PATCH"], allowed_origins = ["https://app.example.com"] }]
  }

  expect_failures = [var.cors_rules]
}
