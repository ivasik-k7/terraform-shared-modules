terraform {
  # >= 1.9.0: several validations reference other variables
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # WAFv2 CLOUDFRONT scope is only available in us-east-1: the caller must
      # pass a provider aliased to us-east-1 (see the example).
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}
