# Mandatory tags as an organization tag policy, an SCP that refuses to create
# resources without them, and the approved-models list for Bedrock, attached
# to a pilot OU first. A break-glass role is exempt from both SCPs.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "guardrails" {
  source = "../.."

  targets = ["ou-ab12-pilotou1"]

  required_tags = {
    Team        = { report_for = ["ec2:instance", "rds:db", "lambda:function", "s3:bucket"] }
    CostCentre  = { report_for = ["ec2:instance", "rds:db", "lambda:function", "s3:bucket"] }
    Environment = { values = ["production", "non-production", "sandbox"], report_for = ["ec2:ALL_SUPPORTED"], enforce_for = ["ec2:instance"] }
  }

  deny_untagged = {
    enabled           = true
    tags              = ["Team", "CostCentre"]
    exempt_principals = ["arn:aws:iam::*:role/break-glass", "arn:aws:iam::*:role/account-vending"]
  }

  bedrock_models = {
    enabled           = true
    allowed_models    = ["example.model-a", "example.model-b"]
    allowed_regions   = ["eu-west-2"]
    exempt_principals = ["arn:aws:iam::*:role/break-glass"]
  }
}

output "provider_setting" {
  value = module.guardrails.provider_setting
}

output "controls" {
  value = module.guardrails.controls
}
