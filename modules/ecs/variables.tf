# ============================================================================
# ECS Cluster Variables
# ============================================================================

variable "cluster_name" {
  description = "Name of the ECS cluster"
  type        = string
}

variable "enable_container_insights" {
  description = "Enable CloudWatch Container Insights for the cluster"
  type        = bool
  default     = true
}

variable "cluster_configuration" {
  description = "Execute command configuration for the cluster"
  type = object({
    enable_execute_command = optional(bool, false)
    kms_key_id             = optional(string)
    log_configuration = optional(object({
      cloud_watch_log_group_name     = optional(string)
      cloud_watch_encryption_enabled = optional(bool, true)
      s3_bucket_name                 = optional(string)
      s3_bucket_encryption_enabled   = optional(bool, true)
      s3_key_prefix                  = optional(string)
    }))
  })
  default = null
}

# ============================================================================
# Capacity Provider Variables
# ============================================================================

variable "capacity_providers" {
  description = "Map of capacity provider configurations (EC2 or Fargate)"
  type = map(object({
    type = string # "FARGATE", "FARGATE_SPOT", or "EC2"

    # Auto Scaling Group (for EC2 capacity providers)
    auto_scaling_group_arn = optional(string)

    # Managed Scaling
    managed_scaling = optional(object({
      maximum_scaling_step_size = optional(number, 10000)
      minimum_scaling_step_size = optional(number, 1)
      status                    = optional(string, "ENABLED")
      target_capacity           = optional(number, 100)
      instance_warmup_period    = optional(number, 300)
    }))

    # Managed Termination Protection
    managed_termination_protection = optional(string, "DISABLED")

    # Default strategy weight and base
    weight = optional(number, 1)
    base   = optional(number, 0)
  }))
  default = {
    FARGATE = {
      type   = "FARGATE"
      weight = 1
      base   = 1
    }
    FARGATE_SPOT = {
      type   = "FARGATE_SPOT"
      weight = 4
      base   = 0
    }
  }
}

# ============================================================================
# Service Variables
# ============================================================================

variable "services" {
  description = "Map of ECS service configurations"
  type = map(object({
    # Task Definition
    task_definition_family = string
    task_cpu               = optional(string, "256")
    task_memory            = optional(string, "512")
    network_mode           = optional(string, "awsvpc")
    requires_compatibilities = optional(list(string), ["FARGATE"])
    
    # Container Definitions
    container_definitions = list(object({
      name      = string
      image     = string
      cpu       = optional(number, 0)
      memory    = optional(number)
      essential = optional(bool, true)
      
      port_mappings = optional(list(object({
        container_port = number
        host_port      = optional(number)
        protocol       = optional(string, "tcp")
        app_protocol   = optional(string)
      })), [])
      
      environment = optional(list(object({
        name  = string
        value = string
      })), [])
      
      secrets = optional(list(object({
        name      = string
        valueFrom = string
      })), [])
      
      mount_points = optional(list(object({
        source_volume  = string
        container_path = string
        read_only      = optional(bool, false)
      })), [])
      
      volumes_from = optional(list(object({
        source_container = string
        read_only        = optional(bool, false)
      })), [])
      
      log_configuration = optional(object({
        log_driver = string
        options    = optional(map(string), {})
        secret_options = optional(list(object({
          name       = string
          value_from = string
        })), [])
      }))
      
      health_check = optional(object({
        command     = list(string)
        interval    = optional(number, 30)
        timeout     = optional(number, 5)
        retries     = optional(number, 3)
        start_period = optional(number, 0)
      }))
      
      depends_on = optional(list(object({
        container_name = string
        condition      = string
      })), [])
    }))
    
    # Volumes
    volumes = optional(list(object({
      name      = string
      host_path = optional(string)
      
      docker_volume_configuration = optional(object({
        scope         = optional(string, "task")
        autoprovision = optional(bool, true)
        driver        = optional(string)
        driver_opts   = optional(map(string))
        labels        = optional(map(string))
      }))
      
      efs_volume_configuration = optional(object({
        file_system_id          = string
        root_directory          = optional(string, "/")
        transit_encryption      = optional(string, "ENABLED")
        transit_encryption_port = optional(number)
        authorization_config = optional(object({
          access_point_id = optional(string)
          iam             = optional(string, "DISABLED")
        }))
      }))
    })), [])
    
    # Service Configuration
    desired_count   = optional(number, 1)
    launch_type     = optional(string)
    platform_version = optional(string, "LATEST")
    
    # Capacity Provider Strategy
    capacity_provider_strategy = optional(list(object({
      capacity_provider = string
      weight            = optional(number, 1)
      base              = optional(number, 0)
    })))
    
    # Network Configuration
    network_configuration = object({
      subnets          = list(string)
      security_groups  = optional(list(string), [])
      assign_public_ip = optional(bool, false)
    })
    
    # Load Balancer
    load_balancers = optional(list(object({
      target_group_arn = string
      container_name   = string
      container_port   = number
    })), [])
    
    # Service Discovery
    service_registries = optional(list(object({
      registry_arn   = string
      port           = optional(number)
      container_name = optional(string)
      container_port = optional(number)
    })), [])
    
    # Deployment Configuration
    deployment_configuration = optional(object({
      deployment_circuit_breaker = optional(object({
        enable   = bool
        rollback = bool
      }))
      maximum_percent         = optional(number, 200)
      minimum_healthy_percent = optional(number, 100)
    }))
    
    # Health Check Grace Period
    health_check_grace_period_seconds = optional(number)
    
    # Scheduling Strategy
    scheduling_strategy = optional(string, "REPLICA")
    
    # Placement Constraints
    placement_constraints = optional(list(object({
      type       = string
      expression = optional(string)
    })), [])
    
    # Ordered Placement Strategy
    ordered_placement_strategy = optional(list(object({
      type  = string
      field = optional(string)
    })), [])
    
    # Enable ECS Exec
    enable_execute_command = optional(bool, false)
    
    # Propagate Tags
    propagate_tags = optional(string, "SERVICE")
    
    # Force New Deployment
    force_new_deployment = optional(bool, false)
    
    # Wait for Steady State
    wait_for_steady_state = optional(bool, false)
    
    # Tags
    tags = optional(map(string), {})
  }))
  default = {}
}

