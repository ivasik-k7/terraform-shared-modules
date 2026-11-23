# The job instances' AMI, built with modules/ami-builder from
# images/job-host/gitlab-runner-job-host.yaml. Optional: the module runs on the
# Amazon ECS-optimized Amazon Linux 2023 AMI as it is. This image adds a
# pre-pulled helper (no job waits for it), a Docker Hub mirror, and bounded
# container logs, and its test phase proves ec2-user reaches Docker.
#
# A workspace of its own: modules/ami-builder supports hashicorp/aws 5.x, the
# runner module 6.x. Pass the AMI it publishes to the runner's ami_id.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.70.0, < 6.0.0" }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  helper_repository_arn = "arn:aws:ecr:eu-west-1:111122223333:repository/ci/gitlab-runner-helper"
}

# The build instance pulls the helper with its own role, so it may pull that
# repository and nothing else.
resource "aws_iam_policy" "pull_helper" {
  name = "gitlab-runner-job-host-pull-helper"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = local.helper_repository_arn },
    ]
  })
}

module "job_host_image" {
  source = "../../../ami-builder"

  name        = "gitlab-runner-job-host"
  description = "docker-autoscaler job instance: Docker for ec2-user, helper pre-pulled"

  # The Amazon ECS-optimized Amazon Linux 2023 AMI, pinned.
  parent_image = "ami-0123456789abcdef0"

  components = [
    {
      name     = "job-host"
      document = file("${path.module}/../../images/job-host/gitlab-runner-job-host.yaml")
      parameters = {
        HelperImage    = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.6.1"
        RegistryMirror = "https://docker-hub-mirror.example.internal"
      }
    },
  ]

  additional_build_policy_arns = [aws_iam_policy.pull_helper.arn]

  instance_types     = ["m7i.large", "m6i.large"]
  subnet_id          = "subnet-0a1b2c3d4e5f60001"
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  kms_key_arn        = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  log_s3_bucket      = "image-build-logs-111122223333"
  log_s3_prefix      = "imagebuilder/gitlab-runner-job-host"

  ami_ssm_parameter_name = "/ami/gitlab-runner-job-host/latest"

  tags = { CostCenter = "cc-1042", Owner = "platform" }
}

output "ami_ssm_parameter_name" {
  value = module.job_host_image.ami_ssm_parameter_name
}

output "pipeline_arn" {
  value = module.job_host_image.pipeline_arn
}
