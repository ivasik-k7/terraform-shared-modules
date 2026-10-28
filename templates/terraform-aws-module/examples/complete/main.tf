# Every input set: a customer key, a year of retention, kept on destroy.
# Send output.kms_key_policy_requirements to the key owner before the apply.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.90.0, < 7.0.0" }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-2"
}

variable "kms_key_arn" {
  description = "Customer managed key in the same region."
  type        = string
}

module "logs" {
  source = "../.."

  name            = "/app/audit"
  retention_days  = 365
  log_group_class = "STANDARD"
  kms_key_arn     = var.kms_key_arn
  skip_destroy    = true

  tags = {
    CostCentre = "cc-1234"
    Owner      = "platform"
  }
}

output "kms_key_policy_requirements" {
  description = "For the key owner, before the first apply."
  value       = module.logs.kms_key_policy_requirements
}

output "governance" {
  value = module.logs.governance
}
