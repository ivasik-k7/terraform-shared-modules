# Properties of the rendered runner: fleet shape, manager wiring, config.toml,
# IAM and contracts. The baseline is a fully configured module, so its own
# advisory checks pass.
#
# What a mock cannot show: the plugin scaling a real group, SSH reaching an
# instance, the runner accepting config.toml, a token being valid, a cache
# transfer, or a CloudWatch alarm firing. The
# Auto Scaling group name is computed, so anything built from it is unknown
# at plan and asserted after a mocked apply.

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
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:eu-west-1:111122223333:cluster/ci" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:eu-west-1:111122223333:task-definition/ci-docker:1" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-1:111122223333:log-group:/ecs/ci/docker" }
  }
  mock_resource "aws_autoscaling_group" {
    defaults = { name = "ci-docker-20261123000000000000000001", arn = "arn:aws:autoscaling:eu-west-1:111122223333:autoScalingGroup:11111111-2222-3333-4444-555555555555:autoScalingGroupName/ci-docker-20261123000000000000000001" }
  }
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-0123456789abcdef0", arn = "arn:aws:ec2:eu-west-1:111122223333:launch-template/lt-0123456789abcdef0" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0" }
  }
  mock_resource "aws_ssm_parameter" {
    defaults = { arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token" }
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
  permissions_boundary_arn   = "arn:aws:iam::111122223333:policy/boundary"
  tags                       = { CostCenter = "cc-1", Environment = "test" }

  pools = {
    docker = {
      token_arn     = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
      job_image     = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
      max_instances = 8
      idle = [{
        periods    = ["* 7-19 * * mon-fri"]
        timezone   = "Europe/London"
        idle_count = 4
        idle_time  = "20m"
      }]
    }
    dind = {
      token_arn     = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/dind/runner-token-AbCdEf"
      job_image     = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/docker:27.3.1"
      privileged    = true
      max_instances = 4
    }
  }
}

# ---------------------------------------------------------------------------
# Fleet
# ---------------------------------------------------------------------------

run "each_pool_gets_a_group_shaped_as_the_plugin_requires" {
  command = plan

  assert {
    condition = alltrue([for k, m in module.fleet : alltrue([
      m.governance.size.min == 0,
      m.governance.scale_in_protection,
      jsonencode(m.governance.suspended_processes) == jsonencode(["AZRebalance"]),
      m.governance.instance_count_owner != "terraform",
      m.governance.instance_refresh == "off",
    ])])
    error_message = "fleeting-plugin-aws needs min 0, scale-in protection, AZRebalance suspended and the count left to it; a refresh would replace instances under running jobs."
  }

  assert {
    condition     = module.fleet["docker"].governance.size.max == 8 && module.fleet["dind"].governance.size.max == 4
    error_message = "the group's maximum is the pool's max_instances, so the plugin's ceiling and the group's agree."
  }

  assert {
    condition = alltrue([for k, m in module.fleet : alltrue([
      m.governance.public_ip == "none",
      m.governance.imds_hop_limit == 1,
      m.governance.ssh_key,
      m.governance.volumes_customer_key,
    ])])
    error_message = "job instances get no public IP, keep instance credentials out of containers, accept the managers' key and encrypt volumes with the customer key."
  }

  assert {
    condition     = jsonencode(keys(module.fleet)) == jsonencode(["dind", "docker"])
    error_message = "one group per pool."
  }
}

run "instances_accept_ssh_only_from_the_managers" {
  command = plan

  assert {
    condition     = aws_vpc_security_group_ingress_rule.instance_ssh[0].from_port == 22 && aws_vpc_security_group_ingress_rule.instance_ssh[0].cidr_ipv4 == null
    error_message = "the only ingress to job instances is SSH from the manager group, never from a CIDR."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.https : r.from_port == 443 && r.cidr_ipv4 != "0.0.0.0/0"])
    error_message = "egress is 443 to the caller's CIDRs."
  }

  assert {
    condition     = alltrue([for r in aws_vpc_security_group_egress_rule.s3 : r.prefix_list_id == "pl-6da54004"])
    error_message = "both groups reach S3 through the prefix list, where ECR serves layers."
  }
}

# ---------------------------------------------------------------------------
# Managers
# ---------------------------------------------------------------------------

run "each_pool_runs_exactly_one_manager_that_stops_before_its_replacement" {
  command = plan

  assert {
    condition     = jsonencode(keys(module.managers.governance.workloads)) == jsonencode(["dind", "docker"])
    error_message = "one manager service per pool."
  }

  assert {
    condition     = length(module.managers.governance.az_rebalancing) == 0
    error_message = "AZ rebalancing would start a second manager beside the first."
  }

  assert {
    condition     = jsonencode(module.managers.governance.single_task_services) == jsonencode(["dind", "docker"])
    error_message = "a manager runs one task: GitLab requires a dedicated group per configuration."
  }

  assert {
    condition     = length(module.managers.governance.secret_looking_environment) == 0
    error_message = "the token and the SSH key reach the manager as secrets, never as environment."
  }
}

