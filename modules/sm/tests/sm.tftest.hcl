# Plan-stage tests for the Secrets Manager module: input validations and
# value-resolution logic (paths, tags, value modes, KMS/recovery resolution).
# Run with: terraform test

mock_provider "aws" {
  # Secret policies consume aws_iam_policy_document.json; give the mock valid JSON.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

###############################################################################
# Input validations
###############################################################################

run "reject_trailing_slash_prefix" {
  command = plan
  variables { name_prefix = "acme/platform/" }
  expect_failures = [var.name_prefix]
}

run "reject_too_long_prefix" {
  command = plan
  variables { name_prefix = join("", [for _ in range(201) : "x"]) }
  expect_failures = [var.name_prefix]
}

run "reject_uppercase_environment" {
  command = plan
  variables { environment = "Prod" }
  expect_failures = [var.environment]
}

run "reject_multiple_value_modes" {
  command = plan
  variables {
    secrets = {
      db = { secret_string = "x", secret_key_value = { a = "b" } }
    }
  }
  expect_failures = [var.secrets]
}

run "reject_bad_per_secret_recovery_window" {
  command = plan
  variables {
    secrets = {
      db = { secret_string = "x", recovery_window_in_days = 3 }
    }
  }
  expect_failures = [var.secrets]
}

run "reject_bad_default_recovery_window" {
  command = plan
  variables { default_recovery_window_in_days = 5 }
  expect_failures = [var.default_recovery_window_in_days]
}

run "accept_force_delete_recovery_window" {
  command = plan
  variables {
    secrets = {
      db = { secret_string = "x", recovery_window_in_days = 0 }
    }
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["db"].recovery_window_in_days == 0
    error_message = "recovery_window_in_days = 0 (force delete) should be accepted"
  }
}

###############################################################################
# Path composition
###############################################################################

run "path_prefix_env_key" {
  command = plan
  variables {
    name_prefix = "acme/platform"
    environment = "dev"
    secrets     = { db = { secret_string = "x" } }
  }
  assert {
    condition     = output.resolved_paths["db"] == "acme/platform/dev/db"
    error_message = "full path should be <prefix>/<env>/<key>"
  }
}

run "path_env_key_only" {
  command = plan
  variables {
    environment = "staging"
    secrets     = { db = { secret_string = "x" } }
  }
  assert {
    condition     = output.resolved_paths["db"] == "staging/db"
    error_message = "empty prefix should be omitted from the path"
  }
}

run "path_key_only" {
  command = plan
  variables {
    secrets = { db = { secret_string = "x" } }
  }
  assert {
    condition     = output.resolved_paths["db"] == "db"
    error_message = "empty prefix and env should leave just the key"
  }
}

###############################################################################
# Tags
###############################################################################

run "tags_merge_and_precedence" {
  command = plan
  variables {
    environment  = "dev"
    default_tags = { team = "core", owner = "platform" }
    secrets = {
      db = { secret_string = "x", tags = { owner = "payments" } }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.managed["db"].tags["managed-by"] == "terraform"
    error_message = "managed-by tag should be injected"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["db"].tags["environment"] == "dev"
    error_message = "environment tag should be injected"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["db"].tags["team"] == "core"
    error_message = "default_tags should be merged"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["db"].tags["owner"] == "payments"
    error_message = "per-secret tags should take precedence over default_tags"
  }
}

run "empty_environment_omits_tag" {
  command = plan
  variables {
    secrets = { db = { secret_string = "x" } }
  }
  assert {
    condition     = !contains(keys(aws_secretsmanager_secret.managed["db"].tags), "environment")
    error_message = "environment tag should be omitted when environment is empty"
  }
}

###############################################################################
# Value modes
###############################################################################

run "value_key_value_serialized_to_json" {
  command = plan
  variables {
    secrets = {
      db = { secret_key_value = { username = "admin", password = "p@ss" } }
    }
  }
  assert {
    condition     = aws_secretsmanager_secret_version.managed["db"].secret_string == jsonencode({ username = "admin", password = "p@ss" })
    error_message = "secret_key_value should be JSON-encoded into secret_string"
  }
}

run "value_string_passthrough" {
  command = plan
  variables {
    secrets = {
      db = { secret_string = "raw-value" }
    }
  }
  assert {
    condition     = aws_secretsmanager_secret_version.managed["db"].secret_string == "raw-value"
    error_message = "secret_string should pass through unchanged"
  }
}

###############################################################################
# KMS + recovery window resolution
###############################################################################

run "kms_and_recovery_resolution" {
  command = plan
  variables {
    default_kms_key_id              = "arn:aws:kms:us-east-1:123456789012:key/default"
    default_recovery_window_in_days = 14
    secrets = {
      inherits = { secret_string = "x" }
      override = {
        secret_string           = "y"
        kms_key_id              = "arn:aws:kms:us-east-1:123456789012:key/custom"
        recovery_window_in_days = 7
      }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret.managed["inherits"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/default"
    error_message = "secret without kms_key_id should inherit default_kms_key_id"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["override"].kms_key_id == "arn:aws:kms:us-east-1:123456789012:key/custom"
    error_message = "per-secret kms_key_id should win"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["inherits"].recovery_window_in_days == 14
    error_message = "secret should inherit default_recovery_window_in_days"
  }
  assert {
    condition     = aws_secretsmanager_secret.managed["override"].recovery_window_in_days == 7
    error_message = "per-secret recovery_window_in_days should win"
  }
}
