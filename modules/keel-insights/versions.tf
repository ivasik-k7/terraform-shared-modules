terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The range of the repository's other 6.x modules.
      version = ">= 6.57.1, < 7.0.0"
    }
  }
}
