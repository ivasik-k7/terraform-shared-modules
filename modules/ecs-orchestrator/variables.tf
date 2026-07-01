# ============================================================================
# GENERAL
# ============================================================================

variable "create" {
  description = "Master switch. When false the module creates nothing."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the ECS cluster (also used to prefix services, roles, and log groups)."
  type        = string

  validation {
    condition     = length(var.cluster_name) >= 1 && length(var.cluster_name) <= 255 && can(regex("^[a-zA-Z0-9-_]+$", var.cluster_name))
    error_message = "cluster_name must be 1-255 chars: letters, numbers, hyphens, underscores."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
}

# ============================================================================
# CLUSTER
# ============================================================================

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights. Off by default - it adds per-metric cost."
  type        = bool
  default     = false
}

variable "service_connect_namespace" {
  description = "Default Cloud Map namespace ARN/id for Service Connect at the cluster level."
  type        = string
  default     = null
}

variable "execute_command_configuration" {
  description = "ECS Exec configuration. Log to CloudWatch/S3 with encryption for auditable shell access."
  type = object({
    kms_key_id = optional(string)
    logging    = optional(string, "DEFAULT") # NONE | DEFAULT | OVERRIDE
    log_configuration = optional(object({
      cloud_watch_encryption_enabled = optional(bool)
      cloud_watch_log_group_name     = optional(string)
      s3_bucket_name                 = optional(string)
      s3_key_prefix                  = optional(string)
      s3_bucket_encryption_enabled   = optional(bool)
    }))
  })
  default = null

  validation {
    condition     = var.execute_command_configuration == null || contains(["NONE", "DEFAULT", "OVERRIDE"], var.execute_command_configuration.logging)
    error_message = "execute_command_configuration.logging must be NONE, DEFAULT, or OVERRIDE."
  }
}

# ============================================================================
# CAPACITY PROVIDERS
# ============================================================================

variable "enable_fargate_capacity_providers" {
  description = "Register FARGATE and FARGATE_SPOT on the cluster."
  type        = bool
  default     = true
}

variable "external_capacity_providers" {
  description = "Names of pre-existing capacity providers to register on the cluster (e.g. EC2 providers built elsewhere)."
  type        = list(string)
  default     = []
}

variable "ec2_capacity_providers" {
  description = <<-EOT
    EC2 capacity providers to create from an Auto Scaling Group ARN and register
    on the cluster. Key is the provider name. The ASG itself is built by the
    asg/ec2/launch-template modules and referenced here by ARN.
  EOT
  type = map(object({
    auto_scaling_group_arn         = string
    managed_termination_protection = optional(string, "DISABLED")
    managed_draining               = optional(string, "ENABLED")
    managed_scaling = optional(object({
      status                    = optional(string, "ENABLED")
      target_capacity           = optional(number, 100)
      minimum_scaling_step_size = optional(number)
      maximum_scaling_step_size = optional(number)
      instance_warmup_period    = optional(number)
    }), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, v in var.ec2_capacity_providers : can(regex("^arn:aws:autoscaling:", v.auto_scaling_group_arn))])
    error_message = "ec2_capacity_providers[*].auto_scaling_group_arn must be an Auto Scaling Group ARN."
  }
}

variable "default_capacity_provider_strategy" {
  description = "Cluster-level default strategy for RunTask calls without an explicit one. Services set their own."
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = []
}

# ============================================================================
# IAM
# ============================================================================

variable "create_task_execution_role" {
  description = "Create a shared task execution role (ECR pull, log write, secret read). Ignored where a service supplies its own execution_role_arn."
  type        = bool
  default     = true
}

variable "task_execution_role_arn" {
  description = "ARN of an existing task execution role to use for all services. Overrides create_task_execution_role."
  type        = string
  default     = null
}

variable "task_execution_role_policies" {
  description = "Extra managed policy ARNs to attach to the created task execution role."
  type        = map(string)
  default     = {}
}

variable "iam_permissions_boundary" {
  description = "Permissions boundary ARN applied to every IAM role this module creates."
  type        = string
  default     = null
}

variable "secrets_kms_key_arns" {
  description = "KMS key ARNs used to encrypt referenced secrets/parameters. Adds kms:Decrypt to the execution role so CMK-encrypted secrets can be read."
  type        = list(string)
  default     = []
}

# ============================================================================
# NETWORKING DEFAULTS (overridable per service)
# ============================================================================

variable "default_subnets" {
  description = "Default subnet IDs for awsvpc services that do not set their own."
  type        = list(string)
  default     = []
}

variable "default_security_group_ids" {
  description = "Default security group IDs for awsvpc services that do not set their own."
  type        = list(string)
  default     = []
}

variable "vpc_id" {
  description = "VPC ID. Required only when a service sets create_security_group = true."
  type        = string
  default     = null
}

# ============================================================================
# LOGGING DEFAULTS
# ============================================================================

variable "log_retention_days" {
  description = "Default CloudWatch Logs retention for service log groups."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a valid CloudWatch Logs retention value."
  }
}

