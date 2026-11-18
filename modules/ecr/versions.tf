terraform {
  # 1.9: validations read other variables, and both operands of || and && are
  # evaluated, so conditions use ternaries.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Tag mutability exclusions (6.8.0), archive lifecycle rules and
      # CREATE_ON_PUSH templates (6.28.0), pull-time update exclusions
      # (6.28.0) and BLOB_MOUNTING (6.29.0) are older than this floor.
      # https://github.com/hashicorp/terraform-provider-aws/blob/v6.57.1/CHANGELOG.md
      version = ">= 6.57.1, < 7.0.0"
    }
  }
}
