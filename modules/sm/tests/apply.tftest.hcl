# Apply-stage tests (mocked provider) for the Secrets Manager module: verifies
# the full resource graph — managed/unmanaged split, placeholders, binary,
# rotation, replicas, and resource policies — plus output structure.
# Run with: terraform test

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
  # The secret_arn feeds aws_secretsmanager_secret_policy, which validates ARN
  # format — so the mocked computed arn must be a well-formed ARN.
  mock_resource "aws_secretsmanager_secret" {
    defaults = {
      arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:mock-aBcDeF"
    }
  }
}

run "managed_vs_unmanaged_split" {
  command = apply

  variables {
    secrets = {
      app    = { secret_string = "x" }
      legacy = { secret_string = "y", ignore_secret_changes = true }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.managed) == 1 && length(aws_secretsmanager_secret.unmanaged) == 1
    error_message = "ignore_secret_changes should route the secret to the unmanaged resource"
  }
  assert {
    condition     = length(aws_secretsmanager_secret_version.managed) == 1 && length(aws_secretsmanager_secret_version.unmanaged) == 1
    error_message = "each secret with a value should get a version under the matching resource"
  }
  assert {
    condition     = length(output.secret_arns) == 2
    error_message = "both secrets should appear in outputs regardless of managed/unmanaged"
  }
}

run "placeholder_creates_no_version" {
  command = apply

  variables {
    secrets = {
      injected = {} # no value mode -> placeholder, value supplied out-of-band
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.managed) == 1
    error_message = "placeholder secret should still be created"
  }
  assert {
    condition     = length(aws_secretsmanager_secret_version.managed) == 0
    error_message = "placeholder secret should not create a version"
  }
}

run "binary_value" {
  command = apply

  variables {
    secrets = {
      cert = { secret_binary = base64encode("certificate-bytes") }
    }
  }

  assert {
    condition     = aws_secretsmanager_secret_version.managed["cert"].secret_binary == base64encode("certificate-bytes")
    error_message = "secret_binary should be set on the version"
  }
  assert {
    condition     = aws_secretsmanager_secret_version.managed["cert"].secret_string == null
    error_message = "secret_string should be null for a binary secret"
  }
}

run "rotation_configured" {
  command = apply

  variables {
    secrets = {
      rotated = {
        secret_string = "x"
        rotation = {
          lambda_arn               = "arn:aws:lambda:us-east-1:123456789012:function:rotate"
          automatically_after_days = 15
        }
      }
      static = { secret_string = "y" }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_rotation.this) == 1
    error_message = "only the secret with a rotation block should get a rotation resource"
  }
  assert {
    condition     = output.rotation_enabled["rotated"] == true
    error_message = "rotation_enabled should be true for the rotated secret"
  }
  assert {
    condition     = output.rotation_enabled["static"] == false
    error_message = "rotation_enabled should be false for the static secret"
  }
  assert {
    condition     = aws_secretsmanager_secret_rotation.this["rotated"].rotation_rules[0].automatically_after_days == 15
    error_message = "rotation interval should be passed through"
  }
}

run "replica_regions" {
  command = apply

  variables {
    secrets = {
      global = {
        secret_string = "x"
        replica_regions = [
          { region = "us-west-2" },
          { region = "eu-west-1", kms_key_id = "arn:aws:kms:eu-west-1:123456789012:key/eu" },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret.managed["global"].replica) == 2
    error_message = "both replica regions should be configured"
  }
}

run "per_secret_policy_only" {
  command = apply

  variables {
    secrets = {
      open = { secret_string = "x" }
      restricted = {
        secret_string = "y"
        policy        = { reader_arns = ["arn:aws:iam::123456789012:role/app"] }
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 1
    error_message = "only the secret with a policy block should get a resource policy"
  }
}

run "module_wide_policy_applies_to_all" {
  command = apply

  variables {
    reader_arns = ["arn:aws:iam::123456789012:role/reader"]
    secrets = {
      a = { secret_string = "x" }
      b = { secret_string = "y" }
      c = { secret_string = "z" }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 3
    error_message = "module-wide reader_arns should attach a policy to every secret"
  }
}

run "additional_policy_statements" {
  command = apply

  variables {
    secrets = {
      shared = {
        secret_string = "x"
        policy = {
          additional_statements = [{
            sid        = "DenyInsecureTransport"
            effect     = "Deny"
            actions    = ["secretsmanager:*"]
            principals = [{ type = "AWS", identifiers = ["*"] }]
            conditions = [{
              test     = "Bool"
              variable = "aws:SecureTransport"
              values   = ["false"]
            }]
          }]
        }
      }
    }
  }

  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 1
    error_message = "a secret with additional_statements should get a resource policy"
  }
}

run "comprehensive_mixed_workload" {
  command = apply

  variables {
    name_prefix        = "acme/platform"
    environment        = "prod"
    default_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/default"
    reader_arns        = ["arn:aws:iam::123456789012:role/app"]

    secrets = {
      db_creds      = { secret_key_value = { username = "admin", password = "p" } }
      api_key       = { secret_string = "abc123" }
      tls_cert      = { secret_binary = base64encode("cert") }
      injected_only = {}
      legacy = {
        secret_string         = "old"
        ignore_secret_changes = true
      }
    }
  }

  assert {
    condition     = length(output.secret_arns) == 5
    error_message = "all five secrets should be created"
  }
  assert {
    condition     = output.resolved_paths["db_creds"] == "acme/platform/prod/db_creds"
    error_message = "paths should compose with prefix and environment"
  }
  # 4 have values (db_creds, api_key, tls_cert, legacy); injected_only is a placeholder.
  assert {
    condition     = length(aws_secretsmanager_secret_version.managed) + length(aws_secretsmanager_secret_version.unmanaged) == 4
    error_message = "only secrets with values should have versions"
  }
  # reader_arns is module-wide, so every secret gets a policy.
  assert {
    condition     = length(aws_secretsmanager_secret_policy.this) == 5
    error_message = "module-wide reader_arns should attach a policy to every secret"
  }
}
