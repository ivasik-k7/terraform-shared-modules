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

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }

  lifecycle_rules = [
    {
      rule_priority    = 1
      description      = "Keep last 10 production images"
      tag_status       = "tagged"
      tag_prefix_list  = ["prod-", "production-"]
      tag_pattern_list = []
      count_type       = "imageCountMoreThan"
      count_number     = 10
      action_type      = "expire"
    },
    {
      rule_priority    = 2
      description      = "Expire untagged images older than 14 days"
      tag_status       = "untagged"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 14
      count_unit       = "days"
      action_type      = "expire"
    }
  ]
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name      = "${local.name_prefix}-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  scan_on_push = true

  encryption_type = "AES256"
  kms_key_arn     = null

  enable_lifecycle_policy = true
  lifecycle_rules         = local.lifecycle_rules

  create_repository_policy     = true
  repository_policy_statements = []
  allowed_principals           = []
  allowed_pull_principals      = []

  enable_replication = false
  replication_rules  = []

  enable_logging                = false
  cloudwatch_log_group_name     = null
  cloudwatch_log_retention_days = 7
  cloudwatch_kms_key_id         = null

  enable_registry_scanning = false
  registry_scan_type       = "BASIC"
  registry_scanning_rules  = []

  pull_through_cache_rules = {}

  enable_registry_policy = false
  registry_policy_json   = null

  tags        = local.base_tags
  common_tags = local.base_tags
}

output "repository_url" {
  value = module.ecr.repository_url
}

output "repository_arn" {
  value = module.ecr.repository_arn
}