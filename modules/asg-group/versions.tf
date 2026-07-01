terraform {
  # >= 1.9.0: a couple of validations reference other variables (cross-variable
  # validation), unavailable on 1.5-1.8.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}
