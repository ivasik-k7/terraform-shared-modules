# The smallest useful call: allocation tags, one cost category, the free
# recommendation services, managed anomaly monitors with an immediate alert,
# and a limit on the whole bill.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "us-east-1"
}

module "billing" {
  source = "../.."

  cost_allocation_tags = ["Team", "CostCentre"]

  cost_categories = {
    Team = { inherit_from_tag = "Team" }
  }

  anomaly_detection = {
    cost_categories = ["Team"]
    alert           = { emails = ["finops@example.com"] }
  }

  limits = {
    total = { amount = "100000", owners = ["finops@example.com"] }
  }

  signals = {
    emails = { high = ["finops@example.com"], critical = ["finops@example.com"] }
  }

  acknowledged_checks = ["commitments_are_watched"]
}

output "topic_arns" {
  value = module.billing.topic_arns
}
