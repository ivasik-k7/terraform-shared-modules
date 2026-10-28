terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.73.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "kms" {
  source = "../.."

  name = "orders"
}

output "key_arn" {
  value = module.kms.key_arns["main"]
}
