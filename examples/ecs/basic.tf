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

resource "aws_security_group" "ecs_tasks" {
  name        = "archon-hub-dev-ecs-tasks"
  description = "Allow HTTP traffic for ECS tasks"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "archon-hub-dev-ecs-tasks"
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
    nginx = {
      task_definition_family   = "archon-hub-dev-nginx"
      task_cpu                 = "256"
      task_memory              = "512"
      desired_count            = 1
      requires_compatibilities = ["FARGATE"]
      launch_type              = "FARGATE"

      container_definitions = [{
        name      = "nginx"
        image     = "nginx:alpine"
        cpu       = 256
        memory    = 512
        essential = true

        port_mappings = [{
          container_port = 80
          protocol       = "tcp"
        }]

        environment = [
          { name = "NGINX_HOST", value = "localhost" },
          { name = "NGINX_PORT", value = "80" }
        ]
      }]

      network_configuration = {
        subnets          = data.aws_subnets.default.ids
        security_groups  = [aws_security_group.ecs_tasks.id]
        assign_public_ip = true
      }
    }

    httpd = {
      task_definition_family   = "archon-hub-dev-httpd"
      task_cpu                 = "256"
      task_memory              = "512"
      desired_count            = 1
      requires_compatibilities = ["FARGATE"]
      launch_type              = "FARGATE"

      container_definitions = [{
        name      = "httpd"
        image     = "httpd:alpine"
        cpu       = 256
        memory    = 512
        essential = true

        port_mappings = [{
          container_port = 80
          protocol       = "tcp"
        }]
      }]

      network_configuration = {
        subnets          = data.aws_subnets.default.ids
        security_groups  = [aws_security_group.ecs_tasks.id]
        assign_public_ip = true
      }
    }

    caddy = {
      task_definition_family   = "archon-hub-dev-caddy"
      task_cpu                 = "256"
      task_memory              = "512"
      desired_count            = 1
      requires_compatibilities = ["FARGATE"]
      launch_type              = "FARGATE"

      container_definitions = [{
        name      = "caddy"
        image     = "caddy:alpine"
        cpu       = 256
        memory    = 512
        essential = true

        port_mappings = [{
          container_port = 80
          protocol       = "tcp"
        }]
      }]

      network_configuration = {
        subnets          = data.aws_subnets.default.ids
        security_groups  = [aws_security_group.ecs_tasks.id]
        assign_public_ip = true
      }
    }
  }

  create_cloudwatch_log_groups = true
  log_retention_in_days        = 1

  tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
    Service     = "ecs"
  }
}

output "cluster_id" {
  description = "ECS cluster ID"
  value       = module.ecs.cluster_id
}

output "cluster_name" {
  description = "ECS cluster name"
  value       = module.ecs.cluster_name
}

output "service_ids" {
  description = "ECS service IDs"
  value       = module.ecs.service_ids
}

output "task_definition_arns" {
  description = "Task definition ARNs"
  value       = module.ecs.task_definition_arns
}

output "log_group_names" {
  description = "CloudWatch log group names"
  value       = module.ecs.log_group_names
}

output "get_url_command" {
  description = "Command to get the public URL"
  value       = "cd ${path.module} && ./get-url.sh"
}

output "quick_access" {
  description = "Quick access instructions"
  value       = <<-EOT
    
    ✅ ECS Services deployed successfully!
    
    🌐 Services running:
       - nginx  (nginx:alpine)
       - httpd  (httpd:alpine - Apache)
       - caddy  (caddy:alpine)
    
    🔍 To get public URLs for all services:
       ./get-url.sh
    
    Or manually for each service:
       aws ecs list-tasks --cluster ${module.ecs.cluster_name} --service-name <SERVICE_NAME> --query 'taskArns[0]' --output text
       aws ecs describe-tasks --cluster ${module.ecs.cluster_name} --tasks <TASK_ARN> --query 'tasks[0].attachments[0].details[?name==`networkInterfaceId`].value' --output text
       aws ec2 describe-network-interfaces --network-interface-ids <ENI_ID> --query 'NetworkInterfaces[0].Association.PublicIp' --output text
    
    📊 View logs:
       aws logs tail /ecs/${module.ecs.cluster_name}/nginx --follow
       aws logs tail /ecs/${module.ecs.cluster_name}/httpd --follow
       aws logs tail /ecs/${module.ecs.cluster_name}/caddy --follow
    
    💰 Cost: ~$27/month for 3 Fargate tasks (0.25 vCPU, 0.5 GB each) running 24/7
    
  EOT
}
