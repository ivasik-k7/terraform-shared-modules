# Three pools behind one call:
#   docker  unprivileged jobs, four to an instance, a warm instance in office hours
#   build   privileged jobs (docker:dind image builds), each on a fresh instance
#           deleted after the job, on Spot above one on-demand instance
#   deploy  jobs that assume a deploy role in AWS; a protected runner in GitLab
# With the S3 cache on an existing bucket, the runner metrics collector,
# a Docker Hub mirror, a private CA, and an extra security group for jobs that
# reach a database. Tokens, images and the SSH key are made outside this call.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-1"
}

locals {
  registry = "111122223333.dkr.ecr.eu-west-1.amazonaws.com"
  key      = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
}

module "runner" {
  source = "../.."

  name           = "ci"
  gitlab_url     = "https://gitlab.example.internal"
  runner_version = "18.6.1"
  manager_image  = "${local.registry}/ci/gitlab-runner-manager:18.6.1-1"
  helper_image   = "${local.registry}/ci/gitlab-runner-helper:x86_64-v18.6.1"
  ca_certificate_pem = join("\n", [
    "-----BEGIN CERTIFICATE-----",
    "MIIBexampleOnlyReplaceWithTheIssuingCaOfYourGitLab",
    "-----END CERTIFICATE-----",
  ])
  ecr_repository_arns    = ["arn:aws:ecr:eu-west-1:111122223333:repository/ci/*"]
  docker_registry_mirror = "https://docker-hub-mirror.example.internal"

  vpc_id                      = "vpc-0a1b2c3d4e5f60001"
  subnet_ids                  = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002", "subnet-0a1b2c3d4e5f60003"]
  egress_cidr_blocks          = ["10.0.0.0/8"]
  instance_security_group_ids = ["sg-0a1b2c3d4e5f60009"]

  # The job-host AMI from examples/job-host-ami: helper pre-pulled, Docker Hub mirror set.
  ami_id                     = "ami-0123456789abcdef0"
  ssh_public_key             = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyReplaceWithYourOwn ci-runner"
  ssh_private_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-ssh-AbCdEf"
  secrets_kms_key_arns       = [local.key]
  kms_key_arn                = local.key
  permissions_boundary_arn   = "arn:aws:iam::111122223333:policy/workload-boundary"
  sns_topic_arn              = "arn:aws:sns:eu-west-1:111122223333:alerts"
  log_retention_days         = 90
  required_tag_keys          = ["CostCenter"]
  tags                       = { CostCenter = "cc-1042", Owner = "platform" }

  cache = {
    bucket_name        = "ci-build-cache-111122223333-eu-west-1"
    bucket_kms_key_arn = local.key
    expiration_days    = 7
    max_archive_gib    = 4
  }

  monitoring = {
    metrics_collector_image = "${local.registry}/mirror/aws-otel-collector:v0.43.1"
    ceiling_minutes         = 20
  }

  pools = {
    docker = {
      token_arn      = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
      job_image      = "${local.registry}/ci/build:1.0.0"
      max_instances  = 20
      instance_types = ["m7i.xlarge", "m6i.xlarge"]
      idle = [{
        periods    = ["* 7-19 * * mon-fri"]
        timezone   = "Europe/London"
        idle_count = 4
        idle_time  = "30m"
      }]
    }
    build = {
      token_arn       = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/build/runner-token"
      job_image       = "${local.registry}/ci/docker:27.3.1"
      privileged      = true
      max_instances   = 10
      instance_types  = ["m7i.large", "m6i.large", "m5.large"]
      spot            = true
      on_demand_base  = 1
      root_volume_gib = 100
      docker_volumes  = ["/certs/client"]
    }
    deploy = {
      token_arn     = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/deploy/runner-token"
      job_image     = "${local.registry}/ci/deploy:1.0.0"
      max_instances = 4
      aws_access = {
        assume_role_arns = ["arn:aws:iam::111122223333:role/ci-deploy-workloads"]
      }
    }
  }

  # The deploy runner is protected in GitLab: only protected branches and tags run there.
  acknowledged_checks = ["jobs_hold_aws_credentials"]
}

output "verify_commands" {
  value = module.runner.verify_commands
}

output "network_contract" {
  value = module.runner.network_contract
}

output "kms_key_policy_requirements" {
  value = module.runner.kms_key_policy_requirements
}

output "job_role_trust_policies" {
  value = module.runner.job_role_trust_policies
}

output "alarm_names" {
  value = module.runner.alarm_names
}

output "governance" {
  value = module.runner.governance
}
