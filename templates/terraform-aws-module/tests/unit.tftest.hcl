# Properties of the module, one run each, named for the property. Plan runs
# against a mocked provider: no credentials, no cost. mock_provider does not
# report replacements, so what forces one is documented, not tested here.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # The module reads the region from endpoint (both provider majors have it).
  mock_data "aws_region" {
    defaults = { endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
}

# The baseline is fully configured, so no advisory check fires: terraform test
# fails a run on any check it does not expect.
variables {
  name        = "/app/orders"
  kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags        = { CostCentre = "cc-1234" }
}

run "the_defaults_are_bounded_and_encrypted" {
  command = plan

  assert {
    condition = alltrue([
      aws_cloudwatch_log_group.this[0].name == "/app/orders",
      aws_cloudwatch_log_group.this[0].retention_in_days == 30,
      aws_cloudwatch_log_group.this[0].log_group_class == "STANDARD",
      aws_cloudwatch_log_group.this[0].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555",
      aws_cloudwatch_log_group.this[0].skip_destroy == false,
    ])
    error_message = "30 days of retention, the standard class, the given key, deleted with the module."
  }
}

run "module_tags_are_added_last" {
  command = plan

  variables {
    tags = { CostCentre = "cc-1234", Module = "something-else" }
  }

  assert {
    condition     = jsonencode(aws_cloudwatch_log_group.this[0].tags) == jsonencode({ CostCentre = "cc-1234", ManagedBy = "Terraform", Module = "log-group" })
    error_message = "caller tags are kept, and the module's own keys cannot be overridden."
  }
}

# Assert the invariant (the condition names exactly this group), not the
# shape (a requirement exists).
run "the_key_contract_names_this_log_group" {
  command = plan

  assert {
    condition = alltrue([
      length(output.kms_key_policy_requirements) == 1,
      output.kms_key_policy_requirements[0].principals.services == ["logs.eu-west-2.amazonaws.com"],
      output.kms_key_policy_requirements[0].conditions[0].values == ["arn:aws:logs:eu-west-2:111122223333:log-group:/app/orders"],
    ])
    error_message = "CloudWatch Logs in this region may use the key for this log group only."
  }
}

run "no_key_means_no_key_contract" {
  command = plan

  variables {
    kms_key_arn         = ""
    acknowledged_checks = ["logs_use_a_customer_key"]
  }

  assert {
    condition     = output.kms_key_policy_requirements != null ? false : aws_cloudwatch_log_group.this[0].kms_key_id == null
    error_message = "without a key nothing is sent and nothing is required of a key owner."
  }

  assert {
    condition     = jsonencode(output.governance.acknowledged_checks) == jsonencode(["logs_use_a_customer_key"])
    error_message = "an acknowledged check is recorded in governance."
  }
}

run "infrequent_access_is_read_with_logs_insights" {
  command = plan

  variables {
    log_group_class = "INFREQUENT_ACCESS"
  }

  assert {
    condition     = strcontains(output.verify_commands.read, "start-query")
    error_message = "Infrequent Access has no FilterLogEvents, so the read command uses Logs Insights."
  }
}

run "create_false_plans_nothing_and_outputs_null" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.this) == 0
    error_message = "create = false plans no resource."
  }

  assert {
    condition = alltrue([
      output.name == null, output.arn == null, output.kms_key_policy_requirements == null,
      output.governance == null, output.verify_commands == null,
    ])
    error_message = "create = false leaves every output null."
  }
}
