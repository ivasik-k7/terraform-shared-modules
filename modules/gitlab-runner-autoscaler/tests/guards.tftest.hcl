# Every validation and this module's check, each proven to fire on the input
# that should trip it and to stay quiet otherwise.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws", dns_suffix = "amazonaws.com" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-1" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-6da54004" }
  }
}

variables {
  name                       = "ci"
  gitlab_url                 = "https://gitlab.example.com"
  runner_version             = "18.6.1"
  manager_image              = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-manager:18.6.1-1"
  helper_image               = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.6.1"
  vpc_id                     = "vpc-0a1b2c3d4e5f60001"
  subnet_ids                 = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  ami_id                     = "ami-0123456789abcdef0"
  ssh_public_key             = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMockKeyForTestsOnly ci-runner"
  ssh_private_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-ssh-AbCdEf"
  kms_key_arn                = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555"
  sns_topic_arn              = "arn:aws:sns:eu-west-1:111122223333:alerts"
  tags                       = { CostCenter = "cc-1" }

  pools = {
    docker = {
      token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
      job_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
    }
  }
}

run "the_baseline_plans_clean" {
  command = plan

  assert {
    condition     = length(module.fleet) == 1
    error_message = "the baseline plans one pool with no warnings."
  }
}

# ---------------------------------------------------------------------------
# Versions and images
# ---------------------------------------------------------------------------

run "a_helper_image_for_another_runner_version_is_rejected" {
  # A helper that does not match the runner fails every job with "No such image".
  command = plan

  variables {
    helper_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.5.0"
  }

  expect_failures = [var.helper_image]
}

run "a_runner_version_that_is_not_x_y_z_is_rejected" {
  command = plan

  variables {
    runner_version = "18.6"
    helper_image   = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.6"
  }

  expect_failures = [var.runner_version]
}

run "a_runner_before_docker_autoscaler_was_generally_available_is_rejected" {
  command = plan

  variables {
    runner_version = "17.0.3"
    helper_image   = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v17.0.3"
  }

  expect_failures = [var.runner_version]
}

run "a_manager_image_tagged_latest_is_rejected" {
  command = plan

  variables {
    manager_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-manager:latest"
  }

  expect_failures = [var.manager_image]
}

run "a_manager_image_without_a_tag_is_rejected" {
  command = plan

  variables {
    manager_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-manager"
  }

  expect_failures = [var.manager_image]
}

run "gitlab_over_plain_http_is_rejected" {
  command = plan

  variables {
    gitlab_url = "http://gitlab.example.com"
  }

  expect_failures = [var.gitlab_url]
}

# ---------------------------------------------------------------------------
# Names and network
# ---------------------------------------------------------------------------

run "a_name_that_would_overflow_the_fleet_name_is_rejected" {
  # <name>-<pool> must fit modules/asg-group's 36 characters.
  command = plan

  variables {
    name = "a-name-of-twenty-ch"
  }

  assert {
    condition     = length(module.fleet) == 1
    error_message = "19 characters is the longest name accepted."
  }
}

run "a_twenty_character_name_is_rejected" {
  command = plan

  variables {
    name = "a-name-of-twenty-chr"
  }

  expect_failures = [var.name]
}

run "egress_to_everywhere_is_rejected" {
  command = plan

  variables {
    egress_cidr_blocks = ["0.0.0.0/0"]
  }

  expect_failures = [var.egress_cidr_blocks]
}

run "an_unknown_acknowledged_check_is_rejected" {
  command = plan

  variables {
    acknowledged_checks = ["no_such_check"]
  }

  expect_failures = [var.acknowledged_checks]
}

# ---------------------------------------------------------------------------
# Pools
# ---------------------------------------------------------------------------

run "a_pool_key_with_capitals_is_rejected" {
  command = plan

  variables {
    pools = { Docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20" } }
  }

  expect_failures = [var.pools]
}

run "a_manager_size_fargate_does_not_offer_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", manager_cpu = 512, manager_memory = 512 } }
  }

  expect_failures = [var.pools]
}

run "a_fractional_instance_count_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", max_instances = 2.5 } }
  }

  expect_failures = [var.pools]
}

run "an_on_demand_base_above_the_ceiling_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", max_instances = 2, on_demand_base = 3 } }
  }

  expect_failures = [var.pools]
}

