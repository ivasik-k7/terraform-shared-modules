# A production account used from London and Ireland: the account part (limits,
# FinOps read-only role) once, in London; the Region part in both, so each
# Region has its severity topics, AI profiles and burn meter.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

provider "aws" {
  alias  = "ireland"
  region = "eu-west-1"
}

locals {
  team        = "core-banking"
  cost_centre = "CC-2100"
  emails      = { high = ["core-banking-leads@example.com"], critical = ["core-banking-oncall@example.com"] }
  bus         = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"

  ai = {
    applications = {
      statement-summaries = {
        models      = { haiku = "arn:aws:bedrock:eu-west-2::foundation-model/anthropic.claude-haiku-4-5" }
        monthly_cap = 3000
      }
    }
    prices          = { "anthropic.claude-haiku-4-5" = { input_per_million = 1, output_per_million = 5 } }
    burn_per_hour   = 25
    invocation_logs = { enabled = true }
  }
}

module "london" {
  source = "../.."

  team        = local.team
  cost_centre = local.cost_centre
  emails      = local.emails

  limits = {
    account = { amount = "120000", owners = ["core-banking-finance@example.com"] }
    data-transfer = {
      amount = "6000"
      scope  = { usage_type_groups = ["EC2: Data Transfer - Inter AZ", "EC2: Data Transfer - Internet (Out)"] }
    }
  }

  platforms = {
    ledger   = { amount = "70000", anomaly = { min_impact = 1000 } }
    payments = { amount = "35000", anomaly = {} }
  }

  ai = local.ai

  finops_access = {
    trusted_account_id = "444444444444"
    trusted_role_arns  = ["arn:aws:iam::444444444444:role/finops-analyst"]
  }

  signals = { control_plane_bus_arn = local.bus }
}

module "ireland" {
  source    = "../.."
  providers = { aws = aws.ireland }

  components  = { account = false }
  team        = local.team
  cost_centre = local.cost_centre
  emails      = local.emails
  ai = merge(local.ai, {
    applications = {
      statement-summaries = {
        models      = { haiku = "arn:aws:bedrock:eu-west-1::foundation-model/anthropic.claude-haiku-4-5" }
        monthly_cap = 3000
      }
    }
  })

  signals = { control_plane_bus_arn = local.bus }
}

output "budget_names" {
  value = module.london.budget_names
}

output "controls" {
  value = merge(module.london.controls, module.ireland.controls)
}
