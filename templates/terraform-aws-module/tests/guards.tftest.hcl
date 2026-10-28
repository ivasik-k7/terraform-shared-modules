# Every validation, precondition and check, with the input that trips it.
# expect_failures names the exact address: var.x for a validation, the
# resource for a precondition, check.x for a check.

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
  name        = "/app/orders"
  kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
}

# Validations

run "a_name_under_aws_is_rejected" {
  command = plan

  variables {
    name = "aws/lambda/orders"
  }

  expect_failures = [var.name]
}

run "a_retention_cloudwatch_does_not_offer_is_rejected" {
  command = plan

  variables {
    retention_days = 45
  }

  expect_failures = [var.retention_days]
}

run "an_unknown_log_class_is_rejected" {
  command = plan

  variables {
    log_group_class = "DELIVERY"
  }

  expect_failures = [var.log_group_class]
}

run "a_malformed_key_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/logs"
  }

  expect_failures = [var.kms_key_arn]
}

run "an_unknown_check_name_is_rejected" {
  command = plan

  variables {
    acknowledged_checks = ["no_such_check"]
  }

  expect_failures = [var.acknowledged_checks]
}

# Preconditions

run "a_key_in_another_region_is_refused" {
  command = plan

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  }

  expect_failures = [aws_cloudwatch_log_group.this]
}

# Checks

run "logs_kept_forever_warn" {
  command = plan

  variables {
    retention_days = 0
  }

  expect_failures = [check.log_retention_is_bounded]
}

run "no_customer_key_warns" {
  command = plan

  variables {
    kms_key_arn = ""
  }

  expect_failures = [check.logs_use_a_customer_key]
}
