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
  default     = "eu-west-2"
}

variable "subnet_ids" {
  description = "Private subnets in at least two AZs, attached to the Cloud WAN segment that reaches the on-prem source. No internet route."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for the replication instance. Egress to the on-prem database port, to the Aurora port, and 443 to the VPC endpoints. No ingress."
  type        = string
}

variable "source_secret_arn" {
  description = "Secrets Manager secret holding the on-prem database credential. DMS reads it through the interface endpoint, never through the internet."
  type        = string
}

variable "target_secret_arn" {
  description = "Secrets Manager secret holding the Aurora credential."
  type        = string
}

variable "secret_kms_key_arn" {
  description = "CMK the secrets are encrypted with. DMS needs kms:Decrypt on it as well as GetSecretValue."
  type        = string
}

variable "replication_kms_key_arn" {
  description = "CMK for replication storage. This volume holds cached changes and in-flight LOBs - production data in transit, at rest."
  type        = string
}

variable "onprem_wallet_base64" {
  description = "Base64 of the Oracle wallet (cwallet.sso) holding the CA that signed the on-prem database's certificate: base64 -w0 cwallet.sso. DMS verifies an Oracle source against a wallet, not a PEM, and supports only none or verify-ca on Oracle - so verify-full is not available here."
  type        = string
}

variable "assessment_bucket_name" {
  description = "Existing S3 bucket for premigration assessment reports, in this region. The module creates the role DMS writes them with, scoped to a folder."
  type        = string
}

variable "rds_ca_bundle_pem" {
  description = "PEM of the RDS CA bundle for the Aurora target."
  type        = string
}

variable "sns_topic_arn" {
  description = "Topic for task events and alarms, in this region."
  type        = string
}

variable "onprem_hostname" {
  description = "Hostname of the on-prem source. It must resolve from inside the VPC - via Route 53 Resolver rules forwarding to on-prem DNS, or a private hosted zone. A name that resolves only on-prem is the most common first-run failure here."
  type        = string
}

module "migration" {
  source = "../../"

  name = "core-banking-to-aurora"

  instance_class       = "dms.c5.xlarge"
  allocated_storage_gb = 200
  engine_version       = "3.5.3"

  multi_az = true

  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]

  publicly_accessible = false

  kms_key_arn = var.replication_kms_key_arn
  require_cmk = true

  certificates = {
    onprem-wallet = { wallet = var.onprem_wallet_base64 }
    rds-ca        = { pem = var.rds_ca_bundle_pem }
  }

  endpoints = {
    core-onprem = {
      role          = "source"
      engine        = "oracle"
      server_name   = var.onprem_hostname
      port          = 1521
      database_name = "CORE"

      secret_arn         = var.source_secret_arn
      secret_kms_key_arn = var.secret_kms_key_arn

      ssl_mode        = "verify-ca"
      certificate_key = "onprem-wallet"
    }

    aurora-core = {
      role          = "target"
      engine        = "aurora-postgresql"
      server_name   = "core.cluster-abc123.eu-west-2.rds.amazonaws.com"
      port          = 5432
      database_name = "core"

      secret_arn         = var.target_secret_arn
      secret_kms_key_arn = var.secret_kms_key_arn

      ssl_mode        = "verify-full"
      certificate_key = "rds-ca"

      postgres = {
        after_connect_script = "SET session_replication_role = replica;"
      }
    }
  }

  premigration_assessment = {
    enabled       = true
    bucket_name   = var.assessment_bucket_name
    bucket_folder = "dms-assessments"
    kms_key_arn   = var.replication_kms_key_arn
  }

  tasks = {
    core = {
      source_endpoint = "core-onprem"
      target_endpoint = "aurora-core"
      migration_type  = "full-load-and-cdc"
      table_mappings  = file("${path.module}/mappings/core-banking.json")

      start = false

      settings = {
        target_table_prep_mode = "DO_NOTHING"

        validation_enabled = true
        validation_threads = 8

        lob_mode = "FULL"

        control_schema = "dms_control"
      }
    }
  }

  validation_tasks = {
    pre-cutover = {
      task    = "core"
      mode    = "full-load"
      threads = 8
      start   = false
    }
  }

  sns_topic_arn = var.sns_topic_arn

  alarm_cdc_latency_seconds = 300

  log_retention_days = 365

  tags = {
    Environment  = "production"
    Owner        = "platform-migration"
    DataClass    = "confidential"
    ChangeRecord = "CHG0000000"
    CostCentre   = "migration-programme"
  }
}

output "firewall_request" {
  description = "Hand to the on-prem network team. These are the addresses that will connect to the source database, and there is one per AZ because the instance is multi-AZ."
  value = {
    source_addresses = module.migration.replication_instance_private_ips
    destination      = "${var.onprem_hostname}:1521"
    direction        = "outbound from AWS to on-premises, over the Cloud WAN attachment"
    return_path_note = "The on-prem side must route the VPC CIDR back through the same Cloud WAN segment. Asymmetric routing here presents as a connection that tests fine and then stalls mid-load."
  }
}

output "network_contract" {
  description = "Hand to whoever owns the VPC. Every interface endpoint listed here is mandatory in an isolated VPC - a missing one is a hang, not an error."
  value       = module.migration.network_contract
}

output "source_prerequisites" {
  description = "Hand to the on-prem DBA team before the first task start. Oracle supplemental logging is the one that fails silently and wrongly rather than loudly."
  value       = module.migration.source_prerequisites
}

output "governance" {
  description = "The posture, as data, for the change record."
  value       = module.migration.governance
}

output "premigration_assessment" {
  description = "Start, status and report commands per task. Run the assessment before starting the task and attach the report to the change record."
  value       = module.migration.premigration_assessment
}

output "kms_key_policy_requirements" {
  description = "Hand to the owner of each CMK before the first apply: what its key policy has to allow."
  value       = module.migration.kms_key_policy_requirements
}

output "verify_commands" {
  description = "Connection test first. In this topology it is the check that fails when DNS, routing or the firewall is not ready."
  value       = module.migration.verify_commands
}
