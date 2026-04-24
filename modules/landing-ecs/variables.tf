# Fargate-only module. network_mode = awsvpc, launch type = FARGATE, both
# hard-pinned. Anything else (EC2 capacity, DAEMON strategy) lives elsewhere.

variable "cluster_name" {
  description = "ECS cluster name. Prefixed onto every resource the module creates."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,254}$", var.cluster_name))
    error_message = "cluster_name must start with alphanumeric and contain only alphanumeric, hyphens, or underscores (max 255 chars)."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights (~$0.35/task/month)."
  type        = bool
  default     = true
}

variable "cluster_settings" {
  description = "Extra aws_ecs_cluster.setting entries. Forward-compat shim; AWS only accepts `containerInsights` today and that's already handled by enable_container_insights."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k in keys(var.cluster_settings) :
      contains(["containerInsights"], k)
    ])
    error_message = "cluster_settings keys must be one of: containerInsights."
  }
}

variable "capacity_providers" {
  description = "Extra capacity providers to register alongside FARGATE + FARGATE_SPOT. Useful when mixing in EC2 ASG providers managed elsewhere."
  type        = list(string)
  default     = []
}

variable "default_capacity_provider_strategy" {
  description = "Fallback strategy for RunTask calls without an explicit one. Services always pick their own, so this only affects ad-hoc RunTask."
  type = list(object({
    capacity_provider = string
    weight            = optional(number, 1)
    base              = optional(number, 0)
  }))
  default = [
    { capacity_provider = "FARGATE", weight = 1, base = 1 }
  ]
}

# Environment & tagging

variable "environment" {
  description = "Deployment environment. Emitted as the Environment tag."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "sandbox", "test"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, sandbox, test."
  }
}

variable "tags" {
  description = "Tags applied to every resource. Put FinOps keys (Project/Team/CostCenter/Owner/...) here; module only enforces Environment/Name/ManagedBy/Module."
  type        = map(string)
  default     = {}
}

# Networking

variable "vpc_id" {
  description = "VPC ID. Required when create_service_security_groups = true."
  type        = string
  default     = ""
}

variable "default_subnets" {
  description = "Default subnet IDs for tasks. Private subnets recommended for production. Overridable per service."
  type        = list(string)
  default     = []
}

# IAM

variable "per_service_execution_role" {
  description = "One execution role per service (each sees only its own secrets). Set false to share a single role across all services — cheaper on IAM count but wider blast radius."
  type        = bool
  default     = true
}

# Module-wide defaults

variable "enable_execute_command" {
  description = "Turn on ECS Exec (interactive shell) for every service unless overridden."
  type        = bool
  default     = false
}

variable "create_service_security_groups" {
  description = "Auto-create a dedicated SG per service. Requires vpc_id."
  type        = bool
  default     = false
}

variable "enable_autoscaling_default" {
  description = "Default autoscaling flag when a service doesn't set enable_autoscaling explicitly."
  type        = bool
  default     = true
}