variable "log_kms_key_id" {
  description = "KMS key ARN to encrypt the created service log groups."
  type        = string
  default     = null
}

# ============================================================================
# MONITORING / ALARMS
# ============================================================================
# Off by default - alarms cost per alarm. RunningTaskCount needs Container
# Insights (enable_container_insights); CPU/memory alarms work without it.

variable "create_cloudwatch_alarms" {
  description = "Create per-service CloudWatch alarms (CPU, memory, and - with Container Insights - low running task count)."
  type        = bool
  default     = false
}

variable "alarm_cpu_threshold" {
  description = "Service CPUUtilization (%) threshold for the high-CPU alarm."
  type        = number
  default     = 85
}

variable "alarm_memory_threshold" {
  description = "Service MemoryUtilization (%) threshold for the high-memory alarm."
  type        = number
  default     = 85
}

variable "alarm_min_running_tasks" {
  description = "Alarm when RunningTaskCount drops below this (requires Container Insights)."
  type        = number
  default     = 1
}

variable "alarm_evaluation_periods" {
  description = "Evaluation periods for the service alarms."
  type        = number
  default     = 3
}

variable "alarm_period" {
  description = "Period (seconds) for the service alarm statistics."
  type        = number
  default     = 60
}

variable "alarm_actions" {
  description = "ARNs notified on ALARM (e.g. an SNS topic)."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs notified when an alarm returns to OK."
  type        = list(string)
  default     = []
}

# ============================================================================
# SERVICES
# ============================================================================

