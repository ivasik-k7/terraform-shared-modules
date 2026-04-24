# Minimal landing-ecs example: a single nginx task on Fargate in the default
# VPC. No ALB, no secrets, no autoscaling — just enough to see the module
# produce a running service.
#
# Creates:
#   ECS cluster         landing-ecs-basic
#   ECS service         landing-ecs-basic-web  (1 task, Fargate)
#   IAM roles           task execution + per-service task role
#   Log group           /ecs/landing-ecs-basic/web (14 day retention)
#   Alarms              CPU high, memory high
#
# Apply:
#   terraform init
#   terraform apply -target=module.basic
#
# Tail logs:
#   aws logs tail /ecs/landing-ecs-basic/web --follow

data "aws_vpc" "basic_default" {
  default = true
}

data "aws_subnets" "basic_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.basic_default.id]
  }
}

module "basic" {
  source = "../../modules/landing-ecs"

  cluster_name = "landing-ecs-basic"

  environment = "sandbox"
  tags = {
    Project    = "landing-ecs-demo"
    Team       = "platform"
    CostCenter = "DEMO"
  }

  default_subnets = data.aws_subnets.basic_default.ids

  # Keep the bill small for a demo.
  enable_container_insights = false
  log_retention_days        = 14

  services = {
    web = {
      image  = "nginx:alpine"
      cpu    = 256
      memory = 512
      port   = 80

      # Default VPC subnets are public; the task needs a public IP to pull
      # from Docker Hub without a NAT gateway.
      assign_public_ip = true

      desired_count = 1
      min_count     = 1
      max_count     = 3

      # capacity_strategy defaults to "stable" (100% on-demand).
      # enable_autoscaling defaults to true via the module; leave it so CPU
      # + memory target tracking kicks in.
    }
  }
}

output "basic_cluster_name" {
  value       = module.basic.cluster_name
  description = "Name of the basic-example ECS cluster."
}
