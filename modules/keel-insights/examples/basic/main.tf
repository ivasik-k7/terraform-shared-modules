# Cloud Intelligence Dashboards in London, in the FinOps account: the
# destination of the management account's exports, and CUDOS v5, KPI, Cost
# Intelligence, FOCUS and CORA. Quick Sight Enterprise and its user exist.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

module "insights" {
  source = "../.."

  data_exports = {
    source_account_ids = ["444444444444"]
  }

  quicksight = {
    user               = "finops-admin"
    subscription_ready = true
  }

  dashboards = {
    primary_tag   = "Team"
    secondary_tag = "Environment"
  }

  tags = { CostCentre = "CC-0001", Owner = "finops" }
}

output "source_requirements" {
  value = module.insights.source_requirements
}

output "dashboard_urls" {
  value = module.insights.dashboard_urls
}
