terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.100.0, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "kms_key_arn" {
  description = "Customer managed key in eu-west-2."
  type        = string
}

variable "dr_bucket_arn" {
  description = "Versioned destination bucket in the DR region."
  type        = string
}

variable "dr_kms_key_arn" {
  description = "Customer managed key in the DR region."
  type        = string
}

variable "log_bucket" {
  description = "The central access log bucket."
  type        = string
}

variable "analytics_role_arn" {
  description = "Role in the analytics account that reads curated data."
  type        = string
}

variable "organization_id" {
  description = "The AWS Organization."
  type        = string
}

module "lake" {
  source = "../.."

  name            = "orders-lake"
  kms_key_arn     = var.kms_key_arn
  organization_id = var.organization_id
  access_logging  = { target_bucket = var.log_bucket }

  grants = {
    analytics = { principals = [var.analytics_role_arn], access = "read", prefixes = ["curated/"] }
  }

  lifecycle_rules = {
    raw = {
      prefix      = "raw/"
      transitions = [{ days = 30, storage_class = "STANDARD_IA" }, { days = 180, storage_class = "GLACIER" }]
    }
    scratch = {
      prefix          = "scratch/"
      expiration_days = 14
    }
  }

  replication = {
    rules = {
      dr = {
        destination_bucket_arn   = var.dr_bucket_arn
        replica_kms_key_arn      = var.dr_kms_key_arn
        storage_class            = "STANDARD_IA"
        replication_time_control = true
      }
    }
  }

  inventory = {
    weekly = { destination_bucket_arn = var.dr_bucket_arn, destination_prefix = "inventory/orders-lake/" }
  }

  tags = { CostCentre = "cc-1234", Owner = "data-platform" }
}

output "kms_key_policy_requirements" {
  description = "For the owners of both keys, before the first apply."
  value       = module.lake.kms_key_policy_requirements
}

output "replication_destination_requirements" {
  value = module.lake.replication_destination_requirements
}
