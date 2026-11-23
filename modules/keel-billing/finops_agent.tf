locals {
  finops_agent       = local.create ? var.finops_agent.enabled : false
  finops_agent_admin = local.finops_agent ? var.finops_agent.delegated_admin_account_id != "" : false
}

# ---------------------------------------------------------------------------
# AWS FinOps Agent: organization-wide access through its service-linked role,
# administered from a delegated account
# https://docs.aws.amazon.com/finops-agent/latest/userguide/what-is.html
# ---------------------------------------------------------------------------

resource "aws_organizations_aws_service_access" "finops_agent" {
  count = local.finops_agent ? 1 : 0

  service_principal = "finops-agent.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "finops_agent" {
  count = local.finops_agent_admin ? 1 : 0

  account_id        = var.finops_agent.delegated_admin_account_id
  service_principal = "finops-agent.amazonaws.com"

  depends_on = [aws_organizations_aws_service_access.finops_agent]
}
