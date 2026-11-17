# The smallest call: two instances across two AZs from a pinned AMI, reachable
# with Session Manager. No topic and no customer key yet, both acknowledged.

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

variable "instance_security_group_id" {
  description = "Security group for the instances."
  type        = string
  default     = "sg-0a1b2c3d4e5f60001"
}

module "fleet" {
  source = "../.."

  name               = "orders-workers"
  ami                = "ami-0123456789abcdef0"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.instance_security_group_id]
  min_size           = 2
  max_size           = 4

  acknowledged_checks = ["somebody_hears_a_failure", "volumes_use_a_customer_key"]
}

output "autoscaling_group_name" {
  value = module.fleet.autoscaling_group_name
}

output "network_contract" {
  value = module.fleet.network_contract
}
