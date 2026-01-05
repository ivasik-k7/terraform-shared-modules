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
  region = "eu-west-1"
}

locals {
  cluster_name = "my-app-dev"
  environment  = "dev"

  tags = {
    Environment = "dev"
    Project     = "my-app"
    ManagedBy   = "Terraform"
    Owner       = "devops-team"
  }
}

################################################################################
# VPC Data (assuming VPC already exists)
################################################################################

data "aws_vpc" "main" {
  filter {
    name   = "tag:Name"
    values = ["dev-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }

  filter {
    name   = "tag:Type"
    values = ["private"]
  }
}

################################################################################
# EKS Cluster - Development Configuration
################################################################################

module "eks" {
  source = "../../modules/eks"

  cluster_name    = local.cluster_name
  cluster_version = "1.28"
  environment     = local.environment

  vpc_id     = data.aws_vpc.main.id
  subnet_ids = data.aws_subnets.private.ids

  # Development: Allow public access from office IP for easy access
  cluster_endpoint_private_access      = true
  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"] # Replace with your office IP

  # Development: Basic logging
  cluster_enabled_log_types              = ["api", "audit"]
  cloudwatch_log_group_retention_in_days = 7

  # Development: Enable encryption but allow quick setup
  enable_cluster_encryption = true
  enable_irsa               = true

  # Development: Single small node group for cost optimization
  node_groups = {
    general = {
      desired_size   = 2
      min_size       = 1
      max_size       = 4
      instance_types = ["t3.medium"]
      capacity_type  = "SPOT" # Use SPOT for dev to save costs
      disk_size      = 30

      labels = {
        role        = "general"
        environment = "dev"
      }
    }
  }

  # Development: Essential addons only
  cluster_addons = {
    vpc-cni = {
      version           = "v1.15.1-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      version           = "v1.10.1-eksbuild.2"
      resolve_conflicts = "OVERWRITE"
    }
    kube-proxy = {
      version           = "v1.28.1-eksbuild.1"
      resolve_conflicts = "OVERWRITE"
    }
  }

  # Development: Enable common IRSA roles
  enable_cluster_autoscaler           = true
  enable_ebs_csi_driver               = true
  enable_aws_load_balancer_controller = true

  # Development: Allow developers access
  access_entries = {
    dev_team = {
      principal_arn = "arn:aws:iam::123456789012:role/DevTeamRole"
      type          = "STANDARD"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }

  tags = local.tags
}
