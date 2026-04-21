# Cluster

variable "cluster_name" {
  description = "ECS cluster name. Used as a prefix for every resource created by this module."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-_]{0,254}$", var.cluster_name))
    error_message = "Cluster name must start with alphanumeric and contain only alphanumeric, hyphens, or underscores (max 255 chars)."
  }
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights. Adds ~$0.35/task/month but provides task-level CPU, memory, and network metrics."
  type        = bool
  default     = true
}

# Environment & tagging

variable "environment" {
  description = "Deployment environment. Drives some defaults (prod gets 'stable' capacity, non-prod gets 'balanced') and is emitted as the Environment tag."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "sandbox", "test"], var.environment)
    error_message = "environment must be one of: dev, staging, prod, sandbox, test."
  }
}

variable "tags" {
  description = <<-EOT
    Tags applied to every resource created by the module. Put cost-allocation
    tags here (Project, Team, CostCenter, Owner, etc). The module does not
    enforce a fixed schema beyond Environment + Name + ManagedBy + Module.

    Example:
      tags = {
        Project    = "checkout"
        Team       = "payments"
        CostCenter = "FIN-123"
        Owner      = "payments@acme.io"
      }
  EOT
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
  description = "Default subnet IDs for ECS tasks. Private subnets recommended for production. Overridable per service."
  type        = list(string)
  default     = []
}

# Module-wide defaults

variable "enable_execute_command" {
  description = "Enable ECS Exec (interactive shell) for all services. Adds SSM agent permissions to task roles. Overridable per service."
  type        = bool
  default     = false
}

variable "create_service_security_groups" {
  description = "Auto-create a dedicated security group for each service. Requires vpc_id. The group starts with no inbound rules; add rules via aws_vpc_security_group_ingress_rule."
  type        = bool
  default     = false
}

variable "enable_autoscaling_default" {
  description = "Enable App Autoscaling for all services unless overridden per service."
  type        = bool
  default     = true
}

variable "propagate_tags" {
  description = "Source of tags propagated to ECS tasks. TASK_DEFINITION (default) ensures tasks carry cost allocation tags. Set to SERVICE if you prefer service-level tags. Set to NONE to disable."
  type        = string
  default     = "TASK_DEFINITION"

  validation {
    condition     = contains(["TASK_DEFINITION", "SERVICE", "NONE"], var.propagate_tags)
    error_message = "propagate_tags must be one of: TASK_DEFINITION, SERVICE, NONE."
  }
}

# Global config injection

variable "global_environment" {
  description = "Env vars injected into every container in this cluster. Per-service environment overrides these."
  type        = map(string)
  default     = {}
}

variable "global_secrets" {
  description = "Secrets injected into every container. Keys = env var names. Values = SSM parameter path (/path/to/param) or Secrets Manager ARN. Per-service secrets merge on top."
  type        = map(string)
  default     = {}
}

# Observability

variable "log_retention_days" {
  description = "CloudWatch log group retention in days. Use 0 for never-expire (not recommended for cost)."
  type        = number
  default     = 30

  validation {
    condition = contains(
      [0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653],
      var.log_retention_days
    )
    error_message = "log_retention_days must be a CloudWatch-valid value: 0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653."
  }
}

variable "kms_key_arn" {
  description = "KMS key ARN for encrypting CloudWatch log groups. Null uses AWS-managed keys."
  type        = string
  default     = null
}

variable "create_cloudwatch_alarms" {
  description = "Create CPU and memory utilization alarms for every service."
  type        = bool
  default     = true
}

variable "alarm_cpu_threshold" {
  description = "CPU utilization (%) that triggers the high-CPU alarm."
  type        = number
  default     = 80
}

variable "alarm_memory_threshold" {
  description = "Memory utilization (%) that triggers the high-memory alarm."
  type        = number
  default     = 80
}

variable "alarm_actions" {
  description = "SNS topic ARNs notified when alarms fire or resolve."
  type        = list(string)
  default     = []
}

variable "create_cloudwatch_dashboard" {
  description = "Create a CloudWatch dashboard with CPU, memory, and running task count widgets for every service."
  type        = bool
  default     = true
}

# Service Connect

variable "service_connect_namespace" {
  description = "AWS Cloud Map namespace ARN for ECS Service Connect. Required when any service sets service_connect_enabled = true."
  type        = string
  default     = null
}

# Services

