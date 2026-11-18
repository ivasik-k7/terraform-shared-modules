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
  mock_data "aws_ebs_encryption_by_default" {
    defaults = { enabled = true }
  }
}

run "basic_plans" {
  command = plan

  module {
    source = "./examples/basic"
  }

  assert {
    condition     = contains(module.ecs.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ecr.dkr")
    error_message = "an ECR image needs the ecr.dkr endpoint in the network contract."
  }
}

run "complete_plans_with_every_contract" {
  command = plan

  module {
    source = "./examples/complete"
  }

  assert {
    condition     = length(module.ecs.kms_key_policy_requirements) > 0 && module.ecs.notification_requirements != null && module.ecs.deployer_requirements != null
    error_message = "the complete example hands every contract to its owner."
  }

  assert {
    condition     = module.ecs.governance.workloads == { api = "service", worker = "service", reconcile = "scheduled", migrate = "task", search = "service", renderer = "service", shipper = "daemon" }
    error_message = "the complete example covers every workload kind."
  }

  assert {
    condition     = module.ecs.governance.deployment_strategies.api == "CANARY" && module.ecs.governance.managed_instances == { compute = "ON_DEMAND" }
    error_message = "the complete example shows a canary release and a Managed Instances provider."
  }
}
