locals {
  create = var.create

  # Module keys last, so a caller's tags cannot override them.
  module_tags = {
    "ManagedBy" = "Terraform"
    "Module"    = "ecs"
  }
  common_tags = merge(var.tags, local.module_tags)

  # Placeholders so ARN strings still build when create = false.
  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  acknowledged = toset(var.acknowledged_checks)

  # Built, not read from resources, so contracts and policies are known at plan.
  cluster_arn        = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:cluster/${var.name}"
  log_group_prefix   = "/ecs/${var.name}"
  schedule_group_arn = "arn:${local.partition}:scheduler:${local.region}:${local.account_id}:schedule-group/${var.name}"

  # ---------------------------------------------------------------------------
  # Workloads
  # ---------------------------------------------------------------------------

  services      = local.create ? var.services : {}
  workload_tags = { for k, s in local.services : k => merge(var.tags, s.tags, local.module_tags) }
  long_running  = { for k, s in local.services : k => s if contains(["service", "daemon"], s.workload) }
  # Four service resources, because ignore_changes cannot be conditional:
  # who owns desired_count (autoscaling) and who owns the running revision
  # (an external pipeline, with ignore_task_definition_changes).
  scaled             = { for k, s in local.long_running : k => s if s.autoscaling != null }
  static             = { for k, s in local.long_running : k => s if s.autoscaling == null ? !s.deployment.ignore_task_definition_changes : false }
  autoscaled         = { for k, s in local.long_running : k => s if s.autoscaling != null ? !s.deployment.ignore_task_definition_changes : false }
  static_ignored     = { for k, s in local.long_running : k => s if s.autoscaling == null ? s.deployment.ignore_task_definition_changes : false }
  autoscaled_ignored = { for k, s in local.long_running : k => s if s.autoscaling != null ? s.deployment.ignore_task_definition_changes : false }
  scheduled          = { for k, s in local.services : k => s if s.workload == "scheduled" }
  replica            = { for k, s in local.long_running : k => s if s.workload == "service" }

  exec_configuration    = var.execute_command.kms_key_arn != "" ? true : var.execute_command.logging != "DEFAULT"
  storage_configuration = var.fargate_ephemeral_storage_kms_key_arn != "" ? true : var.managed_storage_kms_key_arn != ""
  cluster_configuration = local.exec_configuration ? true : local.storage_configuration

  log_group_name     = { for k, s in local.services : k => s.log_group.name != "" ? s.log_group.name : "${local.log_group_prefix}/${k}" }
  log_group_arn      = { for k, n in local.log_group_name : k => "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${n}" }
  created_log_groups = { for k, s in local.services : k => s if s.log_group.create }
  log_retention      = { for k, s in local.created_log_groups : k => s.log_group.retention_days != null ? s.log_group.retention_days : var.log_retention_days }
  # The key a workload's log group is encrypted with: its own, else the
  # module's for a group the module creates. An existing group without one is
  # taken to use CloudWatch Logs' own encryption.
  log_key  = { for k, s in local.services : k => s.log_group.kms_key_arn != "" ? s.log_group.kms_key_arn : (s.log_group.create ? var.log_kms_key_arn : "") }
  log_keys = distinct([for k, key in local.log_key : key if key != ""])

  # ---------------------------------------------------------------------------
  # Capacity
  # ---------------------------------------------------------------------------

  capacity_presets = {
    on_demand      = [{ capacity_provider = "FARGATE", weight = 1, base = 0 }]
    balanced       = [{ capacity_provider = "FARGATE", weight = 1, base = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 }]
    spot_preferred = [{ capacity_provider = "FARGATE", weight = 1, base = 0 }, { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }]
    spot_only      = [{ capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }]
  }

  ec2_provider_name = { for k, p in var.ec2_capacity_providers : k => "${var.name}-${k}" }
  mi_provider_name  = { for k, p in var.managed_instances_capacity_providers : k => "${var.name}-${k}" }
  provider_name     = merge(local.ec2_provider_name, local.mi_provider_name)

  default_is_preset = contains(keys(local.capacity_presets), var.default_capacity)
  cluster_default_strategy = local.default_is_preset ? local.capacity_presets[var.default_capacity] : [
    { capacity_provider = lookup(local.provider_name, var.default_capacity, var.default_capacity), weight = 1, base = 0 }
  ]
  fargate_default_strategy = local.default_is_preset ? local.capacity_presets[var.default_capacity] : local.capacity_presets.on_demand

  # A daemon uses launch_type EC2 and no strategy. Everything else always sends
  # a strategy, so a change of strategy is an update, never a launch_type swap.
  strategy = { for k, s in local.services : k => (
    s.workload == "daemon" ? [] : (
      length(s.capacity_provider_strategy) > 0 ? [
        for p in s.capacity_provider_strategy : {
          capacity_provider = s.launch == "FARGATE" ? p.capacity_provider : lookup(local.provider_name, p.capacity_provider, p.capacity_provider)
          weight            = p.weight
          base              = p.base
        }
        ] : (
        s.capacity == "" ? local.fargate_default_strategy : (
          s.launch == "FARGATE" ? local.capacity_presets[s.capacity] : [
            { capacity_provider = lookup(local.provider_name, s.capacity, s.capacity), weight = 1, base = 0 }
          ]
        )
      )
    )
  ) }

  spot_providers = concat(["FARGATE_SPOT"], [for k, p in var.managed_instances_capacity_providers : local.mi_provider_name[k] if p.capacity_option_type == "SPOT"])
  spot_weight    = { for k, st in local.strategy : k => sum(concat([0], [for p in st : p.weight if contains(local.spot_providers, p.capacity_provider)])) }
  on_demand_floor = { for k, st in local.strategy : k => (
    sum(concat([0], [for p in st : p.base if !contains(local.spot_providers, p.capacity_provider)])) > 0 ? true : sum(concat([0], [for p in st : p.weight if !contains(local.spot_providers, p.capacity_provider)])) > 0
  ) }

  # Managed Instances. The managed infrastructure policy passes only roles
  # named ecsInstanceRole*; the module's own instance role is named so, and a
  # supplied profile's role is granted by ARN instead.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/managed-instances-instance-profile.html
  managed_instances         = local.create ? var.managed_instances_capacity_providers : {}
  create_instance_profile   = anytrue([for k, p in local.managed_instances : p.instance_profile_arn == ""])
  supplied_instance_profile = { for k, p in local.managed_instances : k => element(split("/", p.instance_profile_arn), length(split("/", p.instance_profile_arn)) - 1) if p.instance_profile_arn != "" }
  instance_role_name        = "ecsInstanceRole-${var.name}"
  instance_role_arn         = "arn:${local.partition}:iam::${local.account_id}:role/${local.instance_role_name}"

  # ---------------------------------------------------------------------------
  # Containers
  # ---------------------------------------------------------------------------

  # The image shortcut becomes one container named after the service, with the
  # same shape as an entry of containers, so one builder renders both.
  containers = { for k, s in local.services : k => length(s.containers) > 0 ? s.containers : {
    (k) = {
      image                      = s.image
      essential                  = true
      cpu                        = 0
      memory                     = 0
      memory_reservation         = 0
      command                    = s.command
      entrypoint                 = []
      working_directory          = ""
      user                       = ""
      environment                = s.environment
      secrets                    = s.secrets
      environment_files          = []
      port_mappings              = s.port > 0 ? [{ container_port = s.port, name = k, protocol = "tcp", app_protocol = "", host_port = 0 }] : []
      mount_points               = []
      volumes_from               = []
      depends_on                 = {}
      health_check               = length(s.health_check) > 0 ? { command = s.health_check, interval = 30, timeout = 5, retries = 3, start_period = 0 } : null
      readonly_root_filesystem   = false
      privileged                 = false
      init_process_enabled       = s.enable_execute_command
      capabilities_add           = []
      capabilities_drop          = []
      ulimits                    = {}
      docker_labels              = {}
      start_timeout              = 0
      stop_timeout               = 0
      repository_credentials_arn = ""
      log_driver                 = "awslogs"
      log_options                = {}
      log_secret_options         = {}
      firelens                   = null
    }
  } }

  # Keys whose value is empty or zero are left out, because ECS leaves them out
  # of what it returns and the provider would otherwise show a diff forever.
  container_definitions = { for k, cs in local.containers : k => jsonencode([
    for n, c in cs : merge(
      {
        name                   = n
        image                  = c.image
        essential              = c.essential
        readonlyRootFilesystem = c.readonly_root_filesystem
      },
      c.cpu > 0 ? { cpu = c.cpu } : {},
      c.memory > 0 ? { memory = c.memory } : {},
      c.memory_reservation > 0 ? { memoryReservation = c.memory_reservation } : {},
      length(c.command) > 0 ? { command = c.command } : {},
      length(c.entrypoint) > 0 ? { entryPoint = c.entrypoint } : {},
      c.working_directory != "" ? { workingDirectory = c.working_directory } : {},
      c.user != "" ? { user = c.user } : {},
      c.privileged ? { privileged = true } : {},
      length(merge(var.global_environment, c.environment)) > 0 ? {
        environment = [for name, value in merge(var.global_environment, c.environment) : { name = name, value = value }]
      } : {},
      length(merge(var.global_secrets, c.secrets)) > 0 ? {
        secrets = [for name, arn in merge(var.global_secrets, c.secrets) : { name = name, valueFrom = arn }]
      } : {},
      length(c.environment_files) > 0 ? { environmentFiles = [for f in c.environment_files : { value = f, type = "s3" }] } : {},
      length(c.port_mappings) > 0 ? {
        portMappings = [for p in c.port_mappings : merge(
          { containerPort = p.container_port, protocol = p.protocol },
          p.host_port > 0 ? { hostPort = p.host_port } : {},
          p.name != "" ? { name = p.name } : {},
          p.app_protocol != "" ? { appProtocol = p.app_protocol } : {},
        )]
      } : {},
      length(c.mount_points) > 0 ? {
        mountPoints = [for m in c.mount_points : { sourceVolume = m.source_volume, containerPath = m.container_path, readOnly = m.read_only }]
      } : {},
      length(c.volumes_from) > 0 ? {
        volumesFrom = [for v in c.volumes_from : { sourceContainer = v.source_container, readOnly = v.read_only }]
      } : {},
      length(c.depends_on) > 0 ? {
        dependsOn = [for d, cond in c.depends_on : { containerName = d, condition = cond }]
      } : {},
      c.health_check == null ? {} : {
        healthCheck = merge(
          { command = c.health_check.command, interval = c.health_check.interval, timeout = c.health_check.timeout, retries = c.health_check.retries },
          c.health_check.start_period > 0 ? { startPeriod = c.health_check.start_period } : {},
        )
      },
      c.init_process_enabled || length(c.capabilities_add) > 0 || length(c.capabilities_drop) > 0 ? {
        linuxParameters = merge(
          c.init_process_enabled ? { initProcessEnabled = true } : {},
          length(c.capabilities_add) + length(c.capabilities_drop) > 0 ? {
            capabilities = merge(
              length(c.capabilities_add) > 0 ? { add = c.capabilities_add } : {},
              length(c.capabilities_drop) > 0 ? { drop = c.capabilities_drop } : {},
            )
          } : {},
        )
      } : {},
      length(c.ulimits) > 0 ? {
        ulimits = [for name, u in c.ulimits : { name = name, softLimit = u.soft, hardLimit = u.hard }]
      } : {},
      length(c.docker_labels) > 0 ? { dockerLabels = c.docker_labels } : {},
      c.start_timeout > 0 ? { startTimeout = c.start_timeout } : {},
      c.stop_timeout > 0 ? { stopTimeout = c.stop_timeout } : {},
      c.repository_credentials_arn != "" ? { repositoryCredentials = { credentialsParameter = c.repository_credentials_arn } } : {},
      c.firelens == null ? {} : {
        firelensConfiguration = merge({ type = c.firelens.type }, length(c.firelens.options) > 0 ? { options = c.firelens.options } : {})
      },
      {
        logConfiguration = merge(
          { logDriver = c.log_driver },
          c.log_driver == "awslogs" ? {
            options = merge({
              "awslogs-group"         = local.log_group_name[k]
              "awslogs-region"        = local.region
              "awslogs-stream-prefix" = k
            }, c.log_options)
          } : (length(c.log_options) > 0 ? { options = c.log_options } : {}),
          length(c.log_secret_options) > 0 ? {
            secretOptions = [for name, arn in c.log_secret_options : { name = name, valueFrom = arn }]
          } : {},
        )
      },
    )
  ]) }

  # Port name => container port, for Service Connect and load balancer defaults.
  port_by_name = { for k, cs in local.containers : k => merge(concat([{}], [
    for c in values(cs) : { for p in c.port_mappings : p.name => p.container_port if p.name != "" }
  ])...) }

  # ---------------------------------------------------------------------------
  # Secrets, and what the execution role may read
  # ---------------------------------------------------------------------------

  secret_refs = { for k, cs in local.containers : k => concat(
    values(var.global_secrets),
    flatten([for c in values(cs) : concat(values(c.secrets), values(c.log_secret_options), c.repository_credentials_arn != "" ? [c.repository_credentials_arn] : [])])
  ) }

  # ECS accepts arn:...:secret:name-AbCdEf:json-key:stage:version; IAM matches
  # the secret ARN, the first seven fields. A partial ARN without the random
  # suffix needs the six-character wildcard, and a name that itself ends in
  # -xxxxxx (db-master) cannot be told apart from a full ARN, so it gets both.
  # https://docs.aws.amazon.com/secretsmanager/latest/userguide/auth-and-access_iam-policies.html
  secret_arns = { for k, refs in local.secret_refs : k => sort(distinct(flatten([
    for v in refs : (
      length(regexall("-[A-Za-z0-9]{6}$", join(":", slice(split(":", v), 0, 7)))) > 0
      ? [join(":", slice(split(":", v), 0, 7)), "${join(":", slice(split(":", v), 0, 7))}-??????"]
      : ["${join(":", slice(split(":", v), 0, 7))}-??????"]
    ) if strcontains(v, ":secretsmanager:")
  ]))) }
  parameter_arns = { for k, refs in local.secret_refs : k => sort(distinct([for v in refs : v if strcontains(v, ":ssm:")])) }

  # Bucket ownership: a deleted bucket's name can be registered by anyone.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html
  s3_owner_condition = { StringEquals = { "aws:ResourceAccount" = length(var.trusted_s3_account_ids) > 0 ? var.trusted_s3_account_ids : [local.account_id] } }

  # Writers to an encrypted log group need the key through CloudWatch Logs.
  # https://docs.aws.amazon.com/AmazonCloudWatch/latest/logs/encrypt-log-data-kms.html
  log_writer_actions = ["kms:Encrypt", "kms:ReEncrypt*", "kms:Decrypt", "kms:GenerateDataKey*", "kms:Describe*"]

  environment_file_arns = { for k, cs in local.containers : k => distinct(flatten([for c in values(cs) : c.environment_files])) }

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  task_roles_created      = { for k, s in local.services : k => s if s.task_role.create }
  execution_roles_created = { for k, s in local.services : k => s if s.execution_role.create }

  task_role_name      = { for k, s in local.services : k => "${var.name}-${k}-task" }
  execution_role_name = { for k, s in local.services : k => "${var.name}-${k}-exec" }

  task_role_arn = { for k, s in local.services : k => (
    s.task_role.create ? "arn:${local.partition}:iam::${local.account_id}:role/${local.task_role_name[k]}" : s.task_role.arn
  ) }
  execution_role_arn = { for k, s in local.services : k => (
    s.execution_role.create ? "arn:${local.partition}:iam::${local.account_id}:role/${local.execution_role_name[k]}" : s.execution_role.arn
  ) }

  # EFS volumes that authorise with IAM: the task role is what EFS checks.
  efs_iam_volumes = { for k, s in local.services : k => {
    for n, v in s.volumes : n => v.efs if v.efs != null ? v.efs.iam_authorization : false
  } }
  efs_written = { for k, cs in local.containers : k => distinct(flatten([
    for c in values(cs) : [for m in c.mount_points : m.source_volume if !m.read_only]
  ])) }

  exec_services = { for k, s in local.services : k => s if s.enable_execute_command }

  # Each statement is rendered on its own, so statements of different shapes
  # can share a list; policies are joined from them.
  task_module_statements = { for k, s in local.task_roles_created : k => concat(
    s.enable_execute_command ? [jsonencode({
      Sid      = "EcsExecChannels"
      Effect   = "Allow"
      Action   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
      Resource = "*" # ssmmessages has no resource-level permissions
    })] : [],
    s.enable_execute_command && var.execute_command.kms_key_arn != "" ? [jsonencode({
      Sid      = "EcsExecSessionKey"
      Effect   = "Allow"
      Action   = ["kms:Decrypt"]
      Resource = var.execute_command.kms_key_arn
    })] : [],
    s.enable_execute_command && var.execute_command.logging == "OVERRIDE" && var.execute_command.log_group_name != "" ? [
      jsonencode({ Sid = "EcsExecDescribeLogGroups", Effect = "Allow", Action = ["logs:DescribeLogGroups"], Resource = "*" }),
      jsonencode({
        Sid      = "EcsExecWriteLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:DescribeLogStreams", "logs:PutLogEvents"]
        Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.execute_command.log_group_name}:*"
      }),
    ] : [],
    s.enable_execute_command && var.execute_command.logging == "OVERRIDE" && var.execute_command.s3_bucket_name != "" ? [
      jsonencode({ Sid = "EcsExecBucketLocation", Effect = "Allow", Action = ["s3:GetBucketLocation"], Resource = "*" }),
      jsonencode({ Sid = "EcsExecBucketEncryption", Effect = "Allow", Action = ["s3:GetEncryptionConfiguration"], Resource = "arn:${local.partition}:s3:::${var.execute_command.s3_bucket_name}", Condition = local.s3_owner_condition }),
      jsonencode({
        Sid       = "EcsExecWriteObjects"
        Effect    = "Allow"
        Action    = ["s3:PutObject"]
        Resource  = "arn:${local.partition}:s3:::${var.execute_command.s3_bucket_name}/${var.execute_command.s3_key_prefix != "" ? "${trimsuffix(var.execute_command.s3_key_prefix, "/")}/" : ""}*"
        Condition = local.s3_owner_condition
      }),
    ] : [],
    s.enable_execute_command && var.execute_command.logging == "OVERRIDE" && var.execute_command.s3_bucket_name != "" && var.execute_command.s3_kms_key_arn != "" ? [jsonencode({
      Sid       = "EcsExecBucketKey"
      Effect    = "Allow"
      Action    = ["kms:GenerateDataKey"]
      Resource  = var.execute_command.s3_kms_key_arn
      Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
    })] : [],
    s.enable_execute_command && var.execute_command.logging == "OVERRIDE" && var.execute_command.log_group_name != "" && var.execute_command.log_kms_key_arn != "" ? [jsonencode({
      Sid       = "EcsExecLogKey"
      Effect    = "Allow"
      Action    = local.log_writer_actions
      Resource  = var.execute_command.log_kms_key_arn
      Condition = { StringEquals = { "kms:ViaService" = "logs.${local.region}.amazonaws.com" } }
    })] : [],
    [for i, n in keys(local.efs_iam_volumes[k]) : jsonencode(merge(
      {
        Sid      = "EfsMount${i}"
        Effect   = "Allow"
        Action   = contains(local.efs_written[k], n) ? ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"] : ["elasticfilesystem:ClientMount"]
        Resource = "arn:${local.partition}:elasticfilesystem:${local.region}:${local.account_id}:file-system/${local.efs_iam_volumes[k][n].file_system_id}"
      },
      local.efs_iam_volumes[k][n].access_point_id == "" ? {} : {
        Condition = { StringEquals = { "elasticfilesystem:AccessPointArn" = "arn:${local.partition}:elasticfilesystem:${local.region}:${local.account_id}:access-point/${local.efs_iam_volumes[k][n].access_point_id}" } }
      },
    ))],
  ) }
  # Decided from configuration only, never from ARN values that may be unknown at plan.
  task_module_policy = { for k, s in local.task_roles_created : k => s if s.enable_execute_command ? true : length(local.efs_iam_volumes[k]) > 0 }

  dead_letter_queues = distinct([for k, s in local.scheduled : s.schedule.dead_letter_queue_arn if s.schedule.dead_letter_queue_arn != ""])
  dead_letter_keys   = distinct([for k, s in local.scheduled : s.schedule.dead_letter_queue_kms_key_arn if s.schedule.dead_letter_queue_kms_key_arn != ""])

  execution_module_statements = { for k, s in local.execution_roles_created : k => concat(
    length(local.secret_arns[k]) == 0 ? [] : [jsonencode({ Sid = "ReadSecrets", Effect = "Allow", Action = ["secretsmanager:GetSecretValue"], Resource = local.secret_arns[k] })],
    length(local.parameter_arns[k]) == 0 ? [] : [jsonencode({ Sid = "ReadParameters", Effect = "Allow", Action = ["ssm:GetParameters"], Resource = local.parameter_arns[k] })],
    length(local.secret_refs[k]) == 0 || length(var.secrets_kms_key_arns) == 0 ? [] : [jsonencode({
      Sid       = "DecryptSecrets"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = var.secrets_kms_key_arns
      Condition = { StringEquals = { "kms:ViaService" = ["secretsmanager.${local.region}.amazonaws.com", "ssm.${local.region}.amazonaws.com"] } }
    })],
    length(local.environment_file_arns[k]) == 0 ? [] : [
      jsonencode({ Sid = "ReadEnvironmentFiles", Effect = "Allow", Action = ["s3:GetObject"], Resource = local.environment_file_arns[k], Condition = local.s3_owner_condition }),
      jsonencode({
        Sid       = "LocateEnvironmentFileBuckets"
        Effect    = "Allow"
        Action    = ["s3:GetBucketLocation"]
        Resource  = distinct([for f in local.environment_file_arns[k] : split("/", f)[0]])
        Condition = local.s3_owner_condition
      }),
    ],
    length(local.environment_file_arns[k]) == 0 || length(var.environment_files_kms_key_arns) == 0 ? [] : [jsonencode({
      Sid       = "DecryptEnvironmentFiles"
      Effect    = "Allow"
      Action    = ["kms:Decrypt"]
      Resource  = var.environment_files_kms_key_arns
      Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
    })],
    local.log_key[k] == "" ? [] : [jsonencode({
      Sid       = "WriteEncryptedLogs"
      Effect    = "Allow"
      Action    = local.log_writer_actions
      Resource  = local.log_key[k]
      Condition = { StringEquals = { "kms:ViaService" = "logs.${local.region}.amazonaws.com" } }
    })],
  ) }
  execution_module_policy = { for k, s in local.execution_roles_created : k => s if local.log_key[k] != "" ? true : length(local.secret_refs[k]) + length(flatten([for c in values(local.containers[k]) : c.environment_files])) > 0 }

  # The infrastructure role carries only what the configuration uses.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/infrastructure_IAM_role.html
  ebs_services    = { for k, s in local.services : k => s if s.managed_ebs_volume != null }
  traffic_shifted = { for k, s in local.replica : k => s if s.deployment.strategy != "ROLLING" ? length(s.load_balancers) > 0 : false }
  hooked          = { for k, s in local.replica : k => s if length(s.deployment.lifecycle_hooks) > 0 }
  infrastructure_policies = merge(
    length(local.ebs_services) > 0 ? { volumes = "arn:${local.partition}:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForVolumes" } : {},
    length(local.traffic_shifted) > 0 ? { load_balancers = "arn:${local.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers" } : {},
    length(local.managed_instances) > 0 ? { managed_instances = "arn:${local.partition}:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances" } : {},
  )
  infrastructure_used   = length(local.infrastructure_policies) + length(local.hooked) > 0
  infrastructure_inline = length(local.hooked) + length(local.supplied_instance_profile) > 0
  infrastructure_arn    = var.infrastructure_role.create ? "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-ecs-infrastructure" : var.infrastructure_role.arn
  create_infra_role     = var.infrastructure_role.create && local.infrastructure_used
  # The resource reference orders ECS after the role and its policies.
  infrastructure_role_in_use = local.create_infra_role ? aws_iam_role.infrastructure[0].arn : local.infrastructure_arn
  hook_functions             = flatten([for k, s in local.hooked : [for h in values(s.deployment.lifecycle_hooks) : h.function_arn]])

  scheduler_role_arn = "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-scheduler"

  # ---------------------------------------------------------------------------
  # Service settings
  # ---------------------------------------------------------------------------

  # An autoscaled service starts inside its bounds; afterwards Application Auto
  # Scaling owns the count.
  initial_desired_count = { for k, s in local.long_running : k => (
    s.autoscaling == null ? s.desired_count : min(max(s.desired_count, s.autoscaling.min), s.autoscaling.max)
  ) }

  scaling_policies = merge([for k, s in local.scaled : merge(
    s.autoscaling.cpu_target > 0 ? { "${k}/cpu" = { service = k, metric = "ECSServiceAverageCPUUtilization", label = "", target = s.autoscaling.cpu_target } } : {},
    s.autoscaling.memory_target > 0 ? { "${k}/memory" = { service = k, metric = "ECSServiceAverageMemoryUtilization", label = "", target = s.autoscaling.memory_target } } : {},
    s.autoscaling.requests_per_target > 0 ? { "${k}/requests" = { service = k, metric = "ALBRequestCountPerTarget", label = s.autoscaling.alb_resource_label, target = s.autoscaling.requests_per_target } } : {},
  )]...)
  custom_scaling_policies = merge([for k, s in local.scaled : { for n, c in s.autoscaling.custom : "${k}/${n}" => merge(c, { service = k, name = n }) }]...)
  scaling_schedules       = merge([for k, s in local.scaled : { for n, sc in s.autoscaling.schedules : "${k}/${n}" => merge(sc, { service = k, name = n }) }]...)

  subnets         = { for k, s in local.services : k => length(s.subnet_ids) > 0 ? s.subnet_ids : var.subnet_ids }
  security_groups = { for k, s in local.services : k => length(s.security_group_ids) > 0 ? s.security_group_ids : var.security_group_ids }

  discovery_created = { for k, s in local.long_running : k => s if s.service_discovery != null ? s.service_discovery.namespace_id != "" : false }
  service_registry = { for k, s in local.long_running : k => {
    registry_arn   = s.service_discovery.namespace_id != "" ? aws_service_discovery_service.this[k].arn : s.service_discovery.registry_arn
    container_name = s.service_discovery.dns_record_type == "SRV" ? (s.service_discovery.container_name != "" ? s.service_discovery.container_name : k) : null
    container_port = s.service_discovery.dns_record_type == "SRV" ? (s.service_discovery.container_port > 0 ? s.service_discovery.container_port : s.port) : null
  } if s.service_discovery != null }

  load_balancers = { for k, s in local.long_running : k => [
    for lb in s.load_balancers : {
      target_group_arn = lb.target_group_arn
      container_name   = lb.container_name != "" ? lb.container_name : k
      container_port = lb.container_port > 0 ? lb.container_port : (
        length(s.containers) == 0 ? s.port : one([for p in s.containers[lb.container_name].port_mappings : p.container_port])
      )
      alternate_target_group_arn   = lb.alternate_target_group_arn
      production_listener_rule_arn = lb.production_listener_rule_arn
      test_listener_rule_arn       = lb.test_listener_rule_arn
    }
  ] }

  # Rebalancing does not work with DAEMON, maximumPercent 100, or placement
  # that pins or orders by something other than an AZ spread.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-rebalancing.html
  az_rebalancing = { for k, s in local.long_running : k => alltrue([
    s.deployment.availability_zone_rebalancing,
    s.workload == "service",
    s.deployment.maximum_percent > 100,
    length(s.ordered_placement_strategy) == 0 ? true : (s.ordered_placement_strategy[0].type == "spread" ? s.ordered_placement_strategy[0].field == "attribute:ecs.availability-zone" : false),
    alltrue([for c in s.placement_constraints : !strcontains(c.expression, "attribute:ecs.availability-zone")]),
  ]) }

  service_connect_namespace = { for k, s in local.long_running : k => (
    s.service_connect == null ? "" : (s.service_connect.namespace_arn != "" ? s.service_connect.namespace_arn : var.service_connect_namespace_arn)
  ) }

  # With the image shortcut and a port, an empty expose publishes that port
  # under the service name. With containers, an empty expose is client-only.
  service_connect_expose = { for k, s in local.long_running : k => (
    s.service_connect == null ? {} : (
      length(s.service_connect.expose) == 0 && length(s.containers) == 0 && s.port > 0
      ? { (k) = { discovery_name = "", dns_name = "", port = 0, ingress_port_override = 0, idle_timeout_seconds = 0, per_request_timeout_seconds = 0, test_traffic_header = null } }
      : s.service_connect.expose
    )
  ) }

  # ---------------------------------------------------------------------------
  # Signals
  # ---------------------------------------------------------------------------

  alarmed = { for k, s in local.long_running : k => s if var.create_alarms ? s.alarms.enabled : false }
  expected_tasks = { for k, s in local.replica : k => (
    s.autoscaling != null ? s.autoscaling.min : s.desired_count
  ) }
  # The lowest count the service is allowed to run at any time, scheduled
  # scale-downs included; a floor of 0 means silence is normal, so no alarm.
  task_floor = { for k, s in local.replica : k => (
    s.autoscaling == null ? s.desired_count : min(concat([s.autoscaling.min], [for sc in values(s.autoscaling.schedules) : sc.min])...)
  ) }
  running_task_threshold = { for k, s in local.alarmed : k => s.alarms.min_running_tasks != null ? s.alarms.min_running_tasks : lookup(local.task_floor, k, 0) }
  running_task_alarms = {
    for k, s in local.alarmed : k => local.running_task_threshold[k] if var.container_insights != "disabled" ? (s.workload == "service" ? local.running_task_threshold[k] > 0 : false) : false
  }
  alarm_actions           = length(var.alarm_actions) > 0 ? var.alarm_actions : (var.sns_topic_arn == "" ? [] : [var.sns_topic_arn])
  ok_actions              = length(var.ok_actions) > 0 ? var.ok_actions : local.alarm_actions
  alarms_publish_to_topic = length(local.alarmed) == 0 || var.sns_topic_arn == "" ? false : contains(concat(local.alarm_actions, local.ok_actions), var.sns_topic_arn)

  event_rules_enabled = local.create ? (var.create_event_rules ? var.sns_topic_arn != "" : false) : false
  one_off_families    = [for k, s in local.services : "family:${var.name}-${k}" if contains(["scheduled", "task"], s.workload)]
  event_rules = !local.event_rules_enabled ? {} : merge(
    length(local.long_running) == 0 ? {} : {
      deployment-failed = {
        description = "ECS deployments in ${var.name} that failed (and, with rollback on, were rolled back)."
        pattern = jsonencode({
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Deployment State Change"]
          resources     = [{ prefix = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name}/" }]
          detail        = { eventName = ["SERVICE_DEPLOYMENT_FAILED"] }
        })
      }
      service-impaired = {
        description = "ECS service warnings and errors in ${var.name}: tasks that cannot start or be placed."
        pattern = jsonencode({
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Service Action"]
          resources     = [{ prefix = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:service/${var.name}/" }]
          detail        = { eventType = ["WARN", "ERROR"] }
        })
      }
    },
    length(local.one_off_families) == 0 ? {} : {
      job-failed-to-start = {
        description = "Scheduled and run-task workloads in ${var.name} whose task never started."
        pattern = jsonencode({
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Task State Change"]
          detail        = { clusterArn = [local.cluster_arn], group = local.one_off_families, lastStatus = ["STOPPED"], stopCode = ["TaskFailedToStart"] }
        })
      }
      job-exited-non-zero = {
        description = "Scheduled and run-task workloads in ${var.name} with a container that exited non-zero."
        pattern = jsonencode({
          source        = ["aws.ecs"]
          "detail-type" = ["ECS Task State Change"]
          detail        = { clusterArn = [local.cluster_arn], group = local.one_off_families, lastStatus = ["STOPPED"], containers = { exitCode = [{ "anything-but" = 0 }] } }
        })
      }
    },
  )

  # ---------------------------------------------------------------------------
  # Posture
  # ---------------------------------------------------------------------------

  images = flatten([for k, cs in local.containers : [for n, c in cs : { service = k, container = n, image = c.image }]])
  unpinned_images = [
    for i in local.images : "${i.service}/${i.container}: ${i.image}"
    if !strcontains(i.image, "@sha256:") ? (
      length(regexall(":[^/:]+$", i.image)) == 0 ? true : endswith(i.image, ":latest")
    ) : false
  ]

  ecr_images = [for i in local.images : i.image if strcontains(i.image, ".dkr.ecr.")]
  external_registries = sort(distinct([
    for i in local.images : (
      strcontains(split("/", i.image)[0], ".") ? split("/", i.image)[0] : (strcontains(split("/", i.image)[0], ":") ? split("/", i.image)[0] : "docker.io")
    ) if !strcontains(i.image, ".dkr.ecr.")
  ]))
  efs_volumes   = flatten([for k, s in local.services : [for n, v in s.volumes : v.efs.file_system_id if v.efs != null]])
  ec2_workloads = [for k, s in local.services : k if s.launch == "EC2"]
  # Container instances run the ECS agent, which needs the ecs endpoints.
  container_instances = length(local.ec2_workloads) + length(local.managed_instances) > 0
  ebs_keys = distinct(concat(
    length(local.ebs_services) > 0 && var.managed_storage_kms_key_arn != "" ? [var.managed_storage_kms_key_arn] : [],
    [for k, s in local.ebs_services : s.managed_ebs_volume.kms_key_arn if s.managed_ebs_volume.kms_key_arn != ""],
  ))

  services_without_rollback  = [for k, s in local.long_running : k if s.workload == "service" ? !(s.deployment.circuit_breaker ? s.deployment.rollback : false) : false]
  single_task_services       = [for k, n in local.expected_tasks : k if n < 2]
  spot_without_floor         = [for k, s in local.replica : k if local.spot_weight[k] > 0 ? !local.on_demand_floor[k] : false]
  untagged_task_services     = [for k, s in local.long_running : k if s.propagate_tags == "NONE"]
  writable_root_containers   = sort(flatten([for k, cs in local.containers : [for n, c in cs : "${k}/${n}" if !c.readonly_root_filesystem]]))
  schedules_without_dlq      = [for k, s in local.scheduled : k if s.schedule.dead_letter_queue_arn == ""]
  missing_required_tag_keys  = [for t in var.required_tag_keys : t if trimspace(lookup(var.tags, t, "")) == ""]
  services_with_shell_access = keys(local.exec_services)
  services_with_public_ip    = [for k, s in local.services : k if s.assign_public_ip]
  mutable_tag_images         = [for i in local.images : "${i.service}/${i.container}: ${i.image}" if !strcontains(i.image, "@sha256:")]
  host_access = sort(flatten([for k, s in local.services : concat(
    s.network_mode == "host" ? ["${k}: host network"] : [],
    s.pid_mode == "host" ? ["${k}: host pid namespace"] : [],
    s.ipc_mode == "host" ? ["${k}: host ipc namespace"] : [],
    [for n, v in s.volumes : "${k}: host path ${v.host_path} (volume ${n})" if v.host_path != ""],
    [for n, c in local.containers[k] : "${k}/${n}: privileged" if c.privileged],
    [for n, c in local.containers[k] : "${k}/${n}: adds ${join(", ", c.capabilities_add)}" if length(c.capabilities_add) > 0],
  )]))
  admin_policy_names = ["AdministratorAccess", "IAMFullAccess", "PowerUserAccess"]
  administrator_roles = sort(distinct(flatten([for k, s in local.services : concat(
    [for n, arn in s.task_role.managed_policies : "${k} task role: ${n}" if contains(local.admin_policy_names, element(split("/", arn), length(split("/", arn)) - 1))],
    [for n, arn in s.execution_role.managed_policies : "${k} execution role: ${n}" if contains(local.admin_policy_names, element(split("/", arn), length(split("/", arn)) - 1))],
    [for n, doc in s.task_role.policies : "${k} task role: ${n}" if length(regexall("\"Action\"\\s*:\\s*(\\[\\s*)?\"(\\*|iam:\\*)\"", doc)) > 0],
  )])))
  secret_looking_environment = sort(flatten([for k, cs in local.containers : [
    for n, c in cs : [for e in keys(merge(var.global_environment, c.environment)) : "${k}/${n}: ${e}" if length(regexall("(?i)(password|passwd|secret|token|api_?key|private_?key)$", e)) > 0]
  ]]))
  unrecorded_shell_services = var.execute_command.logging == "NONE" ? keys(local.exec_services) : []
  imds_reachable_workloads  = [for k, s in local.services : k if s.launch == "EC2" ? contains(["bridge", "host"], s.network_mode) : false]

  externally_deployed            = sort(concat(keys(local.static_ignored), keys(local.autoscaled_ignored)))
  unbounded_log_groups           = [for k, d in local.log_retention : k if d == 0]
  created_log_groups_without_key = [for k, s in local.created_log_groups : k if local.log_key[k] == ""]

  services_with_az_rebalancing = [for k, on in local.az_rebalancing : k if on]

  deployment_strategies = { for k, s in local.replica : k => s.deployment.strategy }
  access_logged         = sort([for k, s in local.long_running : k if s.service_connect != null ? s.service_connect.access_logs != null : false])
  # Managed Instances data volumes follow the account's EBS encryption by default.
  # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ManagedInstances.html
  managed_instance_volumes_encrypted = length(local.managed_instances) == 0 ? true : one(data.aws_ebs_encryption_by_default.current[*].enabled) != false
}