variable "services" {
  description = <<-EOT
    Map of ECS services. Each key is the service name (used in resource names and log paths).

    Minimal example:
      services = {
        api = {
          role  = "master"        # master | worker | scheduled | daemon
          image = "nginx:alpine"
          port  = 80
        }
      }

    Cost notes:
      - role = "worker" uses Fargate Spot by default (~70% cheaper)
      - capacity_strategy = "economy" adds Graviton ARM64 on top (~40% cheaper per vCPU)
      - scheduled roles scale to zero by default
      - schedule_scaling scales non-prod to zero overnight

    Capacity strategies:
      stable          100% on-demand (default for master)
      balanced        on-demand base + spot burst
      spot_preferred  mostly spot, on-demand fallback
      spot_only       100% spot (stateless workers only)
      economy         spot + ARM64/Graviton

    Role defaults:
      master    stable, autoscaling on, circuit breaker on
      worker    spot_preferred, autoscaling on, scale-to-zero allowed
      scheduled spot_only, no autoscaling
      daemon    stable, no autoscaling
  EOT

  type = map(object({
    # identity
    role  = optional(string, "master")
    image = string

    # compute
    cpu    = optional(number, 256)
    memory = optional(number, 512)

    capacity_strategy = optional(string) # stable | balanced | spot_preferred | spot_only | economy
    cpu_architecture  = optional(string) # X86_64 | ARM64

    # networking
    port             = optional(number)
    protocol         = optional(string, "tcp")
    subnets          = optional(list(string))
    security_groups  = optional(list(string), [])
    assign_public_ip = optional(bool, false)

    # scaling
    desired_count      = optional(number, 1)
    min_count          = optional(number, 1)
    max_count          = optional(number, 10)
    enable_autoscaling = optional(bool) # null => role-based default

    # scheduled scale-to-zero
    schedule_scaling = optional(object({
      scale_down_cron    = optional(string, "cron(0 20 ? * MON-FRI *)") # 8pm UTC weekdays
      scale_up_cron      = optional(string, "cron(0 7 ? * MON-FRI *)")  # 7am UTC weekdays
      scale_down_min_cap = optional(number, 0)
      scale_down_max_cap = optional(number, 0)
      scale_up_min_cap   = optional(number, 1)
      scale_up_max_cap   = optional(number, 5)
    }))

    # config injection
    environment = optional(map(string), {})
    secrets     = optional(map(string), {}) # key = env var name, value = SSM path or SM ARN

    # load balancer
    load_balancer = optional(object({
      target_group_arn = string
      container_port   = number
      container_name   = optional(string) # defaults to service name
    }))

    # container health check
    health_check = optional(object({
      command      = list(string) # e.g. ["CMD-SHELL", "curl -f http://localhost/health || exit 1"]
      interval     = optional(number, 30)
      timeout      = optional(number, 5)
      retries      = optional(number, 3)
      start_period = optional(number, 60)
    }))

    # deployment
    deployment_minimum_healthy_percent = optional(number, 100)
    deployment_maximum_percent         = optional(number, 200)
    enable_circuit_breaker             = optional(bool, true)
    enable_rollback                    = optional(bool, true)
    health_check_grace_period_seconds  = optional(number, 0)

    # task role (what the app code can do)
    task_role_statements = optional(list(object({
      sid       = optional(string, "")
      effect    = optional(string, "Allow")
      actions   = list(string)
      resources = list(string)
    })), [])

    # sidecars
    xray_enabled = optional(bool, false) # adds X-Ray daemon sidecar (32 CPU / 256 MB)

    # service connect
    service_connect_enabled = optional(bool, false)

    # security
    readonly_root_filesystem = optional(bool, false)
    enable_exec              = optional(bool) # null => module-level default
    create_security_group    = optional(bool) # null => module-level default

    # storage
    ephemeral_storage_gib = optional(number, 21) # 21 GiB is the AWS minimum

    # Volumes are declared on the task definition so mount_points can reference them.
    # Only EFS is exposed; bind mounts and Docker volumes are not supported on Fargate.
    volumes = optional(list(object({
      name = string
      efs_volume_configuration = optional(object({
        file_system_id     = string
        root_directory     = optional(string, "/")
        transit_encryption = optional(string, "ENABLED") # ENABLED | DISABLED
        access_point_id    = optional(string)
      }))
    })), [])

    mount_points = optional(list(object({
      volume_name    = string
      container_path = string
      read_only      = optional(bool, false)
    })), [])

    # Seconds to wait for a graceful SIGTERM before SIGKILL. Max 120 on Fargate.
    stop_timeout = optional(number, 30)

    # When set, an EventBridge rule runs the task on this schedule (cron or rate
    # expression, e.g. "cron(0 2 * * ? *)" or "rate(1 hour)"). Only valid for
    # services with role = "scheduled".
    run_schedule = optional(string)

    tags = optional(map(string), {})

    # Escape hatch: bypass the builder and supply your own container definitions.
    container_definitions_override = optional(list(any))
  }))

  validation {
    condition = alltrue([
      for name, svc in var.services :
      contains(["master", "worker", "scheduled", "daemon"], svc.role)
    ])
    error_message = "Service role must be one of: master, worker, scheduled, daemon."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.capacity_strategy == null ||
      contains(["stable", "balanced", "spot_preferred", "spot_only", "economy"], svc.capacity_strategy)
    ])
    error_message = "capacity_strategy must be one of: stable, balanced, spot_preferred, spot_only, economy."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.cpu_architecture == null ||
      contains(["X86_64", "ARM64"], svc.cpu_architecture)
    ])
    error_message = "cpu_architecture must be one of: X86_64, ARM64."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.run_schedule == null || svc.role == "scheduled"
    ])
    error_message = "run_schedule can only be set on services with role = scheduled."
  }

  validation {
    condition = alltrue([
      for name, svc in var.services :
      svc.min_count <= svc.max_count
    ])
    error_message = "min_count must be <= max_count for every service."
  }
}
