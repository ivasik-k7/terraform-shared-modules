locals {
  create = var.create

  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  dns_suffix = coalesce(one(data.aws_partition.current[*].dns_suffix), "amazonaws.com")
  region     = coalesce(one(data.aws_region.current[*].region), "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  s3_prefix_list_id = var.s3_prefix_list_id != "" ? var.s3_prefix_list_id : coalesce(one(data.aws_ec2_managed_prefix_list.s3[*].id), "pl-00000000")

  module_tags = { ManagedBy = "Terraform", Module = "gitlab-runner-autoscaler" }
  tags        = merge(var.tags, local.module_tags)

  # Checks the design trips by construction: one manager and a zero floor per
  # pool, an SSH key for the managers, a fleet that is never refreshed, and a
  # cache bucket whose objects are disposable.
  built_in_acknowledgements = {
    fleet = ["fleet_survives_an_az", "instances_are_reached_without_ssh_keys", "launch_template_changes_reach_the_fleet"]
    ecs   = ["services_survive_an_az"]
    cache = ["versioning_is_on", "the_bucket_survives_a_destroy"]
  }
  asg_check_names = [
    "somebody_hears_a_failure", "fleet_survives_an_az", "spot_fleets_keep_an_on_demand_floor", "volumes_use_a_customer_key",
    "burstable_credits_are_bounded", "instances_have_no_public_ip", "containers_cannot_reach_instance_credentials", "ami_is_pinned",
  ]
  ecs_check_names = [
    "somebody_hears_a_failure", "deployments_roll_back", "images_are_pinned", "log_retention_is_bounded", "logs_use_a_customer_key",
    "task_costs_are_attributable", "running_task_alarms_have_data", "roles_are_not_administrators", "secrets_are_not_in_environment",
  ]
  s3_check_names = ["access_is_logged", "data_uses_a_customer_key"]

  fleet_acknowledged = distinct(concat(local.built_in_acknowledgements.fleet, [for c in var.acknowledged_checks : c if contains(local.asg_check_names, c)]))
  ecs_acknowledged   = distinct(concat(local.built_in_acknowledgements.ecs, [for c in var.acknowledged_checks : c if contains(local.ecs_check_names, c)]))
  cache_acknowledged = distinct(concat(local.built_in_acknowledgements.cache, [for c in var.acknowledged_checks : c if contains(local.s3_check_names, c)]))

  pools = { for k, p in var.pools : k => merge(p, {
    capacity_per_instance = p.capacity_per_instance != null ? p.capacity_per_instance : (p.privileged ? 1 : 4)
    max_use_count         = p.max_use_count != null ? p.max_use_count : (p.privileged ? 1 : 50)
    fleet_name            = "${var.name}-${k}"
    task_role_arn         = "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-${k}-task"
    uses_cache            = var.cache.enabled ? p.shared_cache : false
    jobs_use_aws          = p.aws_access != null
  }) }
  active_pools = local.create ? local.pools : {}

  # ECR image references resolve to their repository, so the manager's task
  # role may pull exactly the images the pools name.
  ecr_image_pattern = "^([0-9]{12})\\.dkr\\.ecr\\.([a-z0-9-]+)\\.amazonaws\\.com(?:\\.cn)?/([^:@]+)"
  image_references  = concat([var.helper_image], [for p in var.pools : p.job_image])
  image_repository_arns = flatten([for i in local.image_references : [
    for m in regexall(local.ecr_image_pattern, i) : "arn:${local.partition}:ecr:${m[1]}:${m[0]}:repository/${m[2]}"
  ]])
  pull_repository_arns = sort(distinct(concat(var.ecr_repository_arns, local.image_repository_arns)))
  ecr_registries = sort(distinct([
    for a in local.pull_repository_arns : "${split(":", a)[4]}.dkr.ecr.${split(":", a)[3]}.${local.dns_suffix}"
  ]))

  # The manager's own ~/.docker/config.json: the runner reads it for job and
  # helper images alike, and allowed_docker_credential_helpers, which governs
  # job-supplied DOCKER_AUTH_CONFIG, does not apply to it.
  # https://gitlab.com/gitlab-org/gitlab-runner/-/blob/main/helpers/docker/auth/auth.go
  docker_config = jsonencode({ credHelpers = { for r in local.ecr_registries : r => "ecr-login" } })

  ssh_key_path = "/run/fleeting/id"

  # The runner reaches Docker on an instance as ec2-user over SSH, so the
  # instance is ready once user data has put ec2-user in the docker group. sg
  # reads the group file, so it sees a membership added after this session
  # began; the retries cover a daemon user data has just restarted.
  instance_ready_command = "cloud-init status --wait >/dev/null 2>&1; for i in $(seq 1 30); do sg docker -c 'docker info' >/dev/null 2>&1 && exit 0; sleep 2; done; exit 1"

  # Cache. The created bucket's name is built here rather than read from
  # modules/s3, so every policy that names it is known at plan.
  cache_creates_bucket = local.create ? (var.cache.enabled ? var.cache.bucket_name == "" : false) : false
  cache_bucket         = var.cache.bucket_name != "" ? var.cache.bucket_name : "${var.name}-runner-cache-${local.account_id}-${local.region}"
  cache_bucket_arn     = "arn:${local.partition}:s3:::${local.cache_bucket}"
  cache_kms_key_arn    = var.cache.bucket_name != "" ? var.cache.bucket_kms_key_arn : var.kms_key_arn

  # Variables every job gets. AWS_STS_REGIONAL_ENDPOINTS keeps SDKs that still
  # default to the global STS endpoint on the regional one, which a VPC endpoint serves.
  job_environment = { for k, p in local.active_pools : k => merge(
    { AWS_REGION = local.region, AWS_DEFAULT_REGION = local.region, AWS_STS_REGIONAL_ENDPOINTS = "regional" },
    p.uses_cache ? { CACHE_COMPRESSION_LEVEL = var.cache.compression_level, CACHE_COMPRESSION_FORMAT = var.cache.compression_format } : {},
  ) }

  config_toml = { for k, p in local.active_pools : k => templatefile("${path.module}/templates/config.toml.tftpl", {
    name                   = "${var.name}-${k}"
    gitlab_url             = var.gitlab_url
    concurrent             = p.max_instances * p.capacity_per_instance
    tls_ca_file            = var.ca_certificate_pem != "" ? "/etc/gitlab-runner/certs/ca.crt" : ""
    job_image              = p.job_image
    helper_image           = var.helper_image
    privileged             = p.privileged
    volumes                = concat(["/cache"], p.docker_volumes)
    capacity_per_instance  = p.capacity_per_instance
    max_use_count          = p.max_use_count
    max_instances          = p.max_instances
    instance_ready_command = local.instance_ready_command
    autoscaling_group_name = module.fleet[k].autoscaling_group_name
    region                 = local.region
    key_path               = local.ssh_key_path
    policies               = p.idle
    environment            = [for n, v in local.job_environment[k] : "${n}=${v}"]
    listen_address         = local.collect_metrics ? "127.0.0.1:${local.metrics_port}" : ""
    cache = p.uses_cache ? {
      bucket            = local.cache_bucket
      region            = local.region
      path              = k
      max_archive_bytes = floor(var.cache.max_archive_gib * 1073741824)
    } : null
  }) }

  # The group's name is generated from <name>-<pool>-, so scaling rights are
  # scoped by that prefix and the pool tag, both known at plan.
  pool_tag_key                  = "GitLabRunnerPool"
  autoscaling_group_arn_pattern = { for k, p in local.active_pools : k => "arn:${local.partition}:autoscaling:${local.region}:${local.account_id}:autoScalingGroup:*:autoScalingGroupName/${p.fleet_name}-*" }

  # Actions from the plugin's recommended policy. SendSSHPublicKey,
  # GetPasswordData, Start/StopInstances and the standby calls are left out:
  # static credentials on Linux skip them.
  # https://gitlab.com/gitlab-org/fleet-plugins/aws/-/blob/v1.3.2/README.md
  fleeting_policy = { for k, p in local.active_pools : k => jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ScaleTheFleet"
        Effect    = "Allow"
        Action    = ["autoscaling:SetDesiredCapacity", "autoscaling:SetInstanceProtection", "autoscaling:TerminateInstanceInAutoScalingGroup"]
        Resource  = local.autoscaling_group_arn_pattern[k]
        Condition = { StringEquals = { "autoscaling:ResourceTag/${local.pool_tag_key}" = p.fleet_name } }
      },
      {
        Sid      = "SeeTheFleet"
        Effect   = "Allow"
        Action   = ["autoscaling:DescribeAutoScalingGroups", "ec2:DescribeInstances", "ec2:DescribeSpotInstanceRequests"]
        Resource = "*"
      },
    ]
  }) }

  # The manager signs cache transfers with its task role, for its own pool's
  # prefix only: a pool cannot read or poison another pool's cache.
  cache_policy = { for k, p in local.active_pools : k => jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{ Sid = "CacheObjects", Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject"], Resource = "${local.cache_bucket_arn}/${k}/*" }],
      local.cache_kms_key_arn == "" ? [] : [{
        Sid       = "CacheKey"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = local.cache_kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
      }],
    )
  }) if p.uses_cache }

  # The instance role is within reach of every job on a pool with aws_access,
  # and of any privileged job (root on the host), so it is denied the runner's
  # own secrets whatever else it is given.
  instance_role_policies = { for k, p in local.active_pools : k => merge(
    {
      not-the-runners-secrets = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = "NotTheRunnersSecrets"
          Effect   = "Deny"
          Action   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory", "secretsmanager:GetSecretValue"]
          Resource = sort(distinct(concat([for q in local.pools : q.token_arn], [var.ssh_private_key_secret_arn])))
        }]
      })
    },
    !p.jobs_use_aws ? {} : p.aws_access.policies,
    !p.jobs_use_aws ? {} : (length(p.aws_access.assume_role_arns) == 0 ? {} : {
      assume-job-roles = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Sid = "AssumeJobRoles", Effect = "Allow", Action = ["sts:AssumeRole", "sts:TagSession"], Resource = p.aws_access.assume_role_arns }]
      })
    }),
  ) }

  # What a role a job assumes must trust: any role of this pool's fleet, told
  # apart by the pool tag, since the role's own name is generated.
  job_role_trust_policies = { for k, p in local.active_pools : k => jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "GitLabRunnerPool${replace(title(replace(k, "-", " ")), " ", "")}"
      Effect    = "Allow"
      Principal = { AWS = "arn:${local.partition}:iam::${local.account_id}:root" }
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Condition = {
        ArnLike      = { "aws:PrincipalArn" = "arn:${local.partition}:iam::${local.account_id}:role/${p.fleet_name}-*" }
        StringEquals = { "aws:PrincipalTag/${local.pool_tag_key}" = p.fleet_name }
      }
    }]
  }) if p.jobs_use_aws }

  pull_policy = length(local.pull_repository_arns) == 0 ? "" : jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Sid = "EcrPull", Effect = "Allow", Action = ["ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer", "ecr:BatchCheckLayerAvailability"], Resource = local.pull_repository_arns },
    ]
  })

  secrets_kms_key_arns = sort(distinct(var.secrets_kms_key_arns))

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", { registry_mirror = var.docker_registry_mirror })

  # Monitoring. The runner logs JSON (log_format), so a level or a failure
  # reason is a field a metric filter can match.
  # https://gitlab.com/gitlab-org/gitlab-runner/-/blob/main/common/build.go
  monitoring_namespace = "GitLabRunner"
  collect_metrics      = local.create ? var.monitoring.metrics_collector_image != "" : false
  metrics_port         = 9252
  metrics_log_group    = "/gitlab-runner/${var.name}/metrics"

  # Runner and fleeting metrics worth paying for, by the labels kept as
  # dimensions. Names read in the runner, fleeting and taskscaler sources.
  metric_declarations = [
    { dimensions = [["pool", "state"]], metric_name_selectors = ["^gitlab_runner_jobs$", "^fleeting_provisioner_instances$", "^fleeting_taskscaler_tasks$"] },
    { dimensions = [["pool", "failure_reason"]], metric_name_selectors = ["^gitlab_runner_failed_jobs_total$"] },
    { dimensions = [["pool", "level"]], metric_name_selectors = ["^gitlab_runner_errors_total$"] },
    { dimensions = [["pool", "operation"]], metric_name_selectors = ["^fleeting_taskscaler_task_operations_total$", "^fleeting_provisioner_instance_operations_total$"] },
    { dimensions = [["pool"]], metric_name_selectors = ["^fleeting_taskscaler_desired_instances$", "^fleeting_provisioner_max_instances$", "^gitlab_runner_job_queue_duration_seconds_sum$", "^gitlab_runner_job_queue_duration_seconds_count$"] },
  ]

  collector_config = { for k, p in local.active_pools : k => yamlencode({
    receivers = {
      prometheus = {
        config = {
          scrape_configs = [{
            job_name        = "gitlab-runner"
            scrape_interval = "60s"
            static_configs  = [{ targets = ["127.0.0.1:${local.metrics_port}"], labels = { pool = k } }]
          }]
        }
      }
    }
    exporters = {
      awsemf = {
        namespace               = local.monitoring_namespace
        region                  = local.region
        log_group_name          = local.metrics_log_group
        log_stream_name         = k
        dimension_rollup_option = "NoDimensionRollup"
        metric_declarations     = local.metric_declarations
      }
    }
    service = { pipelines = { metrics = { receivers = ["prometheus"], exporters = ["awsemf"] } } }
  }) if local.collect_metrics }

  metrics_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "EmbeddedMetrics"
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams", "logs:DescribeLogGroups"]
      Resource = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.metrics_log_group}", "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.metrics_log_group}:*"]
    }]
  })
}
