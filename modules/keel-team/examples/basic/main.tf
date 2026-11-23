# One team's sandbox account in one Region: an account limit that locks at
# 100%, two platforms sharing the account with their own limits, an AI
# application with its cap, burn meter and metadata-only invocation logs, and
# office hours for the non-production instances.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "team" {
  source = "../.."

  team        = "lending-payments"
  cost_centre = "CC-4410"
  tier        = "sandbox"
  emails      = { high = ["lending-payments-leads@example.com"], critical = ["lending-payments-leads@example.com"] }

  limits = {
    account = {
      amount = "8500"
      action = { lock_roles = ["developer", "ci-deploy"] }
    }
  }

  platforms = {
    payments-api = { amount = "4000", anomaly = {} }
    statements   = { amount = "1500", scope = { regions = ["eu-west-2"] } }
  }

  ai = {
    applications = {
      loan-assistant = {
        models      = { sonnet = "arn:aws:bedrock:eu-west-2::foundation-model/anthropic.claude-sonnet-4-6" }
        monthly_cap = 6000
        platform    = "payments-api"
      }
    }
    prices = {
      "anthropic.claude-sonnet-4-6" = { input_per_million = 3, output_per_million = 15 }
    }
    burn_per_hour   = 40
    invocation_logs = { enabled = true }
  }

  schedules = {
    office-hours = {
      tag_values = ["office-hours"]
      stop       = "cron(0 19 ? * MON-FRI *)"
      start      = "cron(0 8 ? * MON-FRI *)"
    }
  }

  finops_access = { trusted_account_id = "444444444444" }

  signals = {
    control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
  }
}

output "inference_profile_arns" {
  value = module.team.inference_profile_arns
}

output "budget_names" {
  value = module.team.budget_names
}

output "plan_gate" {
  value = module.team.plan_gate
}
