data "aws_region" "current" {}

locals {
  create = var.create
  region = data.aws_region.current.name

  services = local.create ? var.services : {}

  common_tags = merge(var.tags, { "ManagedBy" = "Terraform", "Module" = "ecs-orchestrator" })

  # split so app autoscaling can own desired_count (ignore_changes) without
  # terraform flapping it back on every plan.
  services_autoscaled = { for k, s in local.services : k => s if s.autoscaling != null }
  services_static     = { for k, s in local.services : k => s if s.autoscaling == null }

  # log group per service (created here unless an external name is referenced)
  service_log_group = { for k, s in local.services : k => coalesce(s.log_group_name, "/ecs/${var.cluster_name}/${k}") }

  # shared execution role: explicit ARN wins, else the one we create
  shared_execution_role_arn = var.task_execution_role_arn != null ? var.task_execution_role_arn : (
    local.create_execution_role ? aws_iam_role.execution[0].arn : null
  )
  create_execution_role = local.create && var.create_task_execution_role && var.task_execution_role_arn == null

  # per-service resolved identities / networking
  service_execution_role_arn = { for k, s in local.services : k => coalesce(s.execution_role_arn, local.shared_execution_role_arn) }
  service_task_role_arn = {
    for k, s in local.services : k => s.task_role_arn != null ? s.task_role_arn : (
      s.create_task_role ? aws_iam_role.task[k].arn : null
    )
  }
  # launch_type set -> no strategy; else explicit strategy; else cluster default;
  # else fargate fallback so standalone just works.
  service_capacity_strategy = {
    for k, s in local.services : k => s.launch_type != null ? [] : (
      length(s.capacity_provider_strategy) > 0 ? s.capacity_provider_strategy : (
        length(var.default_capacity_provider_strategy) > 0 ? [] : [{ capacity_provider = "FARGATE", weight = 1, base = 0 }]
      )
    )
  }

  service_subnets = { for k, s in local.services : k => s.subnets != null ? s.subnets : var.default_subnets }
  service_security_groups = {
    for k, s in local.services : k => concat(
      s.create_security_group ? [aws_security_group.service[k].id] : [],
      s.security_groups != null ? s.security_groups : var.default_security_group_ids,
    )
  }
  service_connect_namespace = { for k, s in local.services : k => try(coalesce(s.service_connect.namespace, var.service_connect_namespace), var.service_connect_namespace) }

  services_with_task_role = { for k, s in local.services : k => s if s.task_role_arn == null && s.create_task_role }
  services_with_sg        = { for k, s in local.services : k => s if s.create_security_group }
  services_with_discovery = { for k, s in local.services : k => s if s.service_discovery != null }
  services_with_log_group = { for k, s in local.services : k => s if s.create_log_group && s.log_group_name == null }

  # all referenced secret ARNs (for the execution role read policy)
  all_secret_arns = distinct(flatten([
    for k, conts in local.service_containers : [
      for cn, c in conts : values(c.secrets)
    ]
  ]))

  # single source of container defaults - the shortcut merges over this so it
  # doesn't have to stay in lockstep with the containers type.
  container_defaults = {
    image                    = null
    essential                = true
    cpu                      = null
    memory                   = null
    memory_reservation       = null
    command                  = null
    entrypoint               = null
    working_directory        = null
    user                     = null
    privileged               = null
    readonly_root_filesystem = false
    stop_timeout             = null
    environment              = {}
    secrets                  = {}
    port_mappings            = []
    mount_points             = []
    depends_on               = []
    ulimits                  = []
    health_check             = null
    linux_parameters         = null
    log_options              = null
  }

  # explicit containers, else the single-container shortcut merged over defaults
  service_containers = {
    for sk, s in local.services : sk => length(s.containers) > 0 ? s.containers : {
      (sk) = merge(local.container_defaults, {
        image         = s.image
        command       = s.command
        environment   = s.environment
        secrets       = s.secrets
        port_mappings = s.port != null ? [{ container_port = s.port, host_port = null, protocol = "tcp", name = sk, app_protocol = null }] : []
        health_check  = s.health_check != null ? { command = s.health_check, interval = null, timeout = null, retries = null, start_period = null } : null
      })
    }
  }

  # container defs json. merge() of single-key maps so unset fields drop out -
  # ecs rejects explicit nulls.
  container_definitions = {
    for sk, s in local.services : sk => coalesce(s.container_definitions_override, jsonencode([
      for cn, c in local.service_containers[sk] : merge(
        {
          name                   = cn
          image                  = c.image
          essential              = c.essential
          readonlyRootFilesystem = c.readonly_root_filesystem
          logConfiguration = {
            logDriver = "awslogs"
            options = merge({
              "awslogs-group"         = local.service_log_group[sk]
              "awslogs-region"        = local.region
              "awslogs-stream-prefix" = cn
            }, c.log_options != null ? c.log_options : {})
          }
        },
        c.cpu != null ? { cpu = c.cpu } : {},
        c.memory != null ? { memory = c.memory } : {},
        c.memory_reservation != null ? { memoryReservation = c.memory_reservation } : {},
        c.command != null ? { command = c.command } : {},
        c.entrypoint != null ? { entryPoint = c.entrypoint } : {},
        c.working_directory != null ? { workingDirectory = c.working_directory } : {},
        c.user != null ? { user = c.user } : {},
        c.privileged != null ? { privileged = c.privileged } : {},
        c.stop_timeout != null ? { stopTimeout = c.stop_timeout } : {},
        length(c.environment) > 0 ? { environment = [for k, v in c.environment : { name = k, value = v }] } : {},
        length(c.secrets) > 0 ? { secrets = [for k, v in c.secrets : { name = k, valueFrom = v }] } : {},
        length(c.port_mappings) > 0 ? { portMappings = [for p in c.port_mappings : merge(
          { containerPort = p.container_port, protocol = p.protocol },
          p.host_port != null ? { hostPort = p.host_port } : {},
          p.name != null ? { name = p.name } : {},
          p.app_protocol != null ? { appProtocol = p.app_protocol } : {},
        )] } : {},
        length(c.mount_points) > 0 ? { mountPoints = [for m in c.mount_points : { sourceVolume = m.source_volume, containerPath = m.container_path, readOnly = m.read_only }] } : {},
        length(c.depends_on) > 0 ? { dependsOn = [for d in c.depends_on : { containerName = d.container_name, condition = d.condition }] } : {},
        length(c.ulimits) > 0 ? { ulimits = [for u in c.ulimits : { name = u.name, softLimit = u.soft_limit, hardLimit = u.hard_limit }] } : {},
        c.health_check != null ? { healthCheck = merge(
          { command = c.health_check.command },
          c.health_check.interval != null ? { interval = c.health_check.interval } : {},
          c.health_check.timeout != null ? { timeout = c.health_check.timeout } : {},
          c.health_check.retries != null ? { retries = c.health_check.retries } : {},
          c.health_check.start_period != null ? { startPeriod = c.health_check.start_period } : {},
        ) } : {},
        c.linux_parameters != null ? { linuxParameters = merge(
          c.linux_parameters.init_process_enabled != null ? { initProcessEnabled = c.linux_parameters.init_process_enabled } : {},
          c.linux_parameters.shared_memory_size != null ? { sharedMemorySize = c.linux_parameters.shared_memory_size } : {},
        ) } : {},
      )
    ]))
  }
}
