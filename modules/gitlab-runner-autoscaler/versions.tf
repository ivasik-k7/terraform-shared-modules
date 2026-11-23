terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # The floor modules/ecs and modules/asg-group share.
      version = ">= 6.57.1, < 7.0.0"
    }
  }
}
