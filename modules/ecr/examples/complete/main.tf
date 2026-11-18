# Every input, in the shape of a platform account's registry: application
# repositories with cross-account pulls and Lambda images, a release
# repository that archives what nobody pulls, and the registry's own settings
# (enhanced scanning, replication to a DR Region and a second account, pull
# through caches for Docker Hub, ECR Public and a shared ECR registry, and
# creation templates for what ECR creates).

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

locals {
  key = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
}

variable "workload_account_ids" {
  description = "Accounts whose ECS tasks and nodes pull the application images."
  type        = list(string)
  default     = ["444455556666", "777788889999"]
}

module "ecr" {
  source = "../.."

  create            = true
  name              = "platform"
  tags              = { CostCenter = "cc-0007", Owner = "platform-team", Environment = "shared" }
  required_tag_keys = ["CostCenter", "Owner"]

  image_tag_mutability = "IMMUTABLE"
  kms_key_arn          = local.key
  scan_on_push         = true
  lifecycle_policy     = { untagged_expire_days = 7, keep_last = 200 }

  repositories = {
    # Pulled by ECS tasks in the workload accounts; CI here pushes.
    "orders/api" = {
      tag_mutability_exclusions = ["latest"]
      access = {
        pull_principals = [for a in var.workload_account_ids : "arn:aws:iam::${a}:root"]
        push_principals = ["arn:aws:iam::111122223333:role/ci-orders"]
      }
      tags = { Application = "orders" }
    }

    # A Lambda function image, used by functions in a workload account.
    "orders/thumbnailer" = {
      access = { lambda_accounts = ["444455556666"] }
    }

    # Base images every team builds from, readable across the organization.
    "base/python" = {
      access = { pull_organization_ids = ["o-abcdefghij"] }
    }

    # Release artifacts kept for audit: what nobody pulls for 90 days moves to
    # archive storage, and archives go after seven years.
    "releases/orders" = {
      force_delete = false
      lifecycle_policy = {
        untagged_expire_days  = 1
        keep_last             = 0
        archive_unpulled_days = 90
        archive_expire_days   = 2557
      }
    }
  }

  registry = {
    enabled  = true
    scanning = { type = "ENHANCED", rules = [{ frequency = "CONTINUOUS_SCAN", filters = ["*"] }] }

    replication = [{
      destinations        = [{ region = "eu-west-1" }, { region = "eu-west-2", account_id = "999988887777" }]
      repository_prefixes = ["orders", "base"]
    }]
    replication_source_accounts = ["555566667777"]

    pull_through_cache = {
      "docker-hub" = { upstream = "docker-hub", credential_secret_arn = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:ecr-pullthroughcache/docker-hub-AbCdEf" }
      "ecr-public" = { upstream = "ecr-public" }
      "shared"     = { upstream = "ecr", url = "999988887777.dkr.ecr.eu-west-2.amazonaws.com", role_arn = "arn:aws:iam::111122223333:role/ecr-pull-through-shared", upstream_prefix = "golden" }
    }
    pull_through_cache_principals = ["arn:aws:iam::111122223333:role/eks-nodes"]

    creation_templates = {
      # Caches follow their upstream's tags, and keep 30 days of untouched images.
      "docker-hub" = {
        applied_for          = ["PULL_THROUGH_CACHE"]
        description          = "Docker Hub cache"
        image_tag_mutability = "MUTABLE"
        kms_key_arn          = local.key
        lifecycle_policy     = { untagged_expire_days = 7, keep_last = 0, archive_unpulled_days = 30, archive_expire_days = 90 }
      }
      ROOT = {
        applied_for          = ["PULL_THROUGH_CACHE", "REPLICATION", "CREATE_ON_PUSH"]
        image_tag_mutability = "MUTABLE"
        kms_key_arn          = local.key
        lifecycle_policy     = { keep_last = 50 }
        tags                 = { CreatedBy = "ecr-template" }
      }
    }

    policy_statements           = []
    pull_time_update_exclusions = ["arn:aws:iam::111122223333:role/third-party-scanner"]
    account_settings            = { basic_scan_type_version = "AWS_NATIVE", registry_policy_scope = "V2", blob_mounting = "ENABLED" }
  }

  sns_topic_arn = "arn:aws:sns:eu-west-2:111122223333:platform-alerts"

  acknowledged_checks = []
}

output "repository_urls" {
  value = module.ecr.repository_urls
}

output "pull_policy_json" {
  value = module.ecr.pull_policy_json
}

output "pull_through_cache_policy_json" {
  value = module.ecr.pull_through_cache_policy_json
}

output "governance" {
  value = module.ecr.governance
}

output "kms_key_policy_requirements" {
  value = module.ecr.kms_key_policy_requirements
}

output "deployer_requirements" {
  value = module.ecr.deployer_requirements
}

output "replication_destination_requirements" {
  value = module.ecr.replication_destination_requirements
}

output "notification_requirements" {
  value = module.ecr.notification_requirements
}

output "network_contract" {
  value = module.ecr.network_contract
}

output "verify_commands" {
  value = module.ecr.verify_commands
}
