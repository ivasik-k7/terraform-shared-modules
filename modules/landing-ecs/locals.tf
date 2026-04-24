locals {
  region     = data.aws_region.current.name
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  # Module-set tags win over var.tags so provenance can be trusted.
  cluster_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Name        = var.cluster_name
      ManagedBy   = "Terraform"
      Module      = "landing-ecs"
    }
  )

  # `base` pins the first N tasks on a provider; `weight` splits everything
  # after. ARM64 is a separate axis — set cpu_architecture explicitly.
  capacity_strategies = {
    stable         = [{ capacity_provider = "FARGATE", weight = 1, base = 1 }]
    balanced       = [{ capacity_provider = "FARGATE", weight = 1, base = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 3, base = 0 }]
    spot_preferred = [{ capacity_provider = "FARGATE", weight = 1, base = 0 }, { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 }]
    spot_only      = [{ capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }]
    economy        = [{ capacity_provider = "FARGATE_SPOT", weight = 1, base = 0 }]
  }

  # Both Fargate providers always registered; caller can add more (EC2 ASG, etc).
  cluster_capacity_providers = distinct(concat(
    ["FARGATE", "FARGATE_SPOT"],
    var.capacity_providers,
  ))

  # Everything downstream reads local.services, not var.services.
  services = {
    for name, svc in var.services : name => {
      name = name

      containers = local.resolved_containers[name]

      cpu    = coalesce(svc.task_cpu, svc.cpu)
      memory = coalesce(svc.task_memory, svc.memory)

      capacity_strategy = svc.capacity_strategy
      cpu_architecture  = svc.cpu_architecture

      # null => module-wide default
      enable_autoscaling = coalesce(
        svc.enable_autoscaling,
        var.enable_autoscaling_default,
      )
      enable_cpu_autoscaling    = svc.enable_cpu_autoscaling
      enable_memory_autoscaling = svc.enable_memory_autoscaling
      cpu_target_value          = coalesce(svc.cpu_target_value, var.default_cpu_target_value)
      memory_target_value       = coalesce(svc.memory_target_value, var.default_memory_target_value)
      scale_in_cooldown         = coalesce(svc.scale_in_cooldown, var.default_scale_in_cooldown)
      scale_out_cooldown        = coalesce(svc.scale_out_cooldown, var.default_scale_out_cooldown)
      custom_scaling_policies   = svc.custom_scaling_policies

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

      load_balancer             = svc.load_balancer
      additional_load_balancers = svc.additional_load_balancers

      deployment_controller              = coalesce(svc.deployment_controller, var.default_deployment_controller)
      deployment_minimum_healthy_percent = svc.deployment_minimum_healthy_percent
      deployment_maximum_percent         = svc.deployment_maximum_percent
      enable_circuit_breaker             = svc.enable_circuit_breaker
      enable_rollback                    = svc.enable_rollback
      health_check_grace_period_seconds  = svc.health_check_grace_period_seconds

      task_role_statements     = svc.task_role_statements
      service_connect_enabled  = svc.service_connect_enabled
      service_connect_alias    = coalesce(svc.service_connect_alias, name)
      readonly_root_filesystem = svc.readonly_root_filesystem
      ephemeral_storage_gib    = svc.ephemeral_storage_gib
      volumes                  = svc.volumes
      run_schedule             = svc.run_schedule

      container_definitions_override = svc.container_definitions_override

      alarm_cpu_threshold    = coalesce(svc.alarm_cpu_threshold, var.alarm_cpu_threshold)
      alarm_memory_threshold = coalesce(svc.alarm_memory_threshold, var.alarm_memory_threshold)
      alarm_actions          = svc.alarm_actions != null ? svc.alarm_actions : var.alarm_actions

      log_group_name = "/ecs/${var.cluster_name}/${name}"
      tags           = merge(local.cluster_tags, { Service = name }, svc.tags)
    }
  }

  # Normalize shortcuts + `containers` map into a single shape the JSON
  # builder consumes. Shortcut form fills a single container named after
  # the service; explicit form passes through.
  explicit_containers = {
    for name, svc in var.services : name => [
      for cname, c in svc.containers : {
        name                     = cname
        image                    = c.image
        cpu                      = c.cpu
        memory                   = c.memory
        memory_reservation       = c.memory_reservation
        essential                = c.essential
        command                  = c.command
        entrypoint               = c.entrypoint
        working_directory        = c.working_directory
        user                     = c.user
        environment              = merge(var.global_environment, c.environment)
        secrets                  = merge(var.global_secrets, c.secrets)
        port                     = c.port
        protocol                 = c.protocol
        additional_ports         = c.additional_ports
        health_check             = c.health_check
        stop_timeout             = c.stop_timeout
        start_timeout            = c.start_timeout
        readonly_root_filesystem = c.readonly_root_filesystem
        docker_labels            = c.docker_labels
        ulimits                  = c.ulimits
        linux_parameters         = c.linux_parameters
        depends_on               = c.depends_on
        mount_points             = c.mount_points
        volumes_from             = c.volumes_from
        log_driver               = c.log_driver
        log_options              = c.log_options
        log_secret_options       = c.log_secret_options
      }
    ]
  }

  shortcut_containers = {
    for name, svc in var.services : name => length(svc.containers) > 0 ? [] : [{
      name                     = name
      image                    = svc.image
      cpu                      = null
      memory                   = null
      memory_reservation       = null
      essential                = true
      command                  = svc.command
      entrypoint               = svc.entrypoint
      working_directory        = svc.working_directory
      user                     = svc.user
      environment              = merge(var.global_environment, svc.environment)
      secrets                  = merge(var.global_secrets, svc.secrets)
      port                     = svc.port
      protocol                 = svc.protocol
      additional_ports         = []
      health_check             = svc.health_check
      stop_timeout             = svc.stop_timeout
      start_timeout            = svc.start_timeout
      readonly_root_filesystem = svc.readonly_root_filesystem
      docker_labels            = svc.docker_labels
      ulimits                  = svc.ulimits
      linux_parameters         = svc.linux_parameters
      depends_on               = []
      mount_points             = svc.mount_points
      volumes_from             = []
      log_driver               = svc.log_driver
      log_options              = svc.log_options
      log_secret_options       = svc.log_secret_options
    }]
  }

  resolved_containers = {
    for name, svc in var.services : name => (
      svc.container_definitions_override != null
      ? []
      : (length(svc.containers) > 0 ? local.explicit_containers[name] : local.shortcut_containers[name])
    )
  }

  # Filter sub-maps, consumed by for_each downstream.
  services_autoscaled     = { for k, v in local.services : k => v if v.enable_autoscaling }
  services_not_autoscaled = { for k, v in local.services : k => v if !v.enable_autoscaling }
  services_with_sg        = { for k, v in local.services : k => v if v.create_security_group }
  services_with_schedule  = { for k, v in local.services : k => v if v.schedule_scaling != null && v.enable_autoscaling }
  services_with_exec      = { for k, v in local.services : k => v if v.enable_exec }
  services_scheduled_run  = { for k, v in local.services : k => v if v.run_schedule != null }

  services_with_cpu_autoscale    = { for k, v in local.services_autoscaled : k => v if v.enable_cpu_autoscaling }
  services_with_memory_autoscale = { for k, v in local.services_autoscaled : k => v if v.enable_memory_autoscaling }

  custom_scaling_policies_flat = merge([
    for name, svc in local.services_autoscaled : {
      for p in svc.custom_scaling_policies :
      "${name}:${p.name}" => merge(p, { service = name })
    }
  ]...)

  # Secret refs per service (drives least-privilege execution-role IAM).
  # Keep the flattened all_* copies for the shared-role fallback.
  service_secret_refs = {
    for name, svc in local.services :
    name => distinct(flatten([for c in svc.containers : values(c.secrets)]))
  }

  all_secret_refs = distinct(flatten(values(local.service_secret_refs)))

  sm_arns   = [for r in local.all_secret_refs : r if startswith(r, "arn:${local.partition}:secretsmanager")]
  ssm_paths = [for r in local.all_secret_refs : r if startswith(r, "/") || startswith(r, "arn:${local.partition}:ssm")]

  service_sm_arns = {
    for name, refs in local.service_secret_refs :
    name => [for r in refs : r if startswith(r, "arn:${local.partition}:secretsmanager")]
  }

  service_ssm_paths = {
    for name, refs in local.service_secret_refs :
    name => [for r in refs : r if startswith(r, "/") || startswith(r, "arn:${local.partition}:ssm")]
  }

  # Routes each service at its execution role arn (shared or per-service).
  service_execution_role_arns = {
    for name, _ in local.services :
    name => var.per_service_execution_role ? aws_iam_role.task_execution_service[name].arn : aws_iam_role.task_execution_shared[0].arn
  }

  # Task-definition containerDefinitions JSON. Optional fields are merged in
  # conditionally so the serialized JSON stays minimal (and diff-stable).
  container_definitions = {
    for name, svc in local.services : name => (
      svc.container_definitions_override != null
      ? jsonencode(svc.container_definitions_override)
      : jsonencode([
        for c in svc.containers : merge(
          {
            name      = c.name
            image     = c.image
            essential = c.essential

            portMappings = concat(
              c.port != null ? [merge(
                { containerPort = c.port, protocol = c.protocol },
                svc.service_connect_enabled && c.name == name ? { name = name, appProtocol = "http" } : {}
              )] : [],
              [for ap in c.additional_ports : { containerPort = ap.container_port, protocol = ap.protocol }]
            )

            environment = [for k, v in c.environment : { name = k, value = tostring(v) }]
            secrets     = [for k, v in c.secrets : { name = k, valueFrom = v }]

            logConfiguration = merge(
              { logDriver = c.log_driver },
              c.log_driver == "awslogs" ? {
                options = merge(
                  {
                    "awslogs-group"         = svc.log_group_name
                    "awslogs-region"        = local.region
                    "awslogs-stream-prefix" = c.name
                  },
                  c.log_options,
                )
              } : { options = c.log_options },
              length(c.log_secret_options) > 0 ? {
                secretOptions = [for k, v in c.log_secret_options : { name = k, valueFrom = v }]
              } : {}
            )

            readonlyRootFilesystem = c.readonly_root_filesystem

            mountPoints = [for mp in c.mount_points : {
              sourceVolume  = mp.volume_name
              containerPath = mp.container_path
              readOnly      = mp.read_only
            }]

            volumesFrom = [for vf in c.volumes_from : {
              sourceContainer = vf.source_container
              readOnly        = vf.read_only
            }]
          },
          c.cpu != null ? { cpu = c.cpu } : {},
          c.memory != null ? { memory = c.memory } : {},
          c.memory_reservation != null ? { memoryReservation = c.memory_reservation } : {},
          c.command != null ? { command = c.command } : {},
          c.entrypoint != null ? { entryPoint = c.entrypoint } : {},
          c.working_directory != null ? { workingDirectory = c.working_directory } : {},
          c.user != null ? { user = c.user } : {},
          length(c.docker_labels) > 0 ? { dockerLabels = c.docker_labels } : {},
          length(c.ulimits) > 0 ? {
            ulimits = [for u in c.ulimits : {
              name      = u.name
              softLimit = u.soft_limit
              hardLimit = u.hard_limit
            }]
          } : {},
          c.linux_parameters != null ? {
            linuxParameters = merge(
              c.linux_parameters.init_process_enabled != null ? { initProcessEnabled = c.linux_parameters.init_process_enabled } : {},
              c.linux_parameters.shared_memory_size != null ? { sharedMemorySize = c.linux_parameters.shared_memory_size } : {},
              length(c.linux_parameters.capabilities_add) > 0 || length(c.linux_parameters.capabilities_drop) > 0 ? {
                capabilities = {
                  add  = c.linux_parameters.capabilities_add
                  drop = c.linux_parameters.capabilities_drop
                }
              } : {}
            )
          } : {},
          length(c.depends_on) > 0 ? {
            dependsOn = [for d in c.depends_on : { containerName = d.container_name, condition = d.condition }]
          } : {},
          c.health_check != null ? {
            healthCheck = {
              command     = c.health_check.command
              interval    = c.health_check.interval
              timeout     = c.health_check.timeout
              retries     = c.health_check.retries
              startPeriod = c.health_check.start_period
            }
          } : {},
          c.stop_timeout != null ? { stopTimeout = c.stop_timeout } : {},
          c.start_timeout != null ? { startTimeout = c.start_timeout } : {}
        )
      ])
    )
  }

  # Shared args for the two aws_ecs_service resources. They only differ in
  # lifecycle { ignore_changes = [desired_count] }, which can't be dynamic.
  service_common_args = {
    for k, v in local.services : k => {
      name                               = "${var.cluster_name}-${k}"
      cluster                            = aws_ecs_cluster.this.id
      task_definition                    = aws_ecs_task_definition.this[k].arn
      desired_count                      = v.desired_count
      health_check_grace_period_seconds  = v.health_check_grace_period_seconds
      enable_execute_command             = v.enable_exec
      deployment_minimum_healthy_percent = v.deployment_minimum_healthy_percent
      deployment_maximum_percent         = v.deployment_maximum_percent
      propagate_tags                     = var.propagate_tags == "NONE" ? null : var.propagate_tags
    }
  }
}
