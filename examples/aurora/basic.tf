terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

module "aurora" {
  source             = "../../modules/aurora"
  cluster_identifier = "${local.name_prefix}-db-cluster"
  engine             = "aurora-postgresql"
  engine_version     = "14.6"

  instances = {
    "writer" = {
      instance_class      = "db.t3.medium"
      promotion_tier      = 0
      publicly_accessible = false
    }
  }

  master_username = "archonadmin"
  master_password = "ChangeMe12345!"

  storage_encrypted       = true
  backup_retention_period = 1
  skip_final_snapshot     = true
  deletion_protection     = false

  monitoring_interval             = 0
  performance_insights_enabled    = false
  enabled_cloudwatch_logs_exports = []

  create_security_group = true
  allowed_cidr_blocks   = ["10.0.0.0/16"]

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  tags = local.base_tags
}

output "cluster_endpoint" {
  value = module.aurora.cluster_endpoint
}

output "cluster_reader_endpoint" {
  value = module.aurora.cluster_reader_endpoint
}

output "cluster_id" {
  value = module.aurora.cluster_id
}