# ============================================================================
# Auto Scaling Variables
# ============================================================================

variable "auto_scaling_policies" {
  description = "Map of auto scaling policies for ECS services"
  type = map(object({
    service_name = string
    
    min_capacity = number
    max_capacity = number
    
    # Target Tracking Policies
    target_tracking_policies = optional(list(object({
      name               = string
      target_value       = number
      scale_in_cooldown  = optional(number, 300)
      scale_out_cooldown = optional(number, 60)
      
      # Predefined Metric
      predefined_metric_type = optional(string) # ECSServiceAverageCPUUtilization, ECSServiceAverageMemoryUtilization, ALBRequestCountPerTarget
      resource_label         = optional(string) # Required for ALBRequestCountPerTarget
      
      # Custom Metric
      custom_metric = optional(object({
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
    
    # Step Scaling Policies
    step_scaling_policies = optional(list(object({
      name                   = string
      adjustment_type        = string # ChangeInCapacity, ExactCapacity, PercentChangeInCapacity
      cooldown               = optional(number, 60)
      metric_aggregation_type = optional(string, "Average")
      
      step_adjustments = list(object({
        scaling_adjustment          = number
        metric_interval_lower_bound = optional(number)
        metric_interval_upper_bound = optional(number)
      }))
      
      # CloudWatch Alarm
      alarm_name          = string
      alarm_description   = optional(string)
      comparison_operator = string
      evaluation_periods  = number
      metric_name         = string
      namespace           = string
      period              = number
      statistic           = string
      threshold           = number
      dimensions          = optional(map(string), {})
    })), [])
    
    # Scheduled Actions
    scheduled_actions = optional(list(object({
      name               = string
      schedule           = string
      min_capacity       = optional(number)
      max_capacity       = optional(number)
      timezone           = optional(string, "UTC")
    })), [])
  }))
  default = {}
}

# ============================================================================
# IAM Variables
# ============================================================================

variable "task_execution_role_arn" {
  description = "ARN of the task execution role (if not provided, a default role will be created)"
  type        = string
  default     = null
}

variable "create_task_execution_role" {
  description = "Create a default task execution role"
  type        = bool
  default     = true
}

variable "task_execution_role_policies" {
  description = "Additional IAM policies to attach to the task execution role"
  type        = list(string)
  default     = []
}

variable "task_role_policies" {
  description = "Map of IAM policies to attach to task roles (key = service name)"
  type        = map(list(string))
  default     = {}
}

# ============================================================================
# CloudWatch Logs Variables
# ============================================================================

variable "create_cloudwatch_log_groups" {
  description = "Create CloudWatch log groups for services"
  type        = bool
  default     = true
}

variable "log_retention_in_days" {
  description = "CloudWatch log group retention in days"
  type        = number
  default     = 7
}

variable "log_kms_key_id" {
  description = "KMS key ID for CloudWatch log encryption"
  type        = string
  default     = null
}

# ============================================================================
# Common Variables
# ============================================================================

variable "tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
