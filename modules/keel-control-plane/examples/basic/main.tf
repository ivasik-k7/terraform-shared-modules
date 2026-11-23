# The control plane in the FinOps account: a bus every account in the
# organization may send to, routing by severity, and evidence kept in an
# Object Lock bucket for seven years.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "control_plane" {
  source = "../.."

  sources = { organization_id = "o-abcdefghij" }

  severity = {
    anomaly_warning  = 100
    anomaly_high     = 1000
    anomaly_critical = 5000
    emails = {
      warning  = ["finops@example.com"]
      high     = ["finops@example.com"]
      critical = ["finops-oncall@example.com"]
    }
  }

  evidence = { mode = "GOVERNANCE", retention_days = 2557 }

  tags = { CostCentre = "CC-0001", Owner = "finops" }
}

output "event_bus_arn" {
  value = module.control_plane.event_bus_arn
}

output "topic_arns" {
  value = module.control_plane.topic_arns
}

output "verify_commands" {
  value = module.control_plane.verify_commands
}
