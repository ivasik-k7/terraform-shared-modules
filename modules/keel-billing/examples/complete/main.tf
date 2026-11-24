# The management account, configured as code: owner taxonomy, the free AWS
# recommendation services, anomaly monitors with one immediate alert routed by
# impact on the control plane, organization limits by business unit, platform
# and service, commitment targets, billing views for the FinOps account and a
# business unit, the FinOps Agent decision with its setup steps, and the
# source side of the Cloud Intelligence Dashboards pipeline. Billing APIs and
# their events live in us-east-1, so this workspace runs there.

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

  name = "keel"
  tags = { CostCentre = "CC-0001", Owner = "finops" }

  cost_allocation_tags = ["Team", "CostCentre", "Application", "Environment", "Owner", "Platform"]

  cost_categories = {
    BusinessUnit = {
      rules = [
        { value = "lending", accounts = ["111111111111", "111111111112"] },
        { value = "payments", accounts = ["222222222221"] },
        { value = "platform", tag_key = "Team", tag_values = ["platform", "finops"] },
      ]
      inherit_from_tag = "BusinessUnit"
      split_charges    = [{ source = "platform", targets = ["lending", "payments"] }]
    }
    Environment = {
      inherit_from_tag = "Environment"
    }
  }

  anomaly_detection = {
    cost_category_values = { BusinessUnit = ["lending", "payments", "platform"] }
    alert                = { min_impact_absolute = 100 }
    digests = {
      weekly = { frequency = "WEEKLY", min_impact_absolute = 50, emails = ["finops@example.com"] }
    }
  }

  limits = {
    total = { amount = "4200000", owners = ["finops@example.com"] }
    lending = {
      amount = "1500000"
      scope  = { cost_categories = { BusinessUnit = ["lending"] } }
      owners = ["lending-finops@example.com"]
    }
    ledger-platform = {
      amount = "250000"
      scope  = { tags = { Platform = ["ledger"] } }
    }
    ai = {
      amount = "60000"
      scope  = { services = ["Amazon Bedrock"] }
    }
    data-transfer = {
      amount = "40000"
      scope  = { usage_type_groups = ["EC2: Data Transfer - Inter AZ", "EC2: Data Transfer - Internet (Out)", "EC2: Data Transfer - Region to Region (Out)"] }
    }
    run-rate = { auto_adjust_months = 3, forecast_thresholds = [110], actual_thresholds = [120] }
  }

  commitments = {
    savings_plans_utilization = 95
    savings_plans_coverage    = 70
    ri_utilization            = { "Amazon Relational Database Service" = 95 }
    owners                    = ["finops@example.com"]
  }

  billing_views = {
    finops = { accounts = ["111111111111", "111111111112", "222222222221"], share_with = ["333333333333"] }
    ledger = { tag = { key = "Platform", values = ["ledger"] }, share_with = ["111111111111"] }
  }

  finops_agent = { enabled = true, delegated_admin_account_id = "333333333333" }

  signals = {
    emails                = { critical = ["finops-oncall@example.com"] }
    control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
  }

  acknowledged_checks = ["finops_agent_is_approved"]

  data_exports = {
    enabled                = true
    destination_account_id = "333333333333"
    region                 = "eu-west-2"
  }
}

output "topic_arns" {
  value = module.billing.topic_arns
}

output "billing_view_arns" {
  value = module.billing.billing_view_arns
}

output "controls" {
  value = module.billing.controls
}

output "governance" {
  value = module.billing.governance
}
