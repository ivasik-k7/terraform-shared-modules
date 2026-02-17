###############################################################################
# examples/complete/main.tf
#
# Full-featured example demonstrating every capability of the module.
###############################################################################

provider "aws" {
  region = "us-east-1"
}

locals {
  name   = "prod-app"
  region = "us-east-1"

  tags = {
    Project     = local.name
    Environment = "production"
    ManagedBy   = "Terraform"
    Owner       = "platform-team"
  }
}

###############################################################################
# VPC (use your own or a VPC module)
###############################################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = "10.0.0.0/16"

  azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = false # endpoints replace most NAT usage

  tags = local.tags
}

###############################################################################
# Source security group (EC2 instances / ECS tasks that call the endpoints)
###############################################################################

resource "aws_security_group" "workloads" {
  name        = "${local.name}-workloads"
  description = "Attached to EC2 / ECS workloads"
  vpc_id      = module.vpc.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

###############################################################################
# Restrictive endpoint policy (KMS example — only allows the current account)
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_endpoint" {
  statement {
    sid    = "AllowAccountAccess"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "s3_endpoint" {
  statement {
    sid    = "AllowS3Access"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

###############################################################################
# SNS topic for endpoint lifecycle notifications
###############################################################################

resource "aws_sns_topic" "endpoint_notifications" {
  name = "${local.name}-vpce-notifications"
  tags = local.tags
}

###############################################################################
# The module invocation
###############################################################################

module "vpc_endpoints" {
  source = "../../modules/network-endpoints"

  vpc_id = module.vpc.vpc_id
  region = local.region

  # ── Defaults (apply to all endpoints unless overridden per endpoint) ────────
  default_subnet_ids      = module.vpc.private_subnets
  default_route_table_ids = module.vpc.private_route_table_ids

  # ── Default security group configuration ────────────────────────────────────
  create_default_security_group = true
  default_security_group_name   = "${local.name}-vpce-default"

  # Allow HTTPS from the workload SG only (instead of the whole VPC CIDR)
  default_security_group_ingress_rules = [
    {
      from_port       = 443
      to_port         = 443
      protocol        = "tcp"
      security_groups = [aws_security_group.workloads.id]
      description     = "Allow HTTPS from application workloads"
    }
  ]

  # ── Endpoint definitions ─────────────────────────────────────────────────────
  endpoints = {

    # ── Storage (Gateway — no SG, no subnets, no cost per AZ) ─────────────────
    s3 = {
      service = "s3"
      policy  = data.aws_iam_policy_document.s3_endpoint.json
    }

    dynamodb = {
      service = "dynamodb"
    }

    # ── SSM Suite (required for SSM Session Manager without internet) ──────────
    ssm = {
      service = "ssm"
    }

    ssmmessages = {
      service = "ssmmessages"
    }

    ec2messages = {
      service = "ec2messages"
    }

    # ── ECR (required for pulling images inside private VPC) ───────────────────
    ecr_api = {
      service = "ecr_api"
    }

    ecr_dkr = {
      service = "ecr_dkr"
    }

    # ── KMS — with a restrictive policy and custom per-AZ subnets ─────────────
    kms = {
      service             = "kms"
      private_dns_enabled = true
      policy              = data.aws_iam_policy_document.kms_endpoint.json
      # Pin to just two AZs to reduce cost while keeping HA
      subnet_ids        = slice(module.vpc.private_subnets, 0, 2)
      notification_arns = [aws_sns_topic.endpoint_notifications.arn]
      tags              = { Sensitivity = "high" }
    }

    # ── Secrets Manager ────────────────────────────────────────────────────────
    secretsmanager = {
      service = "secretsmanager"
    }

    # ── STS (needed for IAM role assumption from inside the VPC) ──────────────
    sts = {
      service = "sts"
    }

    # ── CloudWatch — logs + metrics + events ───────────────────────────────────
    cloudwatch_logs = {
      service = "cloudwatch_logs"
    }

    cloudwatch = {
      service = "cloudwatch"
    }

    # ── ECS (if running ECS tasks that need to call the ECS API) ──────────────
    ecs = {
      service = "ecs"
    }

    ecs_agent = {
      service = "ecs_agent"
    }

    ecs_telemetry = {
      service = "ecs_telemetry"
    }

    # ── Bedrock (GenAI workloads fully private) ────────────────────────────────
    bedrock = {
      service = "bedrock"
    }

    bedrock_runtime = {
      service = "bedrock_runtime"
    }

    # ── SQS ───────────────────────────────────────────────────────────────────
    sqs = {
      service = "sqs"
    }

    # ── SNS ───────────────────────────────────────────────────────────────────
    sns = {
      service = "sns"
    }

    # ── Step Functions ─────────────────────────────────────────────────────────
    sfn = {
      service = "sfn"
    }

    # ── Disabled endpoint — stays in config but won't be provisioned ───────────
    rds = {
      service = "rds"
      enabled = false # flip to true when RDS is added to the stack
    }

    # ── Custom / third-party PrivateLink endpoint ──────────────────────────────
    datadog_agent = {
      service             = "com.datadoghq.us1-east.agent"
      type                = "Interface"
      private_dns_enabled = false
      auto_accept         = false
    }
  }

  tags = local.tags
}

###############################################################################
# Outputs
###############################################################################

output "all_endpoint_ids" {
  description = "All provisioned VPC endpoint IDs."
  value       = module.vpc_endpoints.all_endpoint_ids
}

output "s3_prefix_list_id" {
  description = "Use this in security group egress rules targeting S3."
  value       = module.vpc_endpoints.s3_prefix_list_id
}

output "dynamodb_prefix_list_id" {
  description = "Use this in security group egress rules targeting DynamoDB."
  value       = module.vpc_endpoints.dynamodb_prefix_list_id
}

output "vpce_security_group_id" {
  description = "The default security group attached to all Interface endpoints."
  value       = module.vpc_endpoints.security_group_id
}

output "ecr_dkr_dns" {
  description = "DNS entries for the ECR DKR endpoint."
  value       = module.vpc_endpoints.interface_endpoint_dns_entries["ecr_dkr"]
}
