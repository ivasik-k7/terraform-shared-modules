# A mocked apply of a fully configured module: the graph assembles end to end
# without credentials, and values known only after apply land where they
# belong. It proves nothing about AWS accepting the requests.

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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/platform-ecr-templates" }
  }
  mock_resource "aws_ecr_repository" {
    defaults = { arn = "arn:aws:ecr:eu-west-2:111122223333:repository/mock", repository_url = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/mock" }
  }
}

run "a_full_configuration_applies" {
  command = apply

  module {
    source = "./examples/complete"
  }

  assert {
    condition     = length(module.ecr.repository_arns) == 4 && length(module.ecr.repository_urls) == 4
    error_message = "every repository is created and reported."
  }

  assert {
    condition     = module.ecr.creation_template_role_arn == "arn:aws:iam::111122223333:role/platform-ecr-templates"
    error_message = "the template role is created and reported."
  }
}
