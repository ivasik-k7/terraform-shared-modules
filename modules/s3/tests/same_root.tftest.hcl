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

run "resources_created_in_the_same_root_plan" {
  command = plan

  module {
    source = "./tests/fixtures/same-root"
  }

  assert {
    condition     = length(module.bucket.governance.replication) == 1
    error_message = "the bucket, its grant, replication, notifications and inventory plan with unknown ARNs."
  }
  assert {
    condition     = module.raw.governance.access_logged && length(module.raw.governance.replication) == 1
    error_message = "a brought replication role, a log bucket and a queue policy from the same root plan, without a cycle."
  }
}
