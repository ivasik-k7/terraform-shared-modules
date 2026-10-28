# The smallest call: a name. Retention defaults to 30 days, and the
# logs_use_a_customer_key warning is acknowledged on purpose.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.90.0, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "logs" {
  source = "../.."

  name                = "/app/basic"
  acknowledged_checks = ["logs_use_a_customer_key"]
}

output "arn" {
  value = module.logs.arn
}
