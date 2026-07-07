# offline renderer for CI lint. create = false: no data sources, no resources,
# no credentials - only the flag-json locals evaluate. exercises the painful
# paths: env overlay, every constraint kind, every cast.

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}

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

  create = false
  name   = "render"

  environments = {
    staging = {}
    prod    = {}
  }

  profiles = {
    flags = {
      type = "feature-flags"
      flags = {
        checkout-v2 = {
          description = "render fixture"
          enabled     = false
          attributes = {
            rollout-percent = { type = "number", value = "10", required = true, minimum = 0, maximum = 100 }
            allowed-tier    = { type = "string", value = "beta", enum = ["beta", "gold", "all"] }
            match-key       = { type = "string", value = "ab12", pattern = "^[a-z0-9]+$" }
            sticky          = { type = "boolean", value = "true" }
          }
          per_environment = {
            staging = { enabled = true }
            prod    = { attributes = { rollout-percent = "50", allowed-tier = "gold" } }
          }
        }
        dark-mode = { enabled = true }
      }
    }
  }
}

output "feature_flags_json" {
  value = module.render.feature_flags_json
}
