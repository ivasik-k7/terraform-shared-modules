terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "api_cert_key" {
  type        = string
  description = "APi Certificate Key"
}

variable "api_cert_body" {
  type        = string
  description = "API Certificate Body"
}

provider "aws" {
  region = "us-east-1"
}

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}


module "import_acm_certificates" {
  source = "./modules/acm-import"

  tags = merge(
    local.base_tags,
    {
      Project   = "CloudMigration"
      Owner     = "DevOpsTeam"
      ManagedBy = "Terraform"
    },
  )

  certificates = {
    "frontend_cert" = {
      name                   = "frontend-production-cert"
      certificate_body_path  = "${path.module}/certs/frontend.crt"
      private_key_path       = "${path.module}/certs/frontend.key"
      certificate_chain_path = "${path.module}/certs/chain.crt"
      tags = {
        Environment = "Production"
        Service     = "Frontend"
      }
    },

    "api_cert" = {
      name             = "api-staging-cert"
      certificate_body = var.api_cert_body
      private_key      = var.api_cert_key
      tags = {
        Environment = "Staging"
        Service     = "API"
      }
    },
  }
}
