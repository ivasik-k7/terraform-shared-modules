terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0, < 7.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "eu-west-1"
}

variable "subnet_ids" {
  description = "Private subnets for the replication instance, in at least two AZs. They need a route to the Oracle source (on-prem or another VPC) and to the Aurora target."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for the replication instance. Egress to 1521 on the source and 5432 on the target; no ingress."
  type        = string
}

variable "source_secret_arn" {
  description = "Secrets Manager secret holding the Oracle credential, in the shape DMS expects: username, password, host and port. It is a database user of its own for DMS, not the RDS-managed master secret, which DMS cannot read. The database name comes from the endpoint, not the secret."
  type        = string
}

variable "target_secret_arn" {
  description = "Secrets Manager secret holding the Aurora PostgreSQL credential."
  type        = string
}

variable "secret_kms_key_arn" {
  description = "CMK the two secrets are encrypted with. Without it DMS can call GetSecretValue and still not decrypt."
  type        = string
}

variable "kms_key_arn" {
  description = "CMK for replication storage, which is where cached changes and in-flight LOBs sit."
  type        = string
}

variable "sns_topic_arn" {
  description = "Topic for task events and alarms. The one that matters is a task stopping on its own."
  type        = string
}

variable "rds_ca_bundle_pem" {
  description = "PEM of the RDS CA bundle, for verify-full against the Aurora target. Download the regional bundle from AWS."
  type        = string
}

variable "oracle_wallet_base64" {
  description = "Base64 of the Oracle wallet (cwallet.sso) holding the CA that signed the Oracle source's certificate: base64 -w0 cwallet.sso. DMS verifies Oracle against a wallet, not a PEM."
  type        = string
}

module "migration" {
  source = "../../"

  name = "oracle-to-aurora"

  instance_class       = "dms.c5.large"
  allocated_storage_gb = 100
  engine_version       = "3.5.3"
  multi_az             = true

  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]

  kms_key_arn = var.kms_key_arn
  require_cmk = true

  certificates = {
    oracle-wallet = { wallet = var.oracle_wallet_base64 }
    rds-ca        = { pem = var.rds_ca_bundle_pem }
  }

  endpoints = {
    oracle-prod = {
      role          = "source"
      engine        = "oracle"
      server_name   = "oracle-prod.internal.example.com"
      port          = 1521
      database_name = "ORCL"

      secret_arn         = var.source_secret_arn
      secret_kms_key_arn = var.secret_kms_key_arn

      ssl_mode        = "verify-ca"
      certificate_key = "oracle-wallet"
    }

    aurora-target = {
      role          = "target"
      engine        = "aurora-postgresql"
      server_name   = "app-target.cluster-abc123.eu-west-1.rds.amazonaws.com"
      port          = 5432
      database_name = "app"

      secret_arn         = var.target_secret_arn
      secret_kms_key_arn = var.secret_kms_key_arn

      ssl_mode        = "verify-full"
      certificate_key = "rds-ca"

      postgres = {
        after_connect_script = "SET session_replication_role = replica;"
      }
    }
  }

  tasks = {
    app = {
      source_endpoint = "oracle-prod"
      target_endpoint = "aurora-target"
      migration_type  = "full-load-and-cdc"

      table_mappings = file("${path.module}/mappings/app-schema.json")

      start = false

      settings = {
        target_table_prep_mode = "DO_NOTHING"

        lob_mode        = "LIMITED"
        lob_max_size_kb = 64

        validation_enabled = true
        validation_threads = 8

        batch_apply_enabled = true
      }
    }
  }

  sns_topic_arn             = var.sns_topic_arn
  alarm_cdc_latency_seconds = 300
  log_retention_days        = 90

  tags = {
    Environment = "production"
    Owner       = "platform"
    Migration   = "oracle-decommission"
  }
}

output "source_prerequisites" {
  description = "Hand this to whoever owns the Oracle database before the first task start. None of it is enforceable from Terraform."
  value       = module.migration.source_prerequisites
}

output "network_contract" {
  description = "Hand this to whoever owns the VPC and the database firewalls."
  value       = module.migration.network_contract
}

output "replication_instance_private_ips" {
  description = "The addresses the source and target firewalls have to allow."
  value       = module.migration.replication_instance_private_ips
}

output "verify_commands" {
  description = "Connection tests first, then task status, then CDC latency."
  value       = module.migration.verify_commands
}

output "governance" {
  description = "The posture this migration actually has, as data."
  value       = module.migration.governance
}
