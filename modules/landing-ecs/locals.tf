locals {
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Module-set tags take precedence over var.tags to keep provenance consistent.
  cluster_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Name        = var.cluster_name
      ManagedBy   = "Terraform"
      Module      = "landing-ecs"
    }
  )

  # Capacity strategy presets. Each entry is a list of capacity-provider
  # assignments. `base` is the minimum tasks pinned to that provider before
  # `weight` kicks in for the remainder.
  capacity_strategies = {
    # 100% on-demand, for SLA-critical services
    stable = [
      { capacity_provider = "FARGATE", weight = 1, base = 1 }
    ]

    # on-demand base + spot burst, roughly 30-40% savings at scale
    balanced = [
      { capacity_provider = "FARGATE", weight = 1, base = 1 },
      { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 }
    ]

    # mostly spot with an on-demand safety net
    spot_preferred = [
      { capacity_provider = "FARGATE", weight = 1, base = 0 },
      { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }
    ]

    # 100% spot, stateless workers only
    spot_only = [
      { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
    ]

    # spot + Graviton ARM64 (cheaper per vCPU than x86 spot)
    economy = [
      { capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }
    ]
  }

  role_default_strategy = {
    master    = var.environment == "prod" ? "stable" : "balanced"
    worker    = "spot_preferred"
    scheduled = "spot_only"
    daemon    = "stable"
  }

  role_default_autoscaling = {
    master    = true
    worker    = true
    scheduled = false
    daemon    = false
  }

  # Normalized service map. Downstream resources only look at local.services,
  # so defaults live here.
  services = {
    for name, svc in var.services : name => {
      name   = name
      role   = svc.role
      image  = svc.image
      cpu    = svc.cpu
      memory = svc.memory

      capacity_strategy = coalesce(
        svc.capacity_strategy,
        lookup(local.role_default_strategy, svc.role, "balanced")
      )

      # economy => ARM64 unless the caller pinned an architecture explicitly
      cpu_architecture = coalesce(
        svc.cpu_architecture,
        coalesce(svc.capacity_strategy, lookup(local.role_default_strategy, svc.role, "balanced")) == "economy"
        ? "ARM64"
        : "X86_64"
      )

      enable_autoscaling = coalesce(
        svc.enable_autoscaling,
        lookup(local.role_default_autoscaling, svc.role, true),
        var.enable_autoscaling_default
      )
      desired_count    = svc.desired_count
      min_count        = svc.min_count
      max_count        = svc.max_count
      schedule_scaling = svc.schedule_scaling

      subnets          = coalesce(svc.subnets, var.default_subnets)
      security_groups  = svc.security_groups
      assign_public_ip = svc.assign_public_ip
      port             = svc.port
      protocol         = svc.protocol

      enable_exec           = coalesce(svc.enable_exec, var.enable_execute_command)
      create_security_group = coalesce(svc.create_security_group, var.create_service_security_groups)

      # cluster globals are overridden by per-service values
      environment = merge(var.global_environment, svc.environment)
      secrets     = merge(var.global_secrets, svc.secrets)

      load_balancer                      = svc.load_balancer
      health_check                       = svc.health_check
      health_check_grace_period_seconds  = svc.role == "master" && svc.load_balancer != null ? max(svc.health_check_grace_period_seconds, 30) : svc.health_check_grace_period_seconds
      deployment_minimum_healthy_percent = svc.desired_count == 0 ? 0 : svc.deployment_minimum_healthy_percent
      deployment_maximum_percent         = svc.deployment_maximum_percent
      enable_circuit_breaker             = svc.enable_circuit_breaker
      enable_rollback                    = svc.enable_rollback
      task_role_statements               = svc.task_role_statements
      xray_enabled                       = svc.xray_enabled
      service_connect_enabled            = svc.service_connect_enabled
      readonly_root_filesystem           = svc.readonly_root_filesystem
      ephemeral_storage_gib              = svc.ephemeral_storage_gib
      volumes                            = svc.volumes
      mount_points                       = svc.mount_points
      stop_timeout                       = svc.stop_timeout
      run_schedule                       = svc.run_schedule
      container_definitions_override     = svc.container_definitions_override

      log_group_name = "/ecs/${var.cluster_name}/${name}"

      tags = merge(local.cluster_tags, { Service = name }, svc.tags)
    }
  }

  # Filtered sub-maps used elsewhere in the module.
  services_autoscaled     = { for k, v in local.services : k => v if v.enable_autoscaling }
  services_not_autoscaled = { for k, v in local.services : k => v if !v.enable_autoscaling }
  services_with_lb        = { for k, v in local.services : k => v if v.load_balancer != null }
  services_with_sg        = { for k, v in local.services : k => v if v.create_security_group }
  services_with_schedule  = { for k, v in local.services : k => v if v.schedule_scaling != null && v.enable_autoscaling }
  services_with_secrets   = { for k, v in local.services : k => v if length(v.secrets) > 0 }
  services_with_exec      = { for k, v in local.services : k => v if v.enable_exec }
  services_with_xray      = { for k, v in local.services : k => v if v.xray_enabled }
  services_with_sc        = { for k, v in local.services : k => v if v.service_connect_enabled }
  services_scheduled_run  = { for k, v in local.services : k => v if v.run_schedule != null }

  # Flat list of every secret reference across services, used for IAM policy composition.
  all_secret_refs = distinct(flatten([
    for _, svc in local.services_with_secrets : values(svc.secrets)
  ]))

  sm_arns   = [for r in local.all_secret_refs : r if startswith(r, "arn:${local.partition}:secretsmanager")]
  ssm_paths = [for r in local.all_secret_refs : r if startswith(r, "/") || startswith(r, "arn:${local.partition}:ssm")]

  # Builds the JSON container definitions for each service's task definition.
  # A caller can bypass this entirely via container_definitions_override.
  container_definitions = {
    for name, svc in local.services : name => (
      svc.container_definitions_override != null
      ? jsonencode(svc.container_definitions_override)
      : jsonencode(
        concat(
          [
            merge(
              {
                name      = name
                image     = svc.image
                cpu       = svc.cpu
                memory    = svc.memory
                essential = true

                portMappings = svc.port != null ? [
                  merge(
                    {
                      containerPort = svc.port
                      protocol      = svc.protocol
                    },
                    # name + appProtocol required for Service Connect
                    svc.service_connect_enabled ? {
                      name        = name
                      appProtocol = "http"
                    } : {}
                  )
                ] : []

                environment = [
                  for k, v in svc.environment : { name = k, value = tostring(v) }
                ]

                secrets = [
                  for k, v in svc.secrets : { name = k, valueFrom = v }
                ]

                logConfiguration = {
                  logDriver = "awslogs"
                  options = {
                    "awslogs-group"         = svc.log_group_name
                    "awslogs-region"        = local.region
                    "awslogs-stream-prefix" = name
                  }
                }

                readonlyRootFilesystem = svc.readonly_root_filesystem

                mountPoints = [
                  for mp in svc.mount_points : {
                    sourceVolume  = mp.volume_name
                    containerPath = mp.container_path
                    readOnly      = mp.read_only
                  }
                ]
              },
              svc.health_check != null ? {
                healthCheck = {
                  command     = svc.health_check.command
                  interval    = svc.health_check.interval
                  timeout     = svc.health_check.timeout
                  retries     = svc.health_check.retries
                  startPeriod = svc.health_check.start_period
                }
              } : {},
              svc.stop_timeout != null ? {
                stopTimeout = svc.stop_timeout
              } : {}
            )
          ],
          # X-Ray daemon sidecar
          svc.xray_enabled ? [
            {
              name      = "xray-daemon"
              image     = "amazon/aws-xray-daemon:3"
              cpu       = 32
              memory    = 256
              essential = false

              portMappings = [
                { containerPort = 2000, protocol = "udp" }
              ]

              logConfiguration = {
                logDriver = "awslogs"
                options = {
                  "awslogs-group"         = svc.log_group_name
                  "awslogs-region"        = local.region
                  "awslogs-stream-prefix" = "xray"
                }
              }
            }
          ] : []
        )
      )
    )
  }

  # Rough monthly cost estimate per task, in USD. Based on us-east-1 on-demand
  # Fargate pricing (vCPU $0.04048/hr, memory $0.004445/GB/hr) with rule-of-thumb
  # discounts for spot and Graviton. Not a substitute for the AWS pricing calc.
  service_cost_estimates = {
    for name, svc in local.services : name => {
      vcpu_per_task = svc.cpu / 1024
      memory_gb     = svc.memory / 1024
      strategy      = svc.capacity_strategy
      # spot ~70% off; economy ~80% off (spot + Graviton)
      discount_factor = (
        svc.capacity_strategy == "spot_only" ? 0.30 :
        svc.capacity_strategy == "spot_preferred" ? 0.55 :
        svc.capacity_strategy == "economy" ? 0.20 :
        svc.capacity_strategy == "balanced" ? 0.75 :
        1.0
      )
      estimated_monthly_usd_per_task = floor(
        ((svc.cpu / 1024) * 0.04048 + (svc.memory / 1024) * 0.004445) * 720 *
        (
          svc.capacity_strategy == "spot_only" ? 0.30 :
          svc.capacity_strategy == "spot_preferred" ? 0.55 :
          svc.capacity_strategy == "economy" ? 0.20 :
          svc.capacity_strategy == "balanced" ? 0.75 :
          1.0
        ) * 100
      ) / 100
    }
  }
}
