# The smallest call: two repositories for one application, immutable tags,
# scanned on push, encrypted with your key, and a lifecycle policy that keeps
# the newest 100 images.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "ecr" {
  source = "../.."

  name        = "orders"
  kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags        = { CostCenter = "cc-1042", Owner = "orders-team" }

  repositories = {
    "orders/api"    = {}
    "orders/worker" = {}
  }
}

output "repository_urls" {
  value = module.ecr.repository_urls
}

output "push_policy_json" {
  value = module.ecr.push_policy_json
}

output "kms_key_policy_requirements" {
  value = module.ecr.kms_key_policy_requirements
}
