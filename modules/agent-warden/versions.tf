terraform {
  # >= 1.9.0: a couple of validations reference other variables.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # >= 5.75: aws_iam_role_policies_exclusive
      version = ">= 5.75.0, < 6.0.0"
    }
    # zips the inline Lambda sources (killswitch / digest) at plan time - local only.
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}
