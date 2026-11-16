terraform {
  # 1.9: validations read other variables, and both operands of || and && are
  # evaluated, so conditions use ternaries.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The floor is the 5.x release CI tests. Arguments only 6.x has (native
      # blue/green, sigint_rollback, S3 Files volumes) are not used.
      version = ">= 5.100.0, < 7.0.0"
    }
  }
}
