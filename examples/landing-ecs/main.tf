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
  region = var.aws_region
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_vpc" "main" {
  tags = { Name = var.vpc_name }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = { Tier = "private" }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
  tags = { Tier = "public" }
}

# ECR image base, built from the current account + region rather than hard-coded.
locals {
  ecr_base = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${data.aws_region.current.name}.amazonaws.com"
}

# Shared infra that the services hang off.
resource "aws_secretsmanager_secret" "db" {
  name                    = "/${var.project}/${var.environment}/db-url"
  description             = "PostgreSQL connection URL"
  recovery_window_in_days = 7

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-${var.environment}-ecs-alerts"

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${var.project}-${var.environment}-jobs"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 300

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

resource "aws_s3_bucket" "assets" {
  bucket = "${var.project}-${var.environment}-assets-${data.aws_caller_identity.current.account_id}"

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

# ALB + target group fronting the API service.
resource "aws_lb" "api" {
  name               = "${var.project}-${var.environment}-api"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.public.ids

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

resource "aws_lb_target_group" "api" {
  name        = "${var.project}-${var.environment}-api"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.main.id

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
  }

  tags = {
    Environment = var.environment
    Project     = var.project
    Team        = var.team
  }
}

# Example scenario: an on-prem monolith being broken into services on ECS.
#
# Service topology:
#   api      (master)    on-demand Fargate, ALB, X-Ray, autoscale 2-10
#   worker   (worker)    economy (Spot + Graviton ARM64), autoscale 0-20
#   migrate  (scheduled) spot only, desired_count=0, triggered externally
#
# Cost profile:
#   prod:    api=stable, worker=economy, no schedule_scaling
#   staging: schedule_scaling scales both to zero overnight
module "ecs" {
  source = "../../modules/landing-ecs"

  cluster_name = "${var.project}-${var.environment}"

  environment = var.environment
  tags = {
    Project    = var.project
    Team       = var.team
    CostCenter = var.cost_center
    GitRepo    = "github.com/${var.github_org}/${var.project}"
  }

  vpc_id          = data.aws_vpc.main.id
  default_subnets = data.aws_subnets.private.ids

  # ECS Exec is handy in non-prod; Container Insights is on prod only to save $.
  enable_execute_command         = var.environment != "prod"
  create_service_security_groups = true
  enable_container_insights      = var.environment == "prod"

  global_environment = {
    AWS_REGION   = data.aws_region.current.name
    CLUSTER_NAME = "${var.project}-${var.environment}"
    ENVIRONMENT  = var.environment
  }

  services = {

    # REST API. Stable on-demand Fargate for predictable latency, with ALB,
    # X-Ray, health check, and autoscaling between 2 and 10 replicas.
    api = {
      role              = "master"
      image             = "${local.ecr_base}/${var.project}-api:${var.app_version}"
      cpu               = 512
      memory            = 1024
      port              = 8080
      capacity_strategy = "stable"

      desired_count = 2
      min_count     = 2
      max_count     = 10

      # Scale to zero overnight on non-prod.
      schedule_scaling = var.environment != "prod" ? {
        scale_down_cron    = "cron(0 20 ? * MON-FRI *)"
        scale_up_cron      = "cron(0 7 ? * MON-FRI *)"
        scale_down_min_cap = 0
        scale_down_max_cap = 0
        scale_up_min_cap   = 1
        scale_up_max_cap   = 5
      } : null

      load_balancer = {
        target_group_arn = aws_lb_target_group.api.arn
        container_port   = 8080
      }

      health_check = {
        command      = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
        interval     = 30
        timeout      = 5
        retries      = 3
        start_period = 60
      }

      secrets = {
        DATABASE_URL = aws_secretsmanager_secret.db.arn
      }

      environment = {
        PORT      = "8080"
        LOG_LEVEL = var.environment == "prod" ? "warn" : "debug"
        TRACING   = "true"
      }

      task_role_statements = [
        {
          sid       = "AssetsReadWrite"
          actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
          resources = ["${aws_s3_bucket.assets.arn}/*"]
        },
        {
          sid       = "AssetsBucketList"
          actions   = ["s3:ListBucket"]
          resources = [aws_s3_bucket.assets.arn]
        },
        {
          sid       = "JobEnqueue"
          actions   = ["sqs:SendMessage"]
          resources = [aws_sqs_queue.jobs.arn]
        }
      ]

      xray_enabled                      = true
      enable_circuit_breaker            = true
      enable_rollback                   = true
      health_check_grace_period_seconds = 60

      tags = { Component = "api" }
    }

    # Background job processor. Spot + Graviton is fine because tasks are
    # stateless and SQS re-queues on visibility-timeout expiry. Autoscales
    # between 0 and 20 on CPU pressure.
    worker = {
      role              = "worker"
      image             = "${local.ecr_base}/${var.project}-worker:${var.app_version}"
      cpu               = 256
      memory            = 512
      capacity_strategy = "economy"

      desired_count = 1
      min_count     = 0
      max_count     = 20

      schedule_scaling = var.environment != "prod" ? {
        scale_down_cron    = "cron(0 20 ? * MON-FRI *)"
        scale_up_cron      = "cron(0 7 ? * MON-FRI *)"
        scale_down_min_cap = 0
        scale_down_max_cap = 0
        scale_up_min_cap   = 0
        scale_up_max_cap   = 5
      } : null

      secrets = {
        DATABASE_URL = aws_secretsmanager_secret.db.arn
      }

      environment = {
        WORKER_CONCURRENCY = "5"
        QUEUE_URL          = aws_sqs_queue.jobs.url
        LOG_LEVEL          = var.environment == "prod" ? "info" : "debug"
      }

      task_role_statements = [
        {
          sid       = "SQSConsume"
          actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
          resources = [aws_sqs_queue.jobs.arn]
        },
        {
          sid       = "AssetsRead"
          actions   = ["s3:GetObject"]
          resources = ["${aws_s3_bucket.assets.arn}/*"]
        }
      ]

      health_check = {
        command      = ["CMD-SHELL", "test -f /tmp/healthy || exit 1"]
        interval     = 60
        timeout      = 5
        retries      = 3
        start_period = 30
      }

      tags = { Component = "worker" }
    }

    # DB migration runner. Stays at desired_count=0 and is kicked by a
    # pipeline step (or `aws ecs update-service --desired-count 1`). Spot is
    # safe here — if it gets interrupted we just rerun.
    migrate = {
      role              = "scheduled"
      image             = "${local.ecr_base}/${var.project}-api:${var.app_version}"
      cpu               = 512
      memory            = 1024
      capacity_strategy = "spot_only"

      desired_count      = 0
      min_count          = 0
      max_count          = 1
      enable_autoscaling = false

      # Allow starting a new migration even when zero tasks are currently running.
      deployment_minimum_healthy_percent = 0
      deployment_maximum_percent         = 100

      secrets = {
        DATABASE_URL = aws_secretsmanager_secret.db.arn
      }

      environment = {
        RUN_MODE  = "migrate"
        LOG_LEVEL = "info"
      }

      tags = { Component = "migrate" }
    }
  }

  log_retention_days          = var.environment == "prod" ? 90 : 14
  create_cloudwatch_alarms    = true
  create_cloudwatch_dashboard = true
  alarm_actions               = [aws_sns_topic.alerts.arn]
  alarm_cpu_threshold         = 75
  alarm_memory_threshold      = 80
}
