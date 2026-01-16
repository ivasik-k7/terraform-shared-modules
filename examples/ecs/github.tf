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

resource "aws_security_group" "github_runner" {
  name        = "archon-hub-dev-github-runner"
  description = "Allow outbound traffic for GitHub Runner"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "archon-hub-dev-github-runner"
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ssm_parameter" "github_runner_token" {
  name        = "/archon-hub/dev/github-runner-token"
  description = "GitHub Actions runner registration token"
  type        = "SecureString"
  value       = var.github_runner_token

  tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

module "ecs" {
  source = "../../modules/ecs"

  cluster_name              = "archon-hub-dev-cluster"
  enable_container_insights = false

  services = {
    github-runner = {
      task_definition_family   = "archon-hub-dev-github-runner"
      task_cpu                 = "512"
      task_memory              = "1024"
      desired_count            = 1
      requires_compatibilities = ["FARGATE"]
      launch_type              = "FARGATE"

      container_definitions = [{
        name      = "github-runner"
        image     = "myoung34/github-runner:latest"
        cpu       = 512
        memory    = 1024
        essential = true

        environment = [
          { name = "REPO_URL", value = var.github_repo_url },
          { name = "RUNNER_NAME", value = "fargate-runner" },
          { name = "RUNNER_WORKDIR", value = "/tmp/runner" },
          { name = "LABELS", value = "fargate,docker,aws" }
        ]

        secrets = [{
          name      = "ACCESS_TOKEN"
          valueFrom = aws_ssm_parameter.github_runner_token.arn
        }]
      }]

      network_configuration = {
        subnets          = data.aws_subnets.default.ids
        security_groups  = [aws_security_group.github_runner.id]
        assign_public_ip = true
      }
    }
  }

  task_execution_role_policies = [
    "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
  ]

  create_cloudwatch_log_groups = true
  log_retention_in_days        = 7

  tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Service     = "github-runner"
  }
}

variable "github_repo_url" {
  description = "GitHub repository or organization URL (e.g., https://github.com/owner/repo or https://github.com/org-name)"
  type        = string
}

variable "github_runner_token" {
  description = "GitHub Personal Access Token (repo scope for repositories, admin:org scope for organizations)"
  type        = string
  sensitive   = true
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "service_id" {
  description = "GitHub Runner service ID"
  value       = module.ecs.service_ids["github-runner"]
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.ecs.log_group_names["github-runner"]
}

output "instructions" {
  description = "Setup instructions"
  value       = <<-EOT
    
    ✅ GitHub Actions Runner deployed on Fargate!
    
    📋 Setup:
       
       For Repository Runner:
       1. Create GitHub Personal Access Token:
          GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
          Required scopes: repo (full control)
       
       2. Deploy:
          terraform apply \
            -var="github_repo_url=https://github.com/owner/repo" \
            -var="github_runner_token=ghp_xxxxxxxxxxxxx"
       
       For Organization Runner:
       1. Create GitHub Personal Access Token:
          Required scopes: admin:org (full control)
       
       2. Deploy:
          terraform apply \
            -var="github_repo_url=https://github.com/your-org" \
            -var="github_runner_token=ghp_xxxxxxxxxxxxx"
       
       3. Manage runner groups:
          GitHub Org → Settings → Actions → Runner groups
    
    📊 View logs:
       aws logs tail ${module.ecs.log_group_names["github-runner"]} --follow --region us-east-1
    
    🔍 Check runner status:
       Repository: GitHub Repo → Settings → Actions → Runners
       Organization: GitHub Org → Settings → Actions → Runners
    
    🏷️  Use in workflows:
       jobs:
         build:
           runs-on: [self-hosted, fargate, docker, aws]
           steps:
             - uses: actions/checkout@v4
             - run: echo "Running on Fargate!"
    
    💰 Cost: ~$18/month for 1 Fargate task (0.5 vCPU, 1 GB) running 24/7
       SSM Parameter Store: FREE
    
    ⚠️  Note: This is a basic example. For production:
       - Use Fargate Spot for 70% cost savings
       - Add auto-scaling based on workflow queue
       - Use EFS for shared cache/artifacts
       - Configure runner groups for access control
       - Set up ephemeral runners (one job per runner)
    
    🚀 Cost optimization with Fargate Spot:
       Change launch_type to use capacity_provider_strategy:
       capacity_provider_strategy = [{
         capacity_provider = "FARGATE_SPOT"
         weight            = 1
       }]
       Cost: ~$5.40/month (70% savings!)
    
  EOT
}
