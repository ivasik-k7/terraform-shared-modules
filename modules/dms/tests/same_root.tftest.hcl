mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { name = "eu-west-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_iam_roles" {
    defaults = { names = ["dms-vpc-role", "dms-cloudwatch-logs-role"] }
  }
}

run "secrets_roles_and_a_topic_created_in_the_same_root_plan" {
  command = plan

  module {
    source = "./tests/fixtures/same-root"
  }

  assert {
    condition     = toset(keys(module.dms.endpoint_secret_role_arns)) == toset(["source-db", "target-db"]) && toset(keys(module.dms.s3_target_role_arns)) == toset(["lake", "archive"])
    error_message = "every secret endpoint and S3 target has a role entry, created or brought."
  }
}
