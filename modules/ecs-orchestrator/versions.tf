terraform {
  # >= 1.9.0: the services validations reference other variables
  # (cross-variable validation), which is unavailable on 1.5-1.8.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # floor covers ecs managed-ebs volume_configuration + service connect.
      version = ">= 5.50.0, < 6.0.0"
    }
  }
}
