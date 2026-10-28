terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.100.0, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "bucket" {
  source = "../.."

  name                = "app-assets"
  acknowledged_checks = ["data_uses_a_customer_key", "access_is_logged"]
}

output "bucket" {
  value = module.bucket.bucket
}

output "read_policy_json" {
  description = "Attach to the roles that read the bucket."
  value       = module.bucket.read_policy_json
}
