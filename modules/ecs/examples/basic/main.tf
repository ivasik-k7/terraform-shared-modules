# The smallest useful call: one Fargate service from an image, two tasks across
# AZs in private subnets. No topic and no customer key yet, both acknowledged.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "private_subnet_ids" {
  description = "Private subnets in two AZs, with the endpoints output.network_contract lists."
  type        = list(string)
  default     = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
}

variable "task_security_group_id" {
  description = "Security group for the tasks."
  type        = string
  default     = "sg-0a1b2c3d4e5f60001"
}

module "ecs" {
  source = "../.."

  name               = "orders-dev"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.task_security_group_id]

  services = {
    api = {
      image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/orders-api:1.4.2"
      port          = 8080
      desired_count = 2
    }
  }

  acknowledged_checks = ["somebody_hears_a_failure", "logs_use_a_customer_key"]
}

output "service_arns" {
  value = module.ecs.service_arns
}

output "network_contract" {
  value = module.ecs.network_contract
}
