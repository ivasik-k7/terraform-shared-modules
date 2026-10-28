terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.90.0, < 7.0.0"
    }
    # Zips the Lambda behind create_iam_database_users at plan time. Local
    # only: nothing is fetched.
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}
