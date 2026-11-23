# One account's severity topics in London, with owners by severity, forwarded
# to the Keel control plane bus with the account's cost alarms.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "signals" {
  source = "../.."

  name = "lending"
  emails = {
    warning  = ["lending-leads@example.com"]
    high     = ["lending-leads@example.com"]
    critical = ["lending-oncall@example.com"]
  }
  control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
  forward               = { alarm_name_prefixes = ["lending-cost-"] }
}

output "topic_arns" {
  value = module.signals.topic_arns
}

output "verify_commands" {
  value = module.signals.verify_commands
}
