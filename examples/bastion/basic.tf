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

data "aws_route_tables" "default" {
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

module "bastion" {
  source = "../../modules/bastion"

  name        = local.name_prefix
  environment = "dev"

  # ── Networking ────────────────────────────────────────────────
  vpc_id              = data.aws_vpc.default.id
  subnet_ids          = data.aws_subnets.default.ids
  associate_public_ip = true

  # ── Instance (free tier) ──────────────────────────────────────
  # ami_id is omitted → module auto-selects latest Amazon Linux 2023
  instance_type = "t2.micro" # free-tier eligible

  # ── SSH access ────────────────────────────────────────────────
  # Remove key_name or set to null to rely on SSM only
  key_name = null

  allowed_cidr_blocks = [] # no direct SSH ingress; use SSM instead

  # ── SSM Session Manager (no open ports needed) ────────────────
  ssm_enabled = true

  # ── Auto Scaling (single always-on instance) ──────────────────
  asg_desired_capacity = 1
  asg_min_size         = 1
  asg_max_size         = 1

  # ── Storage (free tier: up to 30 GiB gp2) ────────────────────
  root_volume_size      = 8
  root_volume_type      = "gp2"
  root_volume_encrypted = false # KMS encryption has a cost; disable for free tier

  # ── Disable paid features ─────────────────────────────────────
  cloudwatch_logs_enabled   = false
  ssm_logging_enabled       = false
  sns_notifications_enabled = false
  eip_enabled               = false
  schedule_enabled          = false
  asg_warm_pool_enabled     = false

  # ── Security hardening (free) ─────────────────────────────────
  ssh_hardening_enabled        = true
  metadata_http_tokens         = "required" # enforce IMDSv2
  asg_instance_refresh_enabled = false      # avoids accidental replacement

  tags = local.base_tags
}

# ── Outputs ───────────────────────────────────────────────────────

output "bastion_security_group_id" {
  description = "Security group ID of the bastion – attach this to Aurora, RDS, etc."
  value       = module.bastion.security_group_id
}

output "bastion_asg_name" {
  description = "Auto Scaling Group name (use to find the instance in EC2 console)."
  value       = module.bastion.autoscaling_group_name
}

output "bastion_iam_role_arn" {
  description = "IAM role ARN – useful for granting the bastion access to other services."
  value       = module.bastion.iam_role_arn
}

output "ssm_connect_command" {
  description = "Run this command to open a shell on the bastion via Session Manager."
  value       = module.bastion.ssm_connect_command
}
