# Every example plans without a warning it does not acknowledge: examples are
# what readers copy, so a broken one is a broken build.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0fedcba9876543210" }
  }
}

run "basic_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  assert {
    condition     = output.network_contract.session_manager_interface_endpoints[0] == "com.amazonaws.eu-west-2.ssm"
    error_message = "the smallest call hands the network team the Session Manager endpoints."
  }
}

run "complete_plans_with_every_contract" {
  command = plan

  module {
    source = "./examples/complete"
  }

  assert {
    condition     = length(output.kms_key_policy_requirements) == 3 && output.notification_requirements != null && output.deployer_requirements != null
    error_message = "the complete example hands the volume key, the topic key and the deployer contracts to their owners."
  }

  assert {
    condition     = jsonencode(output.governance.initial_lifecycle_hooks) == jsonencode(["register"])
    error_message = "the complete example shows an initial hook, and governance names it."
  }
}

run "ecs_capacity_plans" {
  command = plan

  module {
    source = "./examples/ecs-capacity"
  }

  assert {
    condition     = length(output.kms_key_policy_requirements) == 2
    error_message = "the ECS capacity example asks the volume key owner for the service-linked role's grants."
  }
}
