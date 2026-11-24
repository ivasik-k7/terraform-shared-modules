locals {
  finops_agent = local.create ? var.finops_agent.enabled : false
}

# AWS FinOps Agent's organization access is turned on from its console in
# us-east-1, which creates AWSServiceRoleForFinOpsAgent; turning on trusted
# access in AWS Organizations alone does not complete it. The module emits the
# steps and the policy as data (output.finops_agent_setup).
# https://docs.aws.amazon.com/finops-agent/latest/userguide/setting-up-organization-access.html
