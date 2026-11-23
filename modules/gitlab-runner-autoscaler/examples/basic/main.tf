# One pool of unprivileged Docker jobs on the Amazon ECS-optimized Amazon
# Linux 2023 AMI, which already has Docker, with the S3 cache, alarms and a
# dashboard. Made outside this call: the images (images/manager/build.sh,
# images/mirror.sh), the runner token in SSM, the SSH key in Secrets
# Manager.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "runner" {
  source = "../.."

  name           = "ci"
  gitlab_url     = "https://gitlab.example.com"
  runner_version = "18.6.1"
  manager_image  = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-manager:18.6.1-1"
  helper_image   = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.6.1"

  vpc_id     = "vpc-0a1b2c3d4e5f60001"
  subnet_ids = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]

  ami_id                     = "ami-0123456789abcdef0"
  ssh_public_key             = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyReplaceWithYourOwn ci-runner"
  ssh_private_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-ssh-AbCdEf"
  kms_key_arn                = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  sns_topic_arn              = "arn:aws:sns:eu-west-1:111122223333:alerts"
  tags                       = { CostCenter = "cc-1042", Owner = "platform" }

  pools = {
    docker = {
      token_arn     = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
      job_image     = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
      max_instances = 10
    }
  }
}

output "dashboard_name" {
  value = module.runner.dashboard_name
}

output "verify_commands" {
  value = module.runner.verify_commands
}

output "network_contract" {
  value = module.runner.network_contract
}
