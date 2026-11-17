# EC2 capacity for an ECS cluster: an attribute-based Spot fleet with one
# on-demand instance, protected from scale-in so the ECS capacity provider
# drains tasks before an instance goes. Pass autoscaling_group_arn to
# modules/ecs ec2_capacity_providers[*].auto_scaling_group_arn.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

variable "cluster_name" {
  description = "The ECS cluster the instances join."
  type        = string
  default     = "orders-prod"
}

variable "private_subnet_ids" {
  description = "Private subnets in three AZs."
  type        = list(string)
  default     = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002", "subnet-0a1b2c3d4e5f60003"]
}

variable "instance_security_group_id" {
  description = "Security group for the container instances."
  type        = string
  default     = "sg-0a1b2c3d4e5f60001"
}

module "capacity" {
  source = "../.."

  name               = "orders-ecs"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.instance_security_group_id]

  # The ECS-optimized image, read at every plan; instance refresh rolls the
  # fleet when AWS publishes a new one (acknowledged below).
  ami_ssm_parameter = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  user_data         = <<-EOT
    #!/bin/bash
    cat >> /etc/ecs/ecs.config <<'CONFIG'
    ECS_CLUSTER=${var.cluster_name}
    ECS_ENABLE_SPOT_INSTANCE_DRAINING=true
    ECS_AWSVPC_BLOCK_IMDS=true
    CONFIG
  EOT

  # Any current 2-8 vCPU, 4-32 GiB Intel or AMD type.
  instance_requirements = {
    vcpu_min          = 2
    vcpu_max          = 8
    memory_mib_min    = 4096
    memory_mib_max    = 32768
    cpu_manufacturers = ["intel", "amd"]
  }
  purchase_options = {
    on_demand_base_capacity                  = 1
    on_demand_percentage_above_base_capacity = 0
  }

  min_size              = 2
  max_size              = 20
  protect_from_scale_in = true

  instance_profile = {
    managed_policies = { ecs = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role" }
  }

  # ECS marks the instances it manages.
  autoscaling_group_tags = { AmazonECSManaged = "" }

  sns_topic_arn = "arn:aws:sns:eu-west-2:111122223333:platform-alerts"
  kms_key_arn   = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  acknowledged_checks = ["ami_is_pinned"]
}

output "autoscaling_group_arn" {
  value = module.capacity.autoscaling_group_arn
}

output "kms_key_policy_requirements" {
  value = module.capacity.kms_key_policy_requirements
}
