terraform {
  # 1.9: validations read other variables, and both operands of || and && are
  # evaluated, so conditions use ternaries.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.57.1 is the first release with instance_lifecycle_policy and the
      # reservations-then-balanced AZ distribution this module sends.
      version = ">= 6.57.1, < 7.0.0"
    }
  }
}
