# Every example plans without a warning it does not acknowledge: examples are
# what readers copy, so a broken one is a broken build.

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

run "basic_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }
}

run "complete_plans_with_its_key_contract" {
  command = plan

  module {
    source = "./examples/complete"
  }

  variables {
    kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  }

  assert {
    condition     = length(module.logs.kms_key_policy_requirements) == 1
    error_message = "the complete example hands the key owner one requirement."
  }
}
