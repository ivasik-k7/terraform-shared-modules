# Limits for two platforms sharing one account, a data-transfer usage limit, a
# non-production limit that locks its roles at 100%, and a Savings Plans
# utilization target, alerting on severity topics from keel-signals.

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
  source = "../../../keel-signals"

  name   = "lending"
  emails = { high = ["lending-leads@example.com"], critical = ["lending-oncall@example.com"] }
}

module "limits" {
  source = "../.."

  name       = "lending"
  topic_arns = module.signals.topic_arns

  limits = {
    ledger = {
      amount  = "70000"
      scope   = { tags = { Platform = ["ledger"] } }
      owners  = ["ledger-owner@example.com"]
      anomaly = { min_impact = 1000 }
    }
    payments = {
      amount  = "35000"
      scope   = { tags = { Platform = ["payments"] } }
      owners  = ["payments-owner@example.com"]
      anomaly = {}
    }
    inter-az-gb = {
      type   = "USAGE"
      amount = "200000"
      unit   = "GB"
      scope  = { usage_type_groups = ["EC2: Data Transfer - Inter AZ"] }
    }
    dev = {
      tier   = "non-production"
      amount = "6000"
      scope  = { tags = { Environment = ["dev"] } }
      action = { lock_roles = ["developer"] }
    }
    sp-utilization = {
      type           = "SAVINGS_PLANS_UTILIZATION"
      target_percent = 95
    }
  }
}

output "thresholds" {
  value = module.limits.thresholds
}

output "controls" {
  value = module.limits.controls
}
