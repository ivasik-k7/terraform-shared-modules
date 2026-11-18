terraform {
  # 1.9: validations read other variables, and both operands of || and && are
  # evaluated, so conditions use ternaries.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Native blue/green, linear and canary deployments (6.21.0), sigint_rollback
      # (6.11.0), Service Connect access logs (6.34.0) and Managed Instances
      # capacity providers (6.15.0) are older than this floor.
      # https://github.com/hashicorp/terraform-provider-aws/blob/v6.57.1/CHANGELOG.md
      version = ">= 6.57.1, < 7.0.0"
    }
  }
}
