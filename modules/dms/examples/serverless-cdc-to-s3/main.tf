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
  description = "Private subnets in at least two AZs, with a route to the RDS source and an S3 gateway endpoint."
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group for the replication. Egress to 5432 on the source and 443 for S3 and the AWS APIs."
  type        = string
}

variable "source_secret_arn" {
  description = "Secrets Manager secret holding the PostgreSQL credential."
  type        = string
}

variable "secret_kms_key_arn" {
  description = "CMK the secret is encrypted with."
  type        = string
}

variable "lake_bucket" {
  description = "Existing S3 bucket for the lake. The module creates a role scoped to the prefix below, not to the whole bucket."
  type        = string
}

variable "lake_kms_key_arn" {
  description = "CMK the lake is encrypted with. DMS needs GenerateDataKey on it, which the module's role grants."
  type        = string
}

variable "sns_topic_arn" {
  description = "Topic for replication events."
  type        = string
}

variable "rds_ca_bundle_pem" {
  description = "PEM of the RDS CA bundle, for verify-full against the source."
  type        = string
}

module "cdc_to_lake" {
  source = "../../"

  name         = "sales-cdc-lake"
  compute_mode = "serverless"

  serverless = {
    min_dcu  = 2
    max_dcu  = 16
    multi_az = true
  }

  subnet_ids         = var.subnet_ids
  security_group_ids = [var.security_group_id]

  kms_key_arn = var.lake_kms_key_arn
  require_cmk = true

  certificates = {
    rds-ca = { pem = var.rds_ca_bundle_pem }
  }

  endpoints = {
    sales-db = {
      role          = "source"
      engine        = "postgres"
      server_name   = "sales.cluster-abc123.eu-west-1.rds.amazonaws.com"
      port          = 5432
      database_name = "sales"

      secret_arn         = var.source_secret_arn
      secret_kms_key_arn = var.secret_kms_key_arn

      ssl_mode        = "verify-full"
      certificate_key = "rds-ca"

      postgres = {
        heartbeat_enable    = true
        heartbeat_frequency = 5
        heartbeat_schema    = "awsdms"
      }
    }
  }

  s3_targets = {
    lake = {
      bucket_name   = var.lake_bucket
      bucket_folder = "raw/sales"

      data_format      = "parquet"
      compression_type = "GZIP"

      encryption_mode = "SSE_KMS"
      kms_key_arn     = var.lake_kms_key_arn

      date_partition_enabled  = true
      date_partition_sequence = "YYYYMMDD"

      include_op_for_full_load = true
      timestamp_column_name    = "dms_ingest_ts"
    }
  }

  tasks = {
    sales = {
      source_endpoint = "sales-db"
      target_endpoint = "lake"
      migration_type  = "full-load-and-cdc"
      table_mappings  = file("${path.module}/mappings/cdc-to-lake.json")
      start           = false

      settings = {
        target_table_prep_mode = "DO_NOTHING"
        validation_enabled     = true

        lob_mode        = "LIMITED"
        lob_max_size_kb = 16384
      }
    }
  }

  sns_topic_arn      = var.sns_topic_arn
  log_retention_days = 30

  tags = {
    Environment = "production"
    Owner       = "data-platform"
    DataClass   = "confidential"
  }
}

output "source_prerequisites" {
  description = "What the PostgreSQL source needs before CDC works - logical WAL, the replication role, and a plan for the slot."
  value       = module.cdc_to_lake.source_prerequisites
}

output "network_contract" {
  description = "Hand to whoever owns the VPC. The S3 gateway endpoint is the one people forget."
  value       = module.cdc_to_lake.network_contract
}

output "serverless_replication_arns" {
  description = "Start and stop these with aws dms start-replication / stop-replication."
  value       = module.cdc_to_lake.serverless_replication_arns
}

output "governance" {
  description = "The posture, as data."
  value       = module.cdc_to_lake.governance
}
