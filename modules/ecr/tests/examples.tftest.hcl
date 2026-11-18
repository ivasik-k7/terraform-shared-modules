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
}

run "basic_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  assert {
    condition     = length(module.ecr.kms_key_policy_requirements) == 1
    error_message = "the basic example's key gets its one contract entry."
  }
}

run "complete_plans_with_every_contract" {
  command = plan

  module {
    source = "./examples/complete"
  }

  assert {
    condition = alltrue([
      module.ecr.governance.registry_managed_here,
      length(module.ecr.governance.pull_through_cache) == 3,
      module.ecr.governance.cache_templates == { "docker-hub" = "docker-hub", "ecr-public" = "ROOT", "shared" = "ROOT" },
      length(keys(module.ecr.replication_destination_requirements)) == 1,
      module.ecr.notification_requirements != null,
    ])
    error_message = "the complete example manages the registry, templates every cache, and hands every contract to its owner."
  }
}
