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

module "efs" {
  source = "../../modules/efs"

  name             = "${local.name_prefix}-file-system"
  encrypted        = true
  throughput_mode  = "bursting"
  performance_mode = "generalPurpose"

  vpc_id             = data.aws_vpc.default.id
  subnet_ids         = data.aws_subnets.default.ids
  security_group_ids = []

  create_security_group = true
  allowed_cidr_blocks   = ["10.0.0.0/16"]

  enable_backup_policy = true

  lifecycle_policy_transition_to_ia                    = "AFTER_30_DAYS"
  lifecycle_policy_transition_to_primary_storage_class = "AFTER_1_ACCESS"

  tags = merge(
    local.base_tags,
    {
      Service     = "efs"
      Application = "file-storage"
    }
  )
}

output "efs_id" {
  value = module.efs.file_system_id
}

output "efs_dns_name" {
  value = module.efs.file_system_dns_name
}