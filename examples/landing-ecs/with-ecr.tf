# landing-ecs + ECR: end-to-end container workflow.
#
# What this example shows
# ───────────────────────
#   1. Two ECR repositories (api + worker) provisioned via the tf-modules ecr
#      module, with immutable tags, vulnerability scan on push, and a lifecycle
#      policy that keeps the last 10 prod images and expires untagged layers.
#   2. A landing-ecs cluster that pulls from those repositories.
#   3. A deployment variable (`ecr_image_tag`) so CI can bump the tag without
#      editing Terraform code.
#
# Push workflow (CI or local)
# ───────────────────────────
#   aws ecr get-login-password --region ${REGION} | \
#     docker login --username AWS --password-stdin ${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com
#   docker build -t ${REPO_URL}:${TAG} .
#   docker push       ${REPO_URL}:${TAG}
#
# Deploy
# ──────
#   terraform apply -target=module.ecr_api -target=module.ecr_worker -target=module.ecr_demo \
#     -var="ecr_image_tag=${TAG}"
#
# The `ecr_*` outputs below include ready-to-run docker commands.

variable "ecr_image_tag" {
  description = "Image tag to deploy. In CI, set this to the short git SHA so every push produces an immutable reference."
  type        = string
  default     = "v1"
}

variable "ecr_demo_account_id_for_cross_account_pull" {
  description = "Optional: another AWS account allowed to pull these images. Null to keep repos account-private."
  type        = string
  default     = null
}

data "aws_caller_identity" "ecr_demo" {}
data "aws_region" "ecr_demo" {}

locals {
  ecr_registry = "${data.aws_caller_identity.ecr_demo.account_id}.dkr.ecr.${data.aws_region.ecr_demo.name}.amazonaws.com"

  ecr_common_tags = {
    Project    = "landing-ecs-ecr-demo"
    Team       = "platform"
    CostCenter = "DEMO"
  }

  # Shared lifecycle policy: keep recent prod images, let untagged layers expire.
  # Lowest priority wins, so tagged-prod rules must come before the untagged rule.
  ecr_lifecycle_rules = [
    {
      rule_priority    = 1
      description      = "Keep last 10 prod-tagged images"
      tag_status       = "tagged"
      tag_prefix_list  = ["prod-", "v"]
      tag_pattern_list = []
      count_type       = "imageCountMoreThan"
      count_number     = 10
      action_type      = "expire"
    },
    {
      rule_priority    = 2
      description      = "Expire untagged layers older than 14 days"
      tag_status       = "untagged"
      tag_prefix_list  = []
      tag_pattern_list = []
      count_type       = "sinceImagePushed"
      count_number     = 14
      count_unit       = "days"
      action_type      = "expire"
    },
  ]
}

# ECR repositories.
#
# IMMUTABLE tags are a production best-practice: once pushed, a tag can't be
# overwritten, so rollback + audit always point at the same bytes. In dev you
# might prefer MUTABLE for convenience.

module "ecr_api" {
  source = "../../modules/ecr"

  repository_name      = "landing-ecs-ecr-demo/api"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true # fine for a demo; remove in prod

  scan_on_push = true

  encryption_type = "AES256"
  kms_key_arn     = null

  enable_lifecycle_policy = true
  lifecycle_rules         = local.ecr_lifecycle_rules

  create_repository_policy     = true
  repository_policy_statements = []
  allowed_principals = var.ecr_demo_account_id_for_cross_account_pull == null ? [] : [
    "arn:aws:iam::${var.ecr_demo_account_id_for_cross_account_pull}:root",
  ]
  allowed_pull_principals = []

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

  tags        = local.ecr_common_tags
  common_tags = local.ecr_common_tags
}

module "ecr_worker" {
  source = "../../modules/ecr"

  repository_name      = "landing-ecs-ecr-demo/worker"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  scan_on_push = true

  encryption_type = "AES256"
  kms_key_arn     = null

  enable_lifecycle_policy = true
  lifecycle_rules         = local.ecr_lifecycle_rules