run "the_token_reaches_the_manager_from_the_callers_parameter_or_secret" {
  command = plan

  assert {
    condition     = output.governance.pools.docker.token_arn == "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token" && output.governance.pools.dind.token_arn == "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/dind/runner-token-AbCdEf"
    error_message = "the module creates no token: each pool reads the parameter or secret it is given."
  }

  assert {
    condition     = alltrue([for k, d in local.instance_role_policies : contains(jsondecode(d["not-the-runners-secrets"]).Statement[0].Resource, "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token") && contains(jsondecode(d["not-the-runners-secrets"]).Statement[0].Resource, var.ssh_private_key_secret_arn)])
    error_message = "every instance role is explicitly denied the runner tokens and the SSH key, which a privileged job or a job with aws_access could otherwise reach."
  }
}

# ---------------------------------------------------------------------------
# config.toml
# ---------------------------------------------------------------------------

run "config_toml_drives_this_pools_group_with_static_credentials" {
  command = apply

  assert {
    condition     = strcontains(output.config_toml["docker"], "name = \"ci-docker-20261123000000000000000001\"")
    error_message = "plugin_config.name is the pool's own group."
  }

  assert {
    condition = alltrue([for k, c in output.config_toml : alltrue([
      strcontains(c, "executor = \"docker-autoscaler\""),
      strcontains(c, "plugin = \"fleeting-plugin-aws\""),
      strcontains(c, "use_static_credentials = true"),
      strcontains(c, "key_path = \"/run/fleeting/id\""),
      strcontains(c, "region = \"eu-west-1\""),
      strcontains(c, "token = \"__RUNNER_TOKEN__\""),
      strcontains(c, "helper_image = \"${var.helper_image}\""),
      strcontains(c, "delete_instances_on_shutdown = true"),
      strcontains(c, "AWS_STS_REGIONAL_ENDPOINTS=regional"),
    ])])
    error_message = "every pool uses docker-autoscaler with the AWS plugin, connects with the static key, and leaves the token for the entrypoint."
  }

  assert {
    condition     = strcontains(output.config_toml["docker"], "capacity_per_instance = 4") && strcontains(output.config_toml["docker"], "max_use_count = 50") && strcontains(output.config_toml["docker"], "concurrent = 32")
    error_message = "an unprivileged pool defaults to 4 jobs per instance and 50 jobs per instance lifetime; concurrent is max_instances x capacity."
  }

  assert {
    condition     = strcontains(output.config_toml["dind"], "privileged = true") && strcontains(output.config_toml["dind"], "capacity_per_instance = 1") && strcontains(output.config_toml["dind"], "max_use_count = 1")
    error_message = "a privileged pool defaults to one job per instance, and the instance is deleted after it."
  }

  assert {
    condition     = strcontains(output.config_toml["docker"], "periods = [\"* 7-19 * * mon-fri\"]") && strcontains(output.config_toml["docker"], "idle_count = 4") && !strcontains(output.config_toml["dind"], "[[runners.autoscaler.policy]]")
    error_message = "idle policies render as [[runners.autoscaler.policy]] blocks, and a pool without them has none."
  }
}

