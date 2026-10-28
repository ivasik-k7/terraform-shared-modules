terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.100.0, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "source_bucket_arns" {
  description = "Buckets in this account and region that log here."
  type        = list(string)
}

module "logs" {
  source = "../.."

  name               = "access-logs"
  access_log_sources = var.source_bucket_arns

  lifecycle_rules = {
    expire = {
      transitions     = [{ days = 90, storage_class = "GLACIER_IR" }]
      expiration_days = 365
    }
  }

  tags = { CostCentre = "cc-platform", Owner = "platform" }
}

output "bucket" {
  description = "Point each source bucket's access_logging.target_bucket here."
  value       = module.logs.bucket
}