  create_repository_policy     = true
  repository_policy_statements = []
  allowed_principals = var.ecr_demo_account_id_for_cross_account_pull == null ? [] : [
    "arn:aws:iam::${var.ecr_demo_account_id_for_cross_account_pull}:root",
  ]
  allowed_pull_principals = []

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

  tags        = local.ecr_common_tags
  common_tags = local.ecr_common_tags
}

# ECS cluster consuming the images.
#
# Note on IAM: each execution role the module creates carries
# AmazonECSTaskExecutionRolePolicy, which includes the ECR pull actions
# (ecr:GetAuthorizationToken, ecr:BatchGetImage, ecr:GetDownloadUrlForLayer,
# ecr:BatchCheckLayerAvailability). No extra wiring needed for same-account
# pulls. Cross-account pulls require a repository policy that trusts the
# puller account (set via allowed_principals above). KMS-encrypted repos
# additionally need kms:Decrypt on the execution role — add via
# task_role_statements if you switch encryption_type to KMS.

module "ecr_demo" {
  source = "../../modules/landing-ecs"

  cluster_name = "landing-ecs-ecr-demo"

  environment = "staging"
  tags        = local.ecr_common_tags

  default_subnets = data.aws_subnets.basic_default.ids

  enable_container_insights = false
  log_retention_days        = 14

  services = {
    api = {
      # Image URL is the ECR repo URL + the tag chosen by the caller.
      image  = "${module.ecr_api.repository_url}:${var.ecr_image_tag}"
      cpu    = 512
      memory = 1024
      port   = 8080

      assign_public_ip = true

      desired_count = 1
      min_count     = 1
      max_count     = 4

      health_check = {
        command      = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
        start_period = 30
      }

      # ECR itself re-tags nothing, so bumping the tag is the deployment
      # signal. The module rolls new tasks because the task-definition arn
      # changes (new image string) — circuit breaker + rollback are on by
      # default, so a bad image rolls back without intervention.

      tags = { Component = "api" }
    }

    worker = {
      image             = "${module.ecr_worker.repository_url}:${var.ecr_image_tag}"
      cpu               = 256
      memory            = 512
      capacity_strategy = "economy" # 100% Fargate Spot
      # Opt into Graviton explicitly. Build with `docker buildx` and a
      # --platform arg that includes linux/arm64 before pushing.
      cpu_architecture = "ARM64"
      assign_public_ip = true

      desired_count = 1
      min_count     = 0
      max_count     = 10

      tags = { Component = "worker" }
    }
  }
}

# Handy outputs for the push workflow.

output "ecr_registry" {
  value       = local.ecr_registry
  description = "ECR registry URL for `docker login`."
}

output "ecr_repository_urls" {
  value = {
    api    = module.ecr_api.repository_url
    worker = module.ecr_worker.repository_url
  }
  description = "Per-service ECR repo URLs. Append `:<tag>` to produce a full image reference."
}

output "ecr_docker_login_command" {
  value       = "aws ecr get-login-password --region ${data.aws_region.ecr_demo.name} | docker login --username AWS --password-stdin ${local.ecr_registry}"
  description = "Command to authenticate docker against this ECR registry."
}

output "ecr_push_commands" {
  value = {
    api    = "docker build -t ${module.ecr_api.repository_url}:${var.ecr_image_tag} . && docker push ${module.ecr_api.repository_url}:${var.ecr_image_tag}"
    worker = "docker build -t ${module.ecr_worker.repository_url}:${var.ecr_image_tag} . && docker push ${module.ecr_worker.repository_url}:${var.ecr_image_tag}"
  }
  description = "Ready-to-run build + push commands for each service."
}

output "ecr_current_image_refs" {
  value = {
    api    = "${module.ecr_api.repository_url}:${var.ecr_image_tag}"
    worker = "${module.ecr_worker.repository_url}:${var.ecr_image_tag}"
  }
  description = "Image references the ECS services are pulling right now."
}
