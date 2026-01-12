################################################################################
# Development Environment Example
################################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

################################################################################
# Data Sources
################################################################################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

################################################################################
# Project Configuration - archon-hub
################################################################################

locals {
  project_name = "archon-hub"
  environment  = "dev"

  name_prefix = "${local.project_name}-${local.environment}"

  ecr_repository_name = "${local.name_prefix}-master-application"

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
      description      = "Expire dev images older than 7 days"
      tag_status       = "tagged"
      tag_prefix_list  = ["dev-", "test-"]
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 7
      count_unit       = "days"
      action_type      = "expire"
    },
    {
      rule_priority    = 3
      description      = "Expire untagged images older than 14 days"
      tag_status       = "untagged"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 14
      count_unit       = "days"
      action_type      = "expire"
    },
    {
      rule_priority    = 4
      description      = "Keep last 30 images (catch-all)"
      tag_status       = "any"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "imageCountMoreThan"
      count_number     = 30
      action_type      = "expire"
    }
  ]

  base_tags = {
    Project     = local.project_name
    Environment = local.environment
    ManagedBy   = "Terraform"
    CreatedDate = "2026-01-08"
    CostCenter  = "engineering"
  }

  ecr_tags = merge(
    local.base_tags,
    {
      Service     = "ecr"
      Application = "container-registry"
      Team        = "platform"
      Owner       = "devops-team"
    }
  )

  enable_image_scanning = true      # FREE: 1 basic scan per push
  enable_logging        = false     # COST: Avoid CloudWatch charges
  enable_replication    = false     # COST: Avoid data transfer charges
  encryption_type       = "AES256"  # FREE: AWS-managed encryption
  image_tag_mutability  = "MUTABLE" # FREE: Reuse tags, save storage
  force_delete          = true      # DEV: Allow easy cleanup
}

################################################################################
# ECR Module - archon-hub Container Registry
################################################################################

module "ecr" {
  count  = 0
  source = "./modules/ecr"

  repository_name      = local.ecr_repository_name
  image_tag_mutability = local.image_tag_mutability
  force_delete         = local.force_delete

  scan_on_push = local.enable_image_scanning

  encryption_type = local.encryption_type
  kms_key_arn     = null

  enable_lifecycle_policy = true
  lifecycle_rules         = local.lifecycle_rules

  create_repository_policy     = true
  repository_policy_statements = [] # Use default account access
  allowed_principals           = [] # No cross-account = no data transfer costs
  allowed_pull_principals      = []

  enable_replication = local.enable_replication
  replication_rules  = []

  enable_logging                = local.enable_logging
  cloudwatch_log_group_name     = null
  cloudwatch_log_retention_days = 7
  cloudwatch_kms_key_id         = null

  enable_registry_scanning = false
  registry_scan_type       = "BASIC"
  registry_scanning_rules  = []

  pull_through_cache_rules = {}

  enable_registry_policy = false
  registry_policy_json   = null

  tags        = local.ecr_tags
  common_tags = local.base_tags
}

################################################################################
# Aurora Module - archon-hub Database Cluster
################################################################################

module "aurora" {
  count              = 0
  source             = "./modules/aurora"
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

################################################################################
# EFS
################################################################################

module "efs" {
  count  = 0
  source = "./modules/efs"

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
      Team        = "platform"
      Owner       = "devops-team"
    }
  )

}

################################################################################
# SQS
################################################################################

module "sqs" {
  count  = 0
  source = "./modules/sqs"

  name = "${local.name_prefix}-main-queue"

  create_dlq                    = true
  message_retention_seconds     = 1209600
  dlq_message_retention_seconds = 1209600

  max_receive_count         = 5
  receive_wait_time_seconds = 20
  fifo_queue                = false

  sqs_managed_sse_enabled = true
  kms_master_key_id       = null

  tags = merge(
    local.base_tags,
    {
      Service     = "sqs"
      Application = "message-queue"
      Team        = "platform"
      Owner       = "devops-team"
    }
  )
}


################################################################################
# Outputs
################################################################################

# output "repository_url" {
#   description = "ECR Repository URL"
#   value       = module.ecr.repository_url
# }

# output "repository_arn" {
#   description = "ECR Repository ARN"
#   value       = module.ecr.repository_arn
# }

# output "repository_name" {
#   description = "ECR Repository Name"
#   value       = module.ecr.repository_name
# }

# output "registry_id" {
#   description = "AWS Account ID (Registry ID)"
#   value       = module.ecr.registry_id
# }

# output "repository_policy_statements" {
#   description = "Repository Policy Statements"
#   value       = module.ecr.repository_policy_statements
#   sensitive   = true
# }