run "the_runner_trusts_a_private_ca_only_when_given_one" {
  command = apply

  variables {
    ca_certificate_pem = "-----BEGIN CERTIFICATE-----\nMIIBmock\n-----END CERTIFICATE-----\n"
  }

  assert {
    condition     = alltrue([for k, c in output.config_toml : strcontains(c, "tls-ca-file = \"/etc/gitlab-runner/certs/ca.crt\"")])
    error_message = "with ca_certificate_pem the runner verifies GitLab against it."
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

run "the_manager_may_scale_only_its_own_group_and_pull_only_named_repositories" {
  command = plan

  assert {
    condition = alltrue([for s in jsondecode(local.fleeting_policy["docker"]).Statement : s.Sid != "ScaleTheFleet" ? true : alltrue([
      s.Resource == "arn:aws:autoscaling:eu-west-1:111122223333:autoScalingGroup:*:autoScalingGroupName/ci-docker-*",
      s.Condition.StringEquals["autoscaling:ResourceTag/GitLabRunnerPool"] == "ci-docker",
    ])])
    error_message = "scaling actions are scoped to the pool's own group: its name prefix and its pool tag, so a pool named docker cannot scale docker-big."
  }

  assert {
    condition = alltrue([for s in jsondecode(local.fleeting_policy["docker"]).Statement : alltrue([
      for a in s.Action : !contains(["ec2-instance-connect:SendSSHPublicKey", "ec2:GetPasswordData", "ec2:StartInstances", "ec2:StopInstances"], a)
    ])])
    error_message = "with static credentials on Linux the plugin needs no Instance Connect, password or start/stop rights."
  }

  assert {
    condition = jsondecode(local.pull_policy).Statement[1].Resource == [
      "arn:aws:ecr:eu-west-1:111122223333:repository/ci/build",
      "arn:aws:ecr:eu-west-1:111122223333:repository/ci/docker",
      "arn:aws:ecr:eu-west-1:111122223333:repository/ci/gitlab-runner-helper",
    ]
    error_message = "the task role pulls exactly the ECR repositories the pools' images and the helper image name."
  }

  assert {
    condition     = jsondecode(local.docker_config) == { credHelpers = { "111122223333.dkr.ecr.eu-west-1.amazonaws.com" = "ecr-login" } }
    error_message = "the manager's Docker config sends every ECR registry in use to the ecr-login helper."
  }
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

run "the_network_contract_names_what_the_plugin_calls" {
  command = plan

  assert {
    condition = alltrue([for e in ["com.amazonaws.eu-west-1.ec2", "com.amazonaws.eu-west-1.autoscaling", "com.amazonaws.eu-west-1.ecr.api", "com.amazonaws.eu-west-1.ecr.dkr", "com.amazonaws.eu-west-1.kms"] :
    contains(output.network_contract.endpoint_service_names, e)])
    error_message = "the subnets need the ec2 and autoscaling endpoints for the plugin, ECR for images, and kms for the customer key."
  }

  assert {
    condition     = contains(output.network_contract.https_hosts, "gitlab.example.com")
    error_message = "GitLab itself is a 443 destination."
  }

  assert {
    condition     = length([for r in output.kms_key_policy_requirements : r.sid]) == length(distinct([for r in output.kms_key_policy_requirements : r.sid]))
    error_message = "sids are unique across the fleets', managers' and cache's requirements."
  }

  assert {
    condition     = contains([for r in output.kms_key_policy_requirements : r.sid], "CacheSigners") && !contains([for r in output.kms_key_policy_requirements : r.sid], "CacheBucketWriters")
    error_message = "the managers, which sign cache transfers, are named on the key in place of modules/s3's symbolic writers."
  }
}

run "acknowledgements_reach_the_child_that_owns_the_check" {
  command = plan

  variables {
    acknowledged_checks = ["images_are_scanned", "volumes_use_a_customer_key", "log_retention_is_bounded"]
  }

  assert {
    condition     = contains(module.fleet["docker"].governance.acknowledged_checks, "volumes_use_a_customer_key") && !contains(module.fleet["docker"].governance.acknowledged_checks, "log_retention_is_bounded")
    error_message = "a fleet check goes to the fleets only."
  }

  assert {
    condition     = contains(module.managers.governance.acknowledged_checks, "log_retention_is_bounded") && contains(module.managers.governance.acknowledged_checks, "services_survive_an_az")
    error_message = "an ECS check goes to the managers, beside the built-in one."
  }
}

# ---------------------------------------------------------------------------
# create = false
# ---------------------------------------------------------------------------

run "create_false_plans_nothing" {
  command = plan

  variables {
    create = false
  }

  assert {
    condition = alltrue([
      length(aws_security_group.manager) == 0, length(aws_security_group.instance) == 0,
      length(aws_key_pair.managers) == 0, length(aws_cloudwatch_metric_alarm.manager_errors) == 0,
      length(aws_cloudwatch_dashboard.this) == 0, length(aws_cloudwatch_log_metric_filter.manager) == 0,
      length(module.fleet) == 0, length(aws_vpc_security_group_egress_rule.https) == 0,
    ])
    error_message = "create = false creates nothing."
  }

  assert {
    condition = alltrue([
      output.network_contract == null, output.kms_key_policy_requirements == null, output.governance == null,
      output.verify_commands == null, output.security_group_ids == null, output.cache_bucket == null,
      length(output.config_toml) == 0, length(output.autoscaling_group_names) == 0, output.dashboard_name == null,
      length(output.alarm_names) == 0, length(output.job_role_trust_policies) == 0,
      length(output.manager_service_names) == 0,
    ])
    error_message = "create = false leaves every output null or empty."
  }
}

# ---------------------------------------------------------------------------
# Cache
# ---------------------------------------------------------------------------

run "each_pool_caches_under_its_own_prefix_and_signs_only_for_it" {
  command = apply

  assert {
    condition     = strcontains(output.config_toml["docker"], "Path = \"docker\"") && strcontains(output.config_toml["docker"], "DualStack = false") && strcontains(output.config_toml["docker"], "AuthenticationType = \"iam\"")
    error_message = "the cache is S3 with the task role, under the pool's prefix, on the regional (not dual-stack) endpoint the gateway endpoint serves."
  }

  assert {
    condition     = jsondecode(local.cache_policy["docker"]).Statement[0].Resource == "arn:aws:s3:::ci-runner-cache-111122223333-eu-west-1/docker/*"
    error_message = "a manager may sign only for its own pool's prefix, so one pool cannot read or poison another's cache."
  }

  assert {
    condition     = strcontains(output.config_toml["docker"], "CACHE_COMPRESSION_FORMAT=tarzstd") && strcontains(output.config_toml["docker"], "CACHE_COMPRESSION_LEVEL=fast")
    error_message = "cache archives default to tar+zstd at the fast level."
  }

  assert {
    condition     = output.cache_bucket.created && output.governance.cache.expiration_days == 14
    error_message = "without a bucket the module creates one, and its objects expire."
  }
}

run "no_cache_means_no_bucket_and_no_cache_section" {
  command = plan

  variables {
    cache = { enabled = false }
  }

  assert {
    condition     = output.cache_bucket == null && length(local.cache_policy) == 0
    error_message = "cache.enabled = false creates no bucket and grants nothing."
  }
}

# ---------------------------------------------------------------------------
# AWS access for jobs
# ---------------------------------------------------------------------------

run "a_pool_with_aws_access_exposes_its_role_and_nothing_else_does" {
  command = plan

  variables {
    acknowledged_checks = ["jobs_hold_aws_credentials"]
    pools = {
      docker = {
        token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
        job_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
      }
      deploy = {
        token_arn  = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/deploy/runner-token"
        job_image  = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
        aws_access = { assume_role_arns = ["arn:aws:iam::111122223333:role/deploy-prod"] }
      }
    }
  }

  assert {
    condition     = module.fleet["deploy"].governance.imds_hop_limit == 2 && module.fleet["docker"].governance.imds_hop_limit == 1
    error_message = "only the pool with aws_access lets containers reach the instance role."
  }

  assert {
    condition     = jsondecode(local.instance_role_policies["deploy"]["assume-job-roles"]).Statement[0].Resource == ["arn:aws:iam::111122223333:role/deploy-prod"] && !contains(keys(local.instance_role_policies["docker"]), "assume-job-roles")
    error_message = "the deploy pool's instance role may assume exactly its job roles; other pools get none."
  }

  assert {
    condition     = jsondecode(output.job_role_trust_policies["deploy"]).Statement[0].Condition.StringEquals["aws:PrincipalTag/GitLabRunnerPool"] == "ci-deploy" && !contains(keys(output.job_role_trust_policies), "docker")
    error_message = "the trust policy admits the deploy fleet's role by pool tag and name prefix, and exists only for pools with aws_access."
  }

  assert {
    condition     = contains(output.network_contract.interface_endpoints, "sts")
    error_message = "jobs that assume roles need the STS endpoint."
  }
}

# ---------------------------------------------------------------------------
# Monitoring
# ---------------------------------------------------------------------------

run "every_pool_is_watched" {
  command = apply

  assert {
    condition     = alltrue([for k in ["docker", "dind"] : alltrue([for a in ["manager_errors", "system_failures", "at_ceiling", "instances_without_manager", "running_tasks"] : contains(keys(output.alarm_names[k]), a)])])
    error_message = "each pool has error, system-failure, ceiling and orphaned-instance alarms, besides the manager's running-task alarm."
  }

  assert {
    condition     = aws_cloudwatch_log_metric_filter.manager["docker-system-failures"].pattern == "{ $.failure_reason = \"runner_system_failure\" }"
    error_message = "system failures are counted from the field the runner logs them with."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.at_ceiling["docker"].threshold == 8 && aws_cloudwatch_metric_alarm.instances_without_manager["docker"].alarm_actions == toset([var.sns_topic_arn])
    error_message = "the ceiling alarm fires at max_instances, and alarms notify the topic."
  }

  assert {
    condition     = output.dashboard_name == "ci-gitlab-runner"
    error_message = "one dashboard covers every pool."
  }
}

run "the_collector_sidecar_scrapes_the_runner_when_given_an_image" {
  command = apply

  variables {
    monitoring = { metrics_collector_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/mirror/aws-otel-collector:v0.43.1" }
  }

  assert {
    condition     = strcontains(output.config_toml["docker"], "listen_address = \"127.0.0.1:9252\"") && strcontains(local.collector_config["docker"], "127.0.0.1:9252")
    error_message = "the runner listens on localhost only, where the sidecar in the same task scrapes it."
  }

  assert {
    condition     = contains(keys(output.alarm_names["docker"]), "acquire_timeouts") && length(aws_cloudwatch_log_group.metrics) == 1
    error_message = "with the collector, jobs that time out waiting for an instance raise an alarm."
  }
}