run "an_idle_policy_without_periods_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", idle = [{ periods = [], idle_count = 1 }] } }
  }

  expect_failures = [var.pools]
}

run "a_fractional_idle_count_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", idle = [{ periods = ["* * * * *"], idle_count = 1.5 }] } }
  }

  expect_failures = [var.pools]
}

# ---------------------------------------------------------------------------
# privileged_jobs_get_their_own_instance
# ---------------------------------------------------------------------------

run "privileged_jobs_sharing_an_instance_warn" {
  command = plan

  variables {
    pools = { dind = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "docker:27.3.1", privileged = true, capacity_per_instance = 2 } }
  }

  expect_failures = [check.privileged_jobs_get_their_own_instance]
}

run "privileged_jobs_reusing_an_instance_warn" {
  command = plan

  variables {
    pools = { dind = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "docker:27.3.1", privileged = true, max_use_count = 10 } }
  }

  expect_failures = [check.privileged_jobs_get_their_own_instance]
}

run "privileged_jobs_on_their_own_instance_do_not_warn" {
  command = plan

  variables {
    pools = { dind = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "docker:27.3.1", privileged = true } }
  }

  assert {
    condition     = output.governance.pools.dind.capacity_per_instance == 1 && output.governance.pools.dind.max_use_count == 1
    error_message = "a privileged pool defaults to one job per instance and one job per instance lifetime."
  }
}

run "an_acknowledged_shared_privileged_pool_does_not_warn" {
  command = plan

  variables {
    pools               = { dind = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "docker:27.3.1", privileged = true, capacity_per_instance = 2 } }
    acknowledged_checks = ["privileged_jobs_get_their_own_instance"]
  }

  assert {
    condition     = contains(output.governance.acknowledged_checks, "privileged_jobs_get_their_own_instance")
    error_message = "the acknowledgement is listed in governance."
  }
}

run "no_topic_is_acknowledged_in_the_children_too" {
  # Without a topic both children warn; one acknowledgement silences both.
  command = plan

  variables {
    sns_topic_arn       = ""
    acknowledged_checks = ["somebody_hears_a_failure"]
  }

  assert {
    condition     = contains(module.fleet["docker"].governance.acknowledged_checks, "somebody_hears_a_failure") && contains(module.managers.governance.acknowledged_checks, "somebody_hears_a_failure")
    error_message = "somebody_hears_a_failure reaches both the fleet and the managers."
  }
}

# ---------------------------------------------------------------------------
# Tokens, AWS access, cache, monitoring
# ---------------------------------------------------------------------------

run "a_token_arn_that_is_neither_a_parameter_nor_a_secret_is_rejected" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:s3:::bucket/token", job_image = "alpine:3.20" } }
  }

  expect_failures = [var.pools]
}

run "a_token_in_secrets_manager_is_accepted" {
  command = plan

  variables {
    pools = { docker = { token_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-token-AbCdEf", job_image = "alpine:3.20" } }
  }

  assert {
    condition     = output.governance.pools.docker.token_arn == "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-token-AbCdEf"
    error_message = "a Secrets Manager secret is a token source too."
  }
}

run "aws_access_without_anything_to_grant_is_rejected" {
  command = plan

  variables {
    pools = { deploy = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", aws_access = {} } }
  }

  expect_failures = [var.pools]
}

run "jobs_holding_aws_credentials_warn" {
  command = plan

  variables {
    pools = { deploy = { token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/runner-token", job_image = "alpine:3.20", aws_access = { assume_role_arns = ["arn:aws:iam::111122223333:role/deploy"] } } }
  }

  expect_failures = [check.jobs_hold_aws_credentials]
}

run "a_cache_key_without_its_bucket_is_rejected" {
  command = plan

  variables {
    cache = { bucket_kms_key_arn = "arn:aws:kms:eu-west-1:111122223333:key/11111111-2222-3333-4444-555555555555" }
  }

  expect_failures = [var.cache]
}

run "an_unknown_cache_compression_is_rejected" {
  command = plan

  variables {
    cache = { compression_format = "rar" }
  }

  expect_failures = [var.cache]
}

run "a_ceiling_window_that_is_not_whole_periods_is_rejected" {
  command = plan

  variables {
    monitoring = { ceiling_minutes = 12 }
  }

  expect_failures = [var.monitoring]
}
