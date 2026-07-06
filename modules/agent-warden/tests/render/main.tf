# Offline policy renderer for CI lint. create = false means no data sources and
# no resources, so `terraform apply` here needs NO AWS credentials - it only
# evaluates the jsonencode()d policy locals, which CI then feeds to an IAM linter
# (parliament). Exercises the tricky paths: grant conditions, exceptions,
# tag-on-create, and the SCP.

terraform {
  required_version = ">= 1.9.0"
}

# offline: mock creds + skip flags; nothing ever calls AWS (create = false).
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "render" {
  source = "../.."

  create                   = false
  name                     = "ai-agent"
  sso_permission_set_names = ["Developer"]

  data_read_exceptions       = ["arn:aws:secretsmanager:us-east-1:111122223333:secret:demo-*"]
  extra_denied_actions       = ["bedrock:*"]
  enforce_cost_tag_on_create = true
  enable_budget_killswitch   = true
  enable_budget_guardrail    = true
  monthly_budget_usd         = 1
  provisioner_principal_arns = ["arn:aws:iam::111122223333:role/tfc-provisioner"]

  team_grants = [
    {
      sid       = "GrantWithConditions"
      actions   = ["s3:PutObject"]
      resources = ["arn:aws:s3:::sandbox/*"]
      conditions = [
        { test = "StringEquals", variable = "aws:RequestedRegion", values = ["us-east-1"] },
        { test = "Bool", variable = "aws:SecureTransport", values = ["true"] },
      ]
    },
  ]
}

output "boundary_policy_json" {
  value = module.render.boundary_policy_json
}

output "trust_policy_json" {
  value = module.render.trust_policy_json
}

output "team_grants_policy_json" {
  value = module.render.team_grants_policy_json
}

output "scp_policy_json" {
  value = module.render.scp_policy_json
}
