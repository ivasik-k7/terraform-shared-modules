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

resource "aws_security_group" "gitlab_runner" {
  name        = "archon-hub-dev-gitlab-runner"
  description = "Allow outbound traffic for GitLab Runner"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "archon-hub-dev-gitlab-runner"
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_ssm_parameter" "gitlab_runner_token" {
  name        = "/archon-hub/dev/gitlab-runner-token"
  description = "GitLab Runner registration token"
  type        = "SecureString"
  value       = var.gitlab_runner_token

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
    gitlab-runner = {
      task_definition_family   = "archon-hub-dev-gitlab-runner"
      task_cpu                 = "512"
      task_memory              = "1024"
      desired_count            = 1
      requires_compatibilities = ["FARGATE"]
      launch_type              = "FARGATE"

      container_definitions = [{
        name      = "gitlab-runner"
        image     = "gitlab/gitlab-runner:alpine"
        cpu       = 512
        memory    = 1024
        essential = true

        environment = [
          { name = "RUNNER_EXECUTOR", value = "docker" },
          { name = "DOCKER_IMAGE", value = "alpine:latest" },
          { name = "GITLAB_URL", value = var.gitlab_url }
        ]

        secrets = [{
          name      = "REGISTRATION_TOKEN"
          valueFrom = aws_ssm_parameter.gitlab_runner_token.arn
        }]

        command = [
          "sh", "-c",
          "gitlab-runner register --non-interactive --url $GITLAB_URL --registration-token $REGISTRATION_TOKEN --executor docker --docker-image alpine:latest --description 'Fargate Runner' --tag-list 'fargate,docker' && gitlab-runner run"
        ]
      }]

      network_configuration = {
        subnets          = data.aws_subnets.default.ids
        security_groups  = [aws_security_group.gitlab_runner.id]
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
    Service     = "gitlab-runner"
  }
}

variable "gitlab_url" {
  description = "GitLab instance URL"
  type        = string
  default     = "https://gitlab.com"
}

variable "gitlab_runner_token" {
  description = "GitLab Runner registration token"
  type        = string
  sensitive   = true
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "service_id" {
  description = "GitLab Runner service ID"
  value       = module.ecs.service_ids["gitlab-runner"]
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = module.ecs.log_group_names["gitlab-runner"]
}

output "instructions" {
  description = "Setup instructions"
  value       = <<-EOT
    
    ✅ GitLab Runner deployed on Fargate!
    
    📋 Setup:
       1. Get your GitLab Runner registration token from:
          GitLab Project → Settings → CI/CD → Runners → New project runner
       
       2. Deploy with token:
          terraform apply -var="gitlab_runner_token=YOUR_TOKEN"
       
       3. For self-hosted GitLab:
          terraform apply -var="gitlab_url=https://gitlab.example.com" -var="gitlab_runner_token=YOUR_TOKEN"
    
    📊 View logs:
       aws logs tail ${module.ecs.log_group_names["gitlab-runner"]} --follow --region us-east-1
    
    🔍 Check runner status:
       GitLab Project → Settings → CI/CD → Runners
    
    💰 Cost: ~$18/month for 1 Fargate task (0.5 vCPU, 1 GB) running 24/7
       SSM Parameter Store: FREE (standard parameters)
       vs Secrets Manager: $0.40/month per secret
    
    ⚠️  Note: This is a basic example. For production:
       - Use Fargate Spot for cost savings
       - Add auto-scaling based on job queue
       - Use EFS for shared cache
       - Configure concurrent job limits
    
  EOT
}