variable "services" {
  description = <<-EOT
    Map of ECS services. Key is the service name. Launch type is driven by
    capacity_provider_strategy (FARGATE / FARGATE_SPOT / EC2 providers), not a
    launch_type enum. External resources (target groups, EFS, secrets, Cloud Map
    namespaces, KMS) are referenced by ARN/id, never created here. See README.
  EOT
  type = map(object({
    # --- task sizing / platform ---
    cpu                      = optional(number, 256)
    memory                   = optional(number, 512)
    network_mode             = optional(string, "awsvpc")
    requires_compatibilities = optional(list(string), ["FARGATE"])
    cpu_architecture         = optional(string, "X86_64")
    operating_system_family  = optional(string, "LINUX")
    ephemeral_storage_gib    = optional(number) # Fargate scratch, 21-200
    pid_mode                 = optional(string)
    ipc_mode                 = optional(string)
    task_tags                = optional(map(string), {})

    # --- containers ---
    containers = optional(map(object({
      image                    = string
      essential                = optional(bool, true)
      cpu                      = optional(number)
      memory                   = optional(number)
      memory_reservation       = optional(number)
      command                  = optional(list(string))
      entrypoint               = optional(list(string))
      working_directory        = optional(string)
      user                     = optional(string)
      privileged               = optional(bool)
      readonly_root_filesystem = optional(bool, false)
      stop_timeout             = optional(number)
      environment              = optional(map(string), {})
      secrets                  = optional(map(string), {}) # name => Secrets Manager / SSM ARN
      port_mappings = optional(list(object({
        container_port = number
        host_port      = optional(number)
        protocol       = optional(string, "tcp")
        name           = optional(string)
        app_protocol   = optional(string)
      })), [])
      mount_points = optional(list(object({
        source_volume  = string
        container_path = string
        read_only      = optional(bool, false)
      })), [])
      depends_on = optional(list(object({
        container_name = string
        condition      = string
      })), [])
      ulimits = optional(list(object({
        name       = string
        soft_limit = number
        hard_limit = number
      })), [])
      health_check = optional(object({
        command      = list(string)
        interval     = optional(number)
        timeout      = optional(number)
        retries      = optional(number)
        start_period = optional(number)
      }))
      linux_parameters = optional(object({
        init_process_enabled = optional(bool)
        shared_memory_size   = optional(number)
      }))
      log_options = optional(map(string))
    })), {})

    # single-container shortcut (used when `containers` is empty)
    image        = optional(string)
    port         = optional(number)
    environment  = optional(map(string), {})
    secrets      = optional(map(string), {})
    command      = optional(list(string))
    health_check = optional(list(string)) # CMD-SHELL args

    container_definitions_override = optional(string) # raw JSON escape hatch

    # --- volumes (EFS/FSx referenced; host/docker; managed EBS at launch) ---
    volumes = optional(map(object({
      host_path           = optional(string)
      configure_at_launch = optional(bool) # managed EBS at task launch
      efs = optional(object({
        file_system_id          = string
        root_directory          = optional(string)
        transit_encryption      = optional(string, "ENABLED")
        transit_encryption_port = optional(number)
        access_point_id         = optional(string)
        iam                     = optional(string)
      }))
      docker = optional(object({
        scope         = optional(string)
        autoprovision = optional(bool)
        driver        = optional(string)
        driver_opts   = optional(map(string))
        labels        = optional(map(string))
      }))
    })), {})

    # managed EBS volume attached at task launch (one per service); requires an
    # infrastructure role with EBS permissions.
    managed_ebs_volume = optional(object({
      name             = string
      role_arn         = string
      size_in_gb       = optional(number)
      volume_type      = optional(string, "gp3")
      iops             = optional(number)
      throughput       = optional(number)
      encrypted        = optional(bool, true)
      kms_key_id       = optional(string)
      snapshot_id      = optional(string)
      file_system_type = optional(string)
      tags             = optional(map(string), {})
    }))

    # --- capacity / launch type ---
    # Use capacity_provider_strategy (Fargate/EC2 providers) OR a plain
    # launch_type (FARGATE/EC2/EXTERNAL) for standalone instances with no
    # capacity provider. Mutually exclusive.
    launch_type = optional(string)
    capacity_provider_strategy = optional(list(object({
      capacity_provider = string
      weight            = optional(number, 1)
      base              = optional(number, 0)
    })), [])

    placement_constraints = optional(list(object({
      type       = string
      expression = optional(string)
    })), [])
    ordered_placement_strategy = optional(list(object({
      type  = string
      field = optional(string)
    })), [])

    # --- service runtime ---
    desired_count                      = optional(number, 1)
    deployment_controller              = optional(string, "ECS")
    deployment_minimum_healthy_percent = optional(number, 100)
    deployment_maximum_percent         = optional(number, 200)
    enable_circuit_breaker             = optional(bool, true)
    enable_rollback                    = optional(bool, true)
    enable_execute_command             = optional(bool, false)
    force_new_deployment               = optional(bool, false)
    wait_for_steady_state              = optional(bool, false)
    health_check_grace_period_seconds  = optional(number)
    propagate_tags                     = optional(string, "SERVICE")

    # auto-rollback on external cloudwatch alarms (e.g. 5xx) - complements the circuit breaker
    deployment_alarms = optional(object({
      alarm_names = list(string)
      enable      = optional(bool, true)
      rollback    = optional(bool, true)
    }))

    # --- networking (awsvpc) ---
    subnets               = optional(list(string))
    security_groups       = optional(list(string))
    create_security_group = optional(bool, false)
    assign_public_ip      = optional(bool, false)

    # --- load balancers (target groups referenced) ---
    load_balancers = optional(list(object({
      target_group_arn = string
      container_name   = string
      container_port   = number
    })), [])

    # --- service connect (namespace referenced) ---
    service_connect = optional(object({
      enabled   = optional(bool, true)
      namespace = optional(string)
      services = optional(list(object({
        port_name      = string
        discovery_name = optional(string)
        client_alias = optional(object({
          dns_name = string
          port     = number
        }))
      })), [])
    }))

    # --- cloud map service discovery (namespace referenced, service created) ---
    service_discovery = optional(object({
      namespace_id    = string
      name            = optional(string)
      dns_record_type = optional(string, "A")
      dns_ttl         = optional(number, 10)
      routing_policy  = optional(string, "MULTIVALUE")
    }))

    # --- logging ---
    create_log_group   = optional(bool, true)
    log_group_name     = optional(string) # reference an existing group
    log_retention_days = optional(number)

    # --- iam ---
    execution_role_arn      = optional(string) # override the shared exec role
    task_role_arn           = optional(string) # BYO task role
    create_task_role        = optional(bool, true)
    task_role_policies      = optional(map(string), {})
    task_role_inline_policy = optional(string)

    # --- autoscaling ---
    autoscaling = optional(object({
      min_capacity       = number
      max_capacity       = number
      cpu_target         = optional(number)
      memory_target      = optional(number)
      alb_request_target = optional(number)
      alb_resource_label = optional(string)
      # target-track any cloudwatch metric (e.g. sqs depth). target_value = units per task
      custom_metric = optional(object({
        namespace    = string
        metric_name  = string
        statistic    = optional(string, "Average")
        unit         = optional(string)
        dimensions   = optional(map(string), {})
        target_value = number
      }))
      scale_in_cooldown  = optional(number, 300)
      scale_out_cooldown = optional(number, 60)
      scheduled = optional(map(object({
        schedule     = string
        min_capacity = number
        max_capacity = number
        timezone     = optional(string)
      })), {})
    }))

    tags = optional(map(string), {})
  }))
  default = {}

  # every service needs a way to define containers
  validation {
    condition = alltrue([
      for k, s in var.services :
      length(s.containers) > 0 || s.image != null || s.container_definitions_override != null
    ])
    error_message = "Each service needs containers, an image shortcut, or container_definitions_override."
  }

  # Fargate only accepts specific cpu/memory pairs. Validate the combination
  # (the previous null check was dead - cpu/memory have non-null defaults).
  validation {
    condition = alltrue([
      for k, s in var.services :
      !contains(s.requires_compatibilities, "FARGATE") || (
        contains([256, 512, 1024, 2048, 4096, 8192, 16384], s.cpu) &&
        s.memory >= lookup({ 256 = 512, 512 = 1024, 1024 = 2048, 2048 = 4096, 4096 = 8192, 8192 = 16384, 16384 = 32768 }, s.cpu, 999999) &&
        s.memory <= lookup({ 256 = 2048, 512 = 4096, 1024 = 8192, 2048 = 16384, 4096 = 30720, 8192 = 61440, 16384 = 122880 }, s.cpu, 0)
      )
    ])
    error_message = "Fargate services must use a valid cpu/memory combination (see the AWS Fargate task size table)."
  }

  # network_mode sanity
  validation {
    condition     = alltrue([for k, s in var.services : contains(["awsvpc", "bridge", "host", "none"], s.network_mode)])
    error_message = "services[*].network_mode must be awsvpc, bridge, host, or none."
  }

  # awsvpc services need subnets (per-service or via default_subnets). Fails fast
  # instead of an empty-subnets error at apply.
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.network_mode != "awsvpc" || length(s.subnets != null ? s.subnets : var.default_subnets) > 0
    ])
    error_message = "awsvpc services need subnets: set per-service subnets or module-level default_subnets."
  }

  # load_balancers must target a defined container (explicit map key, or the
  # service key when using the single-container image shortcut).
  validation {
    condition = alltrue([
      for k, s in var.services : alltrue([
        for lb in s.load_balancers :
        contains(length(s.containers) > 0 ? keys(s.containers) : [k], lb.container_name)
      ])
    ])
    error_message = "Each load_balancers[*].container_name must match a defined container."
  }

  # mountPoints must reference a declared volume.
  validation {
    condition = alltrue([
      for k, s in var.services : alltrue([
        for cn, c in s.containers : alltrue([
          for m in c.mount_points : contains(keys(s.volumes), m.source_volume)
        ])
      ])
    ])
    error_message = "Each container mount_points[*].source_volume must match a key in the service's volumes."
  }

  # managed EBS volume must map to a volume declared with configure_at_launch.
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.managed_ebs_volume == null || (
        contains(keys(s.volumes), s.managed_ebs_volume.name) &&
        try(s.volumes[s.managed_ebs_volume.name].configure_at_launch, false) == true
      )
    ])
    error_message = "managed_ebs_volume.name must match a volume declared with configure_at_launch = true."
  }

  # ECS requires at least one essential container per task.
  validation {
    condition = alltrue([
      for k, s in var.services :
      length(s.containers) == 0 || anytrue([for cn, c in s.containers : c.essential])
    ])
    error_message = "Each service with explicit containers must mark at least one container essential = true."
  }

  # Fargate ephemeral storage range.
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.ephemeral_storage_gib == null || (s.ephemeral_storage_gib >= 21 && s.ephemeral_storage_gib <= 200)
    ])
    error_message = "ephemeral_storage_gib must be between 21 and 200."
  }

  # A service placed on an EC2 capacity provider must declare EC2 compatibility,
  # otherwise the FARGATE-only task definition cannot be placed on it.
  validation {
    condition = alltrue([
      for k, s in var.services : alltrue([
        for cp in s.capacity_provider_strategy :
        contains(["FARGATE", "FARGATE_SPOT"], cp.capacity_provider) || contains(s.requires_compatibilities, "EC2")
      ])
    ])
    error_message = "Services using a non-Fargate capacity provider must include \"EC2\" in requires_compatibilities."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.launch_type == null || contains(["FARGATE", "EC2", "EXTERNAL"], s.launch_type)])
    error_message = "services[*].launch_type must be FARGATE, EC2, or EXTERNAL."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.launch_type == null || length(s.capacity_provider_strategy) == 0])
    error_message = "Set either launch_type or capacity_provider_strategy on a service, not both."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.launch_type != "EC2" || contains(s.requires_compatibilities, "EC2")])
    error_message = "launch_type = \"EC2\" requires \"EC2\" in requires_compatibilities."
  }

  # Service Connect needs a namespace from somewhere - per-service or the
  # cluster-level default. Otherwise the config block resolves to a null
  # namespace and fails at apply.
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.service_connect == null || !coalesce(s.service_connect.enabled, true) ||
      s.service_connect.namespace != null || var.service_connect_namespace != null
    ])
    error_message = "service_connect requires a namespace: set services[*].service_connect.namespace or the cluster-level service_connect_namespace."
  }

  # min <= max, or app auto scaling rejects the target
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.autoscaling == null || s.autoscaling.min_capacity <= s.autoscaling.max_capacity
    ])
    error_message = "services[*].autoscaling.min_capacity must be <= max_capacity."
  }

  # same bound rule for scheduled actions
  validation {
    condition = alltrue([
      for k, s in var.services : s.autoscaling == null ? true : alltrue([
        for name, sch in s.autoscaling.scheduled : sch.min_capacity <= sch.max_capacity
      ])
    ])
    error_message = "services[*].autoscaling.scheduled[*].min_capacity must be <= max_capacity."
  }

  # ALBRequestCountPerTarget needs a resource_label
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.autoscaling == null || s.autoscaling.alb_request_target == null || s.autoscaling.alb_resource_label != null
    ])
    error_message = "services[*].autoscaling.alb_resource_label is required when alb_request_target is set."
  }

  # deployment alarms: ECS controller only
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.deployment_alarms == null || s.deployment_controller == "ECS"
    ])
    error_message = "services[*].deployment_alarms requires deployment_controller = \"ECS\" (CODE_DEPLOY/EXTERNAL manage their own rollback)."
  }

  # shortcut and containers are mutually exclusive (both set = shortcut ignored)
  validation {
    condition = alltrue([
      for k, s in var.services :
      length(s.containers) == 0 || (
        s.image == null && s.port == null && s.command == null && s.health_check == null &&
        length(s.environment) == 0 && length(s.secrets) == 0
      )
    ])
    error_message = "Set the single-container shortcut (image/port/environment/secrets/command/health_check) OR containers, not both."
  }

  # strategy must name a registered provider
  validation {
    condition = alltrue([
      for k, s in var.services : alltrue([
        for cp in s.capacity_provider_strategy :
        contains(concat(
          var.enable_fargate_capacity_providers ? ["FARGATE", "FARGATE_SPOT"] : [],
          keys(var.ec2_capacity_providers),
          var.external_capacity_providers,
        ), cp.capacity_provider)
      ])
    ])
    error_message = "services[*].capacity_provider_strategy references a provider that isn't registered (check ec2_capacity_providers keys, external_capacity_providers, or enable_fargate_capacity_providers)."
  }

  # non-fargate task needs a launch_type / strategy / cluster default, else the
  # fargate fallback mismatches
  validation {
    condition = alltrue([
      for k, s in var.services :
      contains(s.requires_compatibilities, "FARGATE") || s.launch_type != null ||
      length(s.capacity_provider_strategy) > 0 || length(var.default_capacity_provider_strategy) > 0
    ])
    error_message = "A non-Fargate task (requires_compatibilities without FARGATE) must set launch_type, capacity_provider_strategy, or a cluster default_capacity_provider_strategy - it can't use the Fargate fallback."
  }

  # ecs rejects an empty alarm list
  validation {
    condition = alltrue([
      for k, s in var.services :
      s.deployment_alarms == null || length(s.deployment_alarms.alarm_names) > 0
    ])
    error_message = "services[*].deployment_alarms.alarm_names must be non-empty."
  }
}
