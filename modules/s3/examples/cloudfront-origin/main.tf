terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.100.0, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "distribution_arn" {
  description = "The CloudFront distribution that serves the site."
  type        = string
}

variable "log_bucket" {
  description = "The central access log bucket."
  type        = string
}

module "site" {
  source = "../.."

  name                         = "www-content"
  cloudfront_distribution_arns = [var.distribution_arn]
  access_logging               = { target_bucket = var.log_bucket }
  default_lifecycle            = { noncurrent_version_expiration_days = 30 }

  acknowledged_checks = ["data_uses_a_customer_key"]
}

output "origin_domain_name" {
  description = "The origin domain name for the distribution."
  value       = module.site.regional_domain_name
}