variable "propagate_tags" {
  description = "Tag propagation source for tasks. TASK_DEFINITION (default), SERVICE, or NONE."
  type        = string
  default     = "TASK_DEFINITION"

  validation {
    condition     = contains(["TASK_DEFINITION", "SERVICE", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be TASK_DEFINITION, SERVICE, or NONE."
  }
}

variable "default_deployment_controller" {
  description = "Deployment controller used when a service doesn't specify one."
  type        = string
  default     = "ECS"

  validation {
    condition     = contains(["ECS", "CODE_DEPLOY", "EXTERNAL"], var.default_deployment_controller)
    error_message = "default_deployment_controller must be ECS, CODE_DEPLOY, or EXTERNAL."
  }
}

# Default autoscaling targets; can be overridden per service.

variable "default_cpu_target_value" {
  description = "CPU utilization target (percent) used by the default target-tracking policy."
  type        = number
  default     = 60
}

variable "default_memory_target_value" {
  description = "Memory utilization target (percent) used by the default target-tracking policy."
  type        = number
  default     = 70
}

variable "default_scale_in_cooldown" {
  description = "Seconds App Autoscaling waits before scaling in again."
  type        = number
  default     = 300
}

variable "default_scale_out_cooldown" {
  description = "Seconds App Autoscaling waits before scaling out again."
  type        = number
  default     = 60
}

# Global config injection

variable "global_environment" {
  description = "Env vars injected into every container. Per-service environment overrides these."
  type        = map(string)
  default     = {}
}

variable "global_secrets" {
  description = "Secrets injected into every container. Values are SSM parameter paths or Secrets Manager ARNs. Per-service secrets merge on top."
  type        = map(string)
  default     = {}
}

# Observability

variable "log_retention_days" {
  description = "CloudWatch Logs retention. 0 means never expire."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a CloudWatch-valid retention value."
  }
}

variable "kms_key_arn" {
  description = "KMS key for log-group encryption. Null uses AWS-managed keys."
  type        = string
  default     = null
}

variable "create_cloudwatch_alarms" {
  description = "Create CPU + memory alarms for each service."
  type        = bool
  default     = true
}

variable "alarm_cpu_threshold" {
  description = "Default CPU % threshold for the high-CPU alarm. Services can override."
  type        = number
  default     = 80
}

variable "alarm_memory_threshold" {
  description = "Default memory % threshold for the high-memory alarm. Services can override."
  type        = number
  default     = 80
}

variable "alarm_evaluation_periods" {
  description = "Number of 60s periods an alarm must breach before firing."
  type        = number
  default     = 2
}

variable "alarm_actions" {
  description = "Default SNS topic ARNs for alarm + OK notifications. Services can override."
  type        = list(string)
  default     = []
}

# Service Connect

variable "service_connect_namespace" {
  description = "Cloud Map namespace ARN used by services with service_connect_enabled = true."
  type        = string
  default     = null
}

# Services

variable "services" {
  description = <<-EOT
    Map of ECS services. Each key is the service name (used in resource
    names, log paths, and Cloud Map service names).

    Containers:
      flat shortcuts (image/port/env/secrets/health_check) — single-container
      `containers = {...}`                                  — multi-container
      container_definitions_override                        — raw JSON escape hatch

    Capacity strategies:
      stable          100% on-demand (default)
      balanced        on-demand base + spot burst
      spot_preferred  mostly spot, on-demand fallback
      spot_only       100% spot
      economy         100% spot (same as spot_only; pair with cpu_architecture
                      = "ARM64" for Graviton savings)

    Autoscaling is on by default. Set enable_autoscaling = false for batch /
    scheduled work (required when run_schedule is set).
  EOT

  type = map(object({
    # Shortcuts for the "main" container. Ignored when `containers` is set.
    image             = optional(string)
    command           = optional(list(string))
    entrypoint        = optional(list(string))
    working_directory = optional(string)
    user              = optional(string)
    environment       = optional(map(string), {})
    secrets           = optional(map(string), {})
    port              = optional(number)
    protocol          = optional(string, "tcp")
    health_check = optional(object({
      command      = list(string)
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    }))
    stop_timeout             = optional(number, 30)
    start_timeout            = optional(number)
    readonly_root_filesystem = optional(bool, false)
    docker_labels            = optional(map(string), {})
    ulimits = optional(list(object({
      name       = string
      soft_limit = number
      hard_limit = number
    })), [])
    linux_parameters = optional(object({
      init_process_enabled = optional(bool)
      shared_memory_size   = optional(number)
      capabilities_add     = optional(list(string), [])
      capabilities_drop    = optional(list(string), [])
    }))
    log_driver         = optional(string, "awslogs")
    log_options        = optional(map(string), {})
    log_secret_options = optional(map(string), {})
    mount_points = optional(list(object({
      volume_name    = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])

    # Multi-container form. When non-empty, the flat shortcuts above are ignored.
    containers = optional(map(object({
      image              = string
      cpu                = optional(number)
      memory             = optional(number) # hard limit
      memory_reservation = optional(number) # soft limit
      essential          = optional(bool, true)
      command            = optional(list(string))
      entrypoint         = optional(list(string))
      working_directory  = optional(string)
      user               = optional(string)
      environment        = optional(map(string), {})
      secrets            = optional(map(string), {})
      port               = optional(number)
      protocol           = optional(string, "tcp")
      additional_ports = optional(list(object({
        container_port = number
        protocol       = optional(string, "tcp")
      })), [])
      health_check = optional(object({
        command      = list(string)
        interval     = optional(number, 30)
        timeout      = optional(number, 5)
        retries      = optional(number, 3)
        start_period = optional(number, 60)
      }))
      stop_timeout             = optional(number, 30)
      start_timeout            = optional(number)
      readonly_root_filesystem = optional(bool, false)
      docker_labels            = optional(map(string), {})
      ulimits = optional(list(object({
        name       = string
        soft_limit = number
        hard_limit = number
      })), [])
      linux_parameters = optional(object({
        init_process_enabled = optional(bool)
        shared_memory_size   = optional(number)
        capabilities_add     = optional(list(string), [])
        capabilities_drop    = optional(list(string), [])
      }))
      depends_on = optional(list(object({
        container_name = string
        # one of START | COMPLETE | SUCCESS | HEALTHY
        condition = string
      })), [])
      mount_points = optional(list(object({
        volume_name    = string
        container_path = string
        read_only      = optional(bool, false)
      })), [])
      volumes_from = optional(list(object({
        source_container = string
        read_only        = optional(bool, false)
      })), [])
      log_driver         = optional(string, "awslogs")
      log_options        = optional(map(string), {})
      log_secret_options = optional(map(string), {})
    })), {})

    # Task-level compute. Pin task_cpu/task_memory for multi-container tasks —
    # Fargate only accepts a discrete set of cpu+memory combinations (check
    # the docs; AWS will reject an invalid pair at apply time).
    task_cpu    = optional(number)
    task_memory = optional(number)
    cpu         = optional(number, 256)
    memory      = optional(number, 512)

    capacity_strategy = optional(string, "stable")
    cpu_architecture  = optional(string, "X86_64")

    # Networking
    subnets          = optional(list(string))
    security_groups  = optional(list(string), [])
    assign_public_ip = optional(bool, false)

    # null => follow var.enable_autoscaling_default. false for batch/scheduled.
    desired_count      = optional(number, 1)
    min_count          = optional(number, 1)
    max_count          = optional(number, 10)
    enable_autoscaling = optional(bool)

    # Per-metric opt-out for the default target-tracking policies.
    enable_cpu_autoscaling    = optional(bool, true)
    enable_memory_autoscaling = optional(bool, true)
    cpu_target_value          = optional(number)
    memory_target_value       = optional(number)
    scale_in_cooldown         = optional(number)
    scale_out_cooldown        = optional(number)

    # Arbitrary target-tracking policies (ALB RequestCountPerTarget, SQS
    # backlog, any CW metric). Exactly one of predefined_metric_type /
    # customized_metric per policy.
    custom_scaling_policies = optional(list(object({
      name                   = string
      target_value           = number
      scale_in_cooldown      = optional(number)
      scale_out_cooldown     = optional(number)
      disable_scale_in       = optional(bool, false)
      predefined_metric_type = optional(string)
      resource_label         = optional(string)
      customized_metric = optional(object({
        metric_name = string
        namespace   = string
        statistic   = string
        unit        = optional(string)
        dimensions = optional(list(object({
          name  = string
          value = string
        })), [])
      }))
    })), [])

    # Cron windows that clamp min/max_capacity. Classic use: non-prod hibernation.
    schedule_scaling = optional(object({
      scale_down_cron    = optional(string, "cron(0 20 ? * MON-FRI *)")
      scale_up_cron      = optional(string, "cron(0 7 ? * MON-FRI *)")
      scale_down_min_cap = optional(number, 0)
      scale_down_max_cap = optional(number, 0)
      scale_up_min_cap   = optional(number, 1)
      scale_up_max_cap   = optional(number, 5)
    }))

    # Primary LB attachment. Use additional_load_balancers for multi-TG
    # scenarios (dual-stack ALB + NLB, CodeDeploy blue/green, etc).
    load_balancer = optional(object({
      target_group_arn = string
      container_port   = number
      container_name   = optional(string)
    }))

    additional_load_balancers = optional(list(object({
      target_group_arn = string
      container_port   = number
      container_name   = optional(string)
    })), [])

    # Deployment
    deployment_controller              = optional(string) # ECS | CODE_DEPLOY | EXTERNAL
    deployment_minimum_healthy_percent = optional(number, 100)
    deployment_maximum_percent         = optional(number, 200)
    enable_circuit_breaker             = optional(bool, true)
    enable_rollback                    = optional(bool, true)
    health_check_grace_period_seconds  = optional(number, 0)

    # IAM (task role)
    task_role_statements = optional(list(object({
      sid       = optional(string, "")
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
      condition = optional(map(map(list(string))))
    })), [])

    # Service Connect
    service_connect_enabled = optional(bool, false)
    service_connect_alias   = optional(string) # default: service name

    # Feature flags
    enable_exec           = optional(bool)
    create_security_group = optional(bool)

    # Storage
    ephemeral_storage_gib = optional(number, 21)
    volumes = optional(list(object({
      name = string
      efs_volume_configuration = optional(object({
        file_system_id     = string
        root_directory     = optional(string, "/")
        transit_encryption = optional(string, "ENABLED")
        access_point_id    = optional(string)
      }))
    })), [])

    # Per-service alarm overrides (null => module default)
    alarm_cpu_threshold    = optional(number)
    alarm_memory_threshold = optional(number)
    alarm_actions          = optional(list(string))

    # Cron/rate expression. Drives an EventBridge rule; requires
    # enable_autoscaling = false.
    run_schedule = optional(string)

    tags = optional(map(string), {})

    # Raw container_definitions list; bypasses the builder. Conflicts with
    # image/containers/environment/secrets/health_check/etc (validation
    # below rejects the mix).
    container_definitions_override = optional(list(any))
  }))

  # Validations

  validation {
    condition = alltrue([
      for name, svc in var.services :
      contains(["stable", "balanced", "spot_preferred", "spot_only", "economy"], svc.capacity_strategy)
    ])
    error_message = "capacity_strategy must be stable, balanced, spot_preferred, spot_only, or economy."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      contains(["X86_64", "ARM64"], svc.cpu_architecture)
    ])
    error_message = "cpu_architecture must be X86_64 or ARM64."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.deployment_controller == null ||
      contains(["ECS", "CODE_DEPLOY", "EXTERNAL"], svc.deployment_controller)
    ])
    error_message = "deployment_controller must be ECS, CODE_DEPLOY, or EXTERNAL."
  }

  # RunTask doesn't mix with App Autoscaling. Force intent to be explicit.
  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.run_schedule == null || svc.enable_autoscaling == false
    ])
    error_message = "run_schedule requires enable_autoscaling = false."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.min_count <= svc.max_count
    ])
    error_message = "min_count must be <= max_count for every service."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.container_definitions_override != null || length(svc.containers) > 0 || svc.image != null
    ])
    error_message = "Every service must set exactly one of: container_definitions_override, containers, or image."
  }

  # Override bypasses the builder; high-level fields would be silently
  # ignored next to it. Reject the mix instead.
  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.container_definitions_override == null || (
        svc.image == null &&
        length(svc.containers) == 0 &&
        length(svc.environment) == 0 &&
        length(svc.secrets) == 0 &&
        svc.health_check == null &&
        svc.command == null &&
        svc.entrypoint == null &&
        length(svc.mount_points) == 0
      )
    ])
    error_message = "container_definitions_override cannot be combined with image/containers/environment/secrets/health_check/command/entrypoint/mount_points. Use one or the other."
  }

  # min healthy > 0 + desired_count = 0 deadlocks the first task. Catch it.
  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.desired_count > 0 || svc.deployment_minimum_healthy_percent == 0
    ])
    error_message = "Services with desired_count = 0 must set deployment_minimum_healthy_percent = 0, otherwise ECS can't start the first task."
  }

  # Without a grace period, ALB/NLB health checks kill tasks during cold start.
  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.load_balancer == null || svc.health_check_grace_period_seconds >= 30
    ])
    error_message = "Services with a load balancer need health_check_grace_period_seconds >= 30."
  }

  validation {
    condition = alltrue(flatten([
      for name, svc in var.services : [
        for cname, c in svc.containers : [
          for d in c.depends_on :
          contains(["START", "COMPLETE", "SUCCESS", "HEALTHY"], d.condition)
        ]
      ]
    ]))
    error_message = "containers[*].depends_on[*].condition must be START, COMPLETE, SUCCESS, or HEALTHY."
  }

  validation {
    condition = alltrue(flatten([
      for name, svc in var.services : [
        for p in svc.custom_scaling_policies :
        (p.predefined_metric_type == null) != (p.customized_metric == null)
      ]
    ]))
    error_message = "Each custom scaling policy must set exactly one of predefined_metric_type or customized_metric."
  }

  # Catch typos at plan time; AWS apply-time error on these is cryptic.
  validation {
    condition = alltrue(flatten([
      for name, svc in var.services : [
        for stmt in svc.task_role_statements : [
          for op, _ in(stmt.condition != null ? stmt.condition : {}) :
          contains([
            "StringEquals", "StringNotEquals",
            "StringEqualsIgnoreCase", "StringNotEqualsIgnoreCase",
            "StringLike", "StringNotLike",
            "NumericEquals", "NumericNotEquals",
            "NumericLessThan", "NumericLessThanEquals",
            "NumericGreaterThan", "NumericGreaterThanEquals",
            "DateEquals", "DateNotEquals",
            "DateLessThan", "DateLessThanEquals",
            "DateGreaterThan", "DateGreaterThanEquals",
            "Bool", "BinaryEquals",
            "IpAddress", "NotIpAddress",
            "ArnEquals", "ArnLike", "ArnNotEquals", "ArnNotLike",
            "Null",
          ], op) || length(regexall("IfExists$", op)) > 0 # *IfExists variant
        ]
      ]
    ]))
    error_message = "task_role_statements[*].condition keys must be valid IAM condition operators (StringEquals, ArnLike, ...; *IfExists suffix allowed)."
  }
}
