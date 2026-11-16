# ---------------------------------------------------------------------------
# Identity and posture
# ---------------------------------------------------------------------------

variable "create" {
  description = "Master switch. false plans to nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Cluster name, and the prefix of every resource the module names (roles, log groups, alarms, schedules). Changing it replaces the cluster and every service in it."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter. IAM role names are built as <name>-<service>-exec and must fit in 64 characters."
  }
}

variable "tags" {
  description = "Tags on every resource the module creates, and on every task through propagate_tags. The module adds ManagedBy and Module last, so they cannot be overridden."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, v in var.tags : length(k) <= 128 && length(v) <= 256 && !startswith(lower(k), "aws:")])
    error_message = "tags keys must be at most 128 characters, values at most 256, and no key may start with the reserved \"aws:\" prefix."
  }
}

variable "required_tag_keys" {
  description = "Tag keys that must be in the module-level tags (and so on every resource and task), for example [\"CostCenter\", \"Environment\", \"Owner\"]. A missing or empty value fails the plan. Empty: no requirement."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\"). An acknowledged check stops warning in plans and HCP Terraform health assessments, and is listed in output.governance so a reviewer still sees the decision."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for c in var.acknowledged_checks : contains([
        "somebody_hears_a_failure",
        "deployments_roll_back",
        "images_are_pinned",
        "log_retention_is_bounded",
        "logs_use_a_customer_key",
        "services_survive_an_az",
        "spot_services_keep_an_on_demand_floor",
        "shell_access_is_intended",
        "task_costs_are_attributable",
        "running_task_alarms_have_data",
        "failed_schedules_are_kept",
        "shell_sessions_are_recorded",
        "containers_stay_on_their_side",
        "roles_are_not_administrators",
        "secrets_are_not_in_environment",
      ], c)
    ])
    error_message = "acknowledged_checks names a check that does not exist. The check names are the check blocks in checks.tf, listed in the README under \"Advisory checks\"."
  }
}

# ---------------------------------------------------------------------------
# Network defaults
# ---------------------------------------------------------------------------

variable "subnet_ids" {
  description = "Subnets for awsvpc tasks, used by every service that does not set its own subnet_ids. Private subnets in at least two AZs; output.network_contract lists what they must reach."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.subnet_ids : can(regex("^subnet-[0-9a-f]{8,17}$", s))])
    error_message = "subnet_ids must be subnet IDs (subnet-...)."
  }
}

variable "security_group_ids" {
  description = "Security groups for awsvpc tasks, used by every service that does not set its own security_group_ids. The module creates none: own them where the rest of the network is owned."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for s in var.security_group_ids : can(regex("^sg-[0-9a-f]{8,17}$", s))])
    error_message = "security_group_ids must be security group IDs (sg-...)."
  }
}

variable "allow_public_ip" {
  description = "Allow a service to set assign_public_ip = true. A task with a public IP in a public subnet is reachable from the internet on every port its security groups open."
  type        = bool
  default     = false
  nullable    = false
}

# ---------------------------------------------------------------------------
# Cluster
# ---------------------------------------------------------------------------

variable "container_insights" {
  description = "Container Insights: disabled, enabled or enhanced. It is billed as CloudWatch custom metrics and performance log ingestion per task and service (enhanced adds per-container metrics and costs more); see COSTS.md. The running-task alarms read its RunningTaskCount metric and are not created when it is disabled."
  type        = string
  default     = "enabled"
  nullable    = false

  validation {
    condition     = contains(["disabled", "enabled", "enhanced"], var.container_insights)
    error_message = "container_insights must be disabled, enabled or enhanced."
  }
}

variable "execute_command" {
  description = <<-EOT
    Cluster settings for ECS Exec sessions, used by services that set enable_execute_command.
      kms_key_arn     encrypts the session between the client and the container; the task role is given kms:Decrypt on it
      logging         DEFAULT (the container's awslogs configuration), OVERRIDE (log_group_name and/or s3_bucket_name) or NONE
      log_group_name  with OVERRIDE: CloudWatch Logs group for session output; the task role is given write access to it
      s3_bucket_name  with OVERRIDE: bucket for session output; s3_key_prefix is its prefix
      encrypt_logs    with OVERRIDE: require the destinations to be encrypted. AWS requires the log group, when used,
                      to be encrypted with a customer managed key; the bucket needs default encryption
      log_kms_key_arn the exec log group's key: the task roles get write access through CloudWatch Logs, and
                      kms_key_policy_requirements lists it
      s3_kms_key_arn  the exec bucket's SSE-KMS key: the task roles get GenerateDataKey through S3
    The task role writes the transcripts, so the workload itself can alter them: put the bucket under
    versioning or Object Lock if they are audit evidence.
  EOT
  type = object({
    kms_key_arn     = optional(string, "")
    logging         = optional(string, "DEFAULT")
    log_group_name  = optional(string, "")
    s3_bucket_name  = optional(string, "")
    s3_key_prefix   = optional(string, "")
    encrypt_logs    = optional(bool, true)
    log_kms_key_arn = optional(string, "")
    s3_kms_key_arn  = optional(string, "")
  })
  default  = {}
  nullable = false

  validation {
    condition     = contains(["DEFAULT", "OVERRIDE", "NONE"], var.execute_command.logging)
    error_message = "execute_command.logging must be DEFAULT, OVERRIDE or NONE."
  }

  validation {
    condition     = var.execute_command.logging != "OVERRIDE" ? true : (var.execute_command.log_group_name != "" ? true : var.execute_command.s3_bucket_name != "")
    error_message = "execute_command.logging = OVERRIDE needs log_group_name, s3_bucket_name or both."
  }

  validation {
    condition = alltrue([for k in [var.execute_command.kms_key_arn, var.execute_command.log_kms_key_arn, var.execute_command.s3_kms_key_arn] :
    k == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", k))])
    error_message = "execute_command.kms_key_arn, log_kms_key_arn and s3_kms_key_arn must each be empty or a KMS key ARN."
  }
}

variable "fargate_ephemeral_storage_kms_key_arn" {
  description = "Customer managed key for Fargate ephemeral storage (platform 1.4.0 or later, Linux only). A change updates the cluster in place and reaches running services only at their next deployment. output.kms_key_policy_requirements says what the key policy must allow. Empty: Fargate's own encryption."
  type        = string
  default     = ""
  nullable    = false

  validation {
    # Fargate rejects aliases and multi-Region keys for ephemeral storage.
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-create-storage-key.html
    condition     = var.fargate_ephemeral_storage_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/[0-9a-f-]{36}$", var.fargate_ephemeral_storage_kms_key_arn))
    error_message = "fargate_ephemeral_storage_kms_key_arn must be empty or a single-Region KMS key ARN (key/<uuid>). Fargate supports neither aliases nor multi-Region (mrk-) keys for ephemeral storage."
  }
}

variable "managed_storage_kms_key_arn" {
  description = "Cluster-level customer managed key for EBS volumes attached to tasks (services with managed_ebs_volume). A key on the volume itself takes precedence. Empty: the account's EBS default."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.managed_storage_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.managed_storage_kms_key_arn))
    error_message = "managed_storage_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "service_connect_namespace_arn" {
  description = "Cloud Map namespace ARN that Service Connect uses by default, for services that do not name their own. The module does not create namespaces."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.service_connect_namespace_arn == "" ? true : can(regex("^arn:aws[a-z-]*:servicediscovery:[a-z0-9-]+:[0-9]{12}:namespace/ns-", var.service_connect_namespace_arn))
    error_message = "service_connect_namespace_arn must be empty or a Cloud Map namespace ARN."
  }
}

# ---------------------------------------------------------------------------
# Capacity
# ---------------------------------------------------------------------------

variable "default_capacity" {
  description = <<-EOT
    The cluster's default capacity provider strategy, used by tasks started without one (run-task from a pipeline) and by Fargate services that set no capacity. A preset:
      on_demand       FARGATE only
      balanced        FARGATE base 1, then 1:3 FARGATE:FARGATE_SPOT
      spot_preferred  1:4 FARGATE:FARGATE_SPOT, no base
      spot_only       FARGATE_SPOT only; tasks wait when Spot has no capacity
    or the key of an ec2_capacity_providers entry, or a name in external_capacity_providers.
  EOT
  type        = string
  default     = "on_demand"
  nullable    = false
}

variable "ec2_capacity_providers" {
  description = <<-EOT
    EC2 capacity providers, keyed by a short name, each backed by an Auto Scaling group you own. Registered as <name>-<key>; services reference the key.
      auto_scaling_group_arn          the group; replacing it replaces the capacity provider
      managed_termination_protection  ENABLED needs scale-in protection on the group
      managed_draining                ENABLED drains tasks before an instance is terminated
      managed_scaling                 ECS scales the group to target_capacity percent utilisation
  EOT
  type = map(object({
    auto_scaling_group_arn         = string
    managed_termination_protection = optional(string, "DISABLED")
    managed_draining               = optional(string, "ENABLED")
    managed_scaling = optional(object({
      status                    = optional(string, "ENABLED")
      target_capacity           = optional(number, 100)
      minimum_scaling_step_size = optional(number, 1)
      maximum_scaling_step_size = optional(number, 10000)
      instance_warmup_period    = optional(number, 300)
    }), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, p in var.ec2_capacity_providers : can(regex("^[a-z][a-z0-9-]{0,30}$", k))])
    error_message = "ec2_capacity_providers keys must be 1-31 lowercase letters, digits or hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for k, p in var.ec2_capacity_providers : !contains(["on_demand", "balanced", "spot_preferred", "spot_only"], k)])
    error_message = "ec2_capacity_providers keys must not be a capacity preset name (on_demand, balanced, spot_preferred, spot_only)."
  }

  validation {
    condition     = alltrue([for k, p in var.ec2_capacity_providers : can(regex("^arn:aws[a-z-]*:autoscaling:[a-z0-9-]+:[0-9]{12}:autoScalingGroup:", p.auto_scaling_group_arn))])
    error_message = "ec2_capacity_providers[*].auto_scaling_group_arn must be an Auto Scaling group ARN."
  }

  validation {
    condition = alltrue([for k, p in var.ec2_capacity_providers : alltrue([
      contains(["ENABLED", "DISABLED"], p.managed_termination_protection),
      contains(["ENABLED", "DISABLED"], p.managed_draining),
      contains(["ENABLED", "DISABLED"], p.managed_scaling.status),
      p.managed_scaling.target_capacity >= 1,
      p.managed_scaling.target_capacity <= 100,
      p.managed_scaling.minimum_scaling_step_size >= 1,
      p.managed_scaling.maximum_scaling_step_size >= p.managed_scaling.minimum_scaling_step_size,
      p.managed_scaling.maximum_scaling_step_size <= 10000,
    ])])
    error_message = "ec2_capacity_providers: managed_termination_protection, managed_draining and managed_scaling.status are ENABLED or DISABLED; target_capacity is 1-100; scaling steps are 1-10000 with minimum <= maximum."
  }
}

variable "external_capacity_providers" {
  description = "Auto Scaling group capacity providers created outside this module (by another module or team) to register on the cluster. The cluster's provider list is owned by one resource, so this is the only way to add them. Services reference them by name in capacity or capacity_provider_strategy, with launch = \"EC2\". ECS Managed Instances providers need task definitions compatible with MANAGED_INSTANCES, which aws 5.x cannot declare, so they are not supported."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for p in var.external_capacity_providers : can(regex("^[A-Za-z0-9_-]{1,255}$", p)) ? !contains(["FARGATE", "FARGATE_SPOT", "on_demand", "balanced", "spot_preferred", "spot_only"], p) : false])
    error_message = "external_capacity_providers must be capacity provider names (letters, digits, - and _), not FARGATE, FARGATE_SPOT or a preset name."
  }

  validation {
    condition     = alltrue([for p in var.external_capacity_providers : !contains([for k in keys(var.ec2_capacity_providers) : "${var.name}-${k}"], p)])
    error_message = "An external_capacity_providers name is the name of one of this module's ec2_capacity_providers (<name>-<key>); the module registers those itself."
  }
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "Days to keep the service log groups (/ecs/<name>/<service>). 0 keeps every line forever: storage grows without bound ($0.0315 per GB-month in eu-west-2, after $0.5985 per GB ingested)."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be 0 or a retention period CloudWatch Logs accepts (1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653)."
  }
}

variable "log_kms_key_arn" {
  description = "Customer managed key for the service log groups. output.kms_key_policy_requirements says what its policy must allow; without that grant the log group create fails part way through the apply. Empty: CloudWatch Logs' own encryption."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.log_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.log_kms_key_arn))
    error_message = "log_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "log_skip_destroy" {
  description = "Keep the service log groups, and their lines, when the module or a service is destroyed. They still expire after log_retention_days."
  type        = bool
  default     = false
  nullable    = false
}

# ---------------------------------------------------------------------------
# Shared container configuration
# ---------------------------------------------------------------------------

variable "global_environment" {
  description = "Environment variables given to every container. A container's own environment wins on a clash."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "global_secrets" {
  description = "Secrets given to every container, name => Secrets Manager secret ARN (optionally with :json-key:version-stage:version-id) or SSM parameter ARN. A container's own secrets win on a clash."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for n, v in var.global_secrets : can(regex("^arn:aws[a-z-]*:(secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:|ssm:[a-z0-9-]+:[0-9]{12}:parameter/)", v))])
    error_message = "global_secrets values must be Secrets Manager secret ARNs or SSM parameter ARNs. A bare name cannot be scoped in the execution role's policy."
  }
}

variable "secrets_kms_key_arns" {
  description = "Customer managed keys that encrypt the referenced secrets and SecureString parameters. Execution roles get kms:Decrypt on them through Secrets Manager and SSM only, and output.kms_key_policy_requirements lists what each key must allow."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for k in var.secrets_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", k))])
    error_message = "secrets_kms_key_arns must be KMS key ARNs."
  }
}

variable "environment_files_kms_key_arns" {
  description = "SSE-KMS keys of the buckets holding containers' environment_files. Execution roles get kms:Decrypt on them through S3 only, and output.kms_key_policy_requirements lists them. Without it, a task whose file is under a customer key stops before the application starts."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for k in var.environment_files_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", k))])
    error_message = "environment_files_kms_key_arns must be KMS key ARNs."
  }
}

variable "trusted_s3_account_ids" {
  description = "Accounts allowed to own the buckets the module grants access to (environment files, ECS Exec transcripts). Grants carry aws:ResourceAccount, so a bucket name taken over by another account receives nothing and serves nothing. Empty: this account only."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for a in var.trusted_s3_account_ids : can(regex("^[0-9]{12}$", a))])
    error_message = "trusted_s3_account_ids must be 12-digit account IDs."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary for every IAM role the module creates. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

variable "infrastructure_role" {
  description = "The role ECS uses to create and attach EBS volumes for services with managed_ebs_volume. create = true makes <name>-ecs-infrastructure with AmazonECSInfrastructureRolePolicyForVolumes; create = false uses arn. Not used when no service has a managed EBS volume."
  type = object({
    create = optional(bool, true)
    arn    = optional(string, "")
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.infrastructure_role.create ? var.infrastructure_role.arn == "" : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", var.infrastructure_role.arn))
    error_message = "infrastructure_role: set create = false together with arn (an IAM role ARN), or leave both at their defaults."
  }
}

variable "task_definition_skip_destroy" {
  description = "Keep superseded task definition revisions ACTIVE instead of deregistering them. Revisions cost nothing, and an active one is what `aws ecs update-service --task-definition <family>:<n>` rolls back to."
  type        = bool
  default     = true
  nullable    = false
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

variable "sns_topic_arn" {
  description = "Topic for alarms, failed deployments, impaired services and failed scheduled jobs. The module does not own it: output.notification_requirements is what its access policy must allow. Empty: alarms are created without actions and no event rules are created."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_arn == "" ? true : can(regex("^arn:aws[a-z-]*:sns:[a-z0-9-]+:[0-9]{12}:[A-Za-z0-9_.-]+$", var.sns_topic_arn))
    error_message = "sns_topic_arn must be empty or an SNS topic ARN."
  }
}

variable "sns_topic_kms_key_arn" {
  description = "The topic's customer managed key, if it has one, so kms_key_policy_requirements can say which publishers it must allow."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.sns_topic_kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", var.sns_topic_kms_key_arn))
    error_message = "sns_topic_kms_key_arn must be empty or a KMS key ARN."
  }
}

variable "create_alarms" {
  description = "CPU and memory alarms per long-running service ($0.10 per alarm-month), and a running-task alarm per replica service when container_insights is not disabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "alarm_cpu_percent" {
  description = "Average service CPU utilisation, over three consecutive minutes, that raises the CPU alarm. A service's alarms.cpu_percent overrides it."
  type        = number
  default     = 85
  nullable    = false

  validation {
    condition     = var.alarm_cpu_percent > 0 && var.alarm_cpu_percent <= 100
    error_message = "alarm_cpu_percent must be between 1 and 100."
  }
}

variable "alarm_memory_percent" {
  description = "Average service memory utilisation, over three consecutive minutes, that raises the memory alarm. A service's alarms.memory_percent overrides it."
  type        = number
  default     = 85
  nullable    = false

  validation {
    condition     = var.alarm_memory_percent > 0 && var.alarm_memory_percent <= 100
    error_message = "alarm_memory_percent must be between 1 and 100."
  }
}

variable "alarm_actions" {
  description = "Where alarms send ALARM: SNS topics, Lambda functions, SSM incident plans, any CloudWatch alarm action ARN. Empty: sns_topic_arn, when set. output.notification_requirements covers only sns_topic_arn; other targets must allow CloudWatch themselves."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.alarm_actions) <= 5 ? alltrue([for a in var.alarm_actions : startswith(a, "arn:")]) : false
    error_message = "alarm_actions must be at most five ARNs (CloudWatch's limit per state)."
  }
}

variable "ok_actions" {
  description = "Where alarms send OK. Empty: the same as the alarm actions."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.ok_actions) <= 5 ? alltrue([for a in var.ok_actions : startswith(a, "arn:")]) : false
    error_message = "ok_actions must be at most five ARNs (CloudWatch's limit per state)."
  }
}

variable "alarm_period" {
  description = "Seconds per datapoint for the module's alarms. ECS publishes service metrics every 60 seconds."
  type        = number
  default     = 60
  nullable    = false

  validation {
    condition     = var.alarm_period >= 60 ? var.alarm_period % 60 == 0 : false
    error_message = "alarm_period must be a multiple of 60 seconds (ECS publishes its metrics once a minute)."
  }
}

variable "alarm_evaluation_periods" {
  description = "Consecutive breaching periods before an alarm fires; with the 60-second default period, 3 is three minutes."
  type        = number
  default     = 3
  nullable    = false

  validation {
    condition     = var.alarm_evaluation_periods >= 1 ? var.alarm_evaluation_periods * var.alarm_period <= 86400 : false
    error_message = "alarm_evaluation_periods must be 1 or more, and periods × alarm_period at most one day."
  }
}

variable "create_event_rules" {
  description = "EventBridge rules that forward failed deployments, impaired services and failed scheduled jobs to sns_topic_arn. Events from AWS services cost nothing to match. Not created without a topic."
  type        = bool
  default     = true
  nullable    = false
}

# ---------------------------------------------------------------------------
# Workloads
# ---------------------------------------------------------------------------

variable "services" {
  description = <<-EOT
    Workloads on the cluster, keyed by name (the ECS service name, task family suffix and log group suffix). Each one is a task definition plus:
      workload = "service"    a long-running ECS service (default)
      workload = "daemon"     one task per EC2 container instance (launch = "EC2")
      workload = "scheduled"  an EventBridge Scheduler schedule that runs the task (schedule)
      workload = "task"       the task definition only, for run-task from a pipeline (output.run_task_commands)

    The smallest entry is { image = "...", port = 8080, desired_count = 2 }: one container named after the service.
    For sidecars, init containers or log routers use containers, keyed by container name.

    capacity picks a preset (on_demand, balanced, spot_preferred, spot_only) or an ec2_capacity_providers key;
    capacity_provider_strategy overrides it with an explicit list. Empty: on Fargate, default_capacity when it is a
    preset, otherwise on_demand; on EC2 (except a daemon), required.

    Prices (eu-west-2, COSTS.md): Fargate $0.04656 per vCPU-hour and $0.00511 per GB-hour (ARM64 20% less);
    ephemeral_storage_gib above 20 GiB $0.000129 per GB-hour.

    Every field, its default and its effect is in the README section "Services fields"; the validations below name
    the field they refuse.
  EOT
  type = map(object({
    workload = optional(string, "service")
    launch   = optional(string, "FARGATE")
    capacity = optional(string, "")
    capacity_provider_strategy = optional(list(object({
      capacity_provider = string
      weight            = optional(number, 1)
      base              = optional(number, 0)
    })), [])

    cpu                     = optional(number, 256)
    memory                  = optional(number, 512)
    cpu_architecture        = optional(string, "X86_64")
    operating_system_family = optional(string, "LINUX")
    network_mode            = optional(string, "awsvpc")
    ephemeral_storage_gib   = optional(number, 0)
    pid_mode                = optional(string, "")
    ipc_mode                = optional(string, "")
    platform_version        = optional(string, "LATEST")

    image        = optional(string, "")
    port         = optional(number, 0)
    command      = optional(list(string), [])
    environment  = optional(map(string), {})
    secrets      = optional(map(string), {})
    health_check = optional(list(string), [])

    containers = optional(map(object({
      image              = string
      essential          = optional(bool, true)
      cpu                = optional(number, 0)
      memory             = optional(number, 0)
      memory_reservation = optional(number, 0)
      command            = optional(list(string), [])
      entrypoint         = optional(list(string), [])
      working_directory  = optional(string, "")
      user               = optional(string, "")
      environment        = optional(map(string), {})
      secrets            = optional(map(string), {})
      environment_files  = optional(list(string), [])
      port_mappings = optional(list(object({
        container_port = number
        name           = optional(string, "")
        protocol       = optional(string, "tcp")
        app_protocol   = optional(string, "")
        host_port      = optional(number, 0)
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
      depends_on = optional(map(string), {})
      health_check = optional(object({
        command      = list(string)
        interval     = optional(number, 30)
        timeout      = optional(number, 5)
        retries      = optional(number, 3)
        start_period = optional(number, 0)
      }))
      readonly_root_filesystem   = optional(bool, false)
      privileged                 = optional(bool, false)
      init_process_enabled       = optional(bool, false)
      capabilities_add           = optional(list(string), [])
      capabilities_drop          = optional(list(string), [])
      ulimits                    = optional(map(object({ soft = number, hard = number })), {})
      docker_labels              = optional(map(string), {})
      start_timeout              = optional(number, 0)
      stop_timeout               = optional(number, 0)
      repository_credentials_arn = optional(string, "")
      log_driver                 = optional(string, "awslogs")
      log_options                = optional(map(string), {})
      log_secret_options         = optional(map(string), {})
      firelens = optional(object({
        type    = optional(string, "fluentbit")
        options = optional(map(string), {})
      }))
    })), {})

    volumes = optional(map(object({
      host_path           = optional(string, "")
      configure_at_launch = optional(bool, false)
      efs = optional(object({
        file_system_id     = string
        access_point_id    = optional(string, "")
        root_directory     = optional(string, "")
        iam_authorization  = optional(bool, true)
        transit_encryption = optional(bool, true)
      }))
      docker = optional(object({
        scope         = optional(string, "task")
        autoprovision = optional(bool, false)
        driver        = optional(string, "")
        driver_opts   = optional(map(string), {})
        labels        = optional(map(string), {})
      }))
    })), {})

    managed_ebs_volume = optional(object({
      volume_name      = string
      size_in_gb       = optional(number, 0)
      snapshot_id      = optional(string, "")
      volume_type      = optional(string, "gp3")
      iops             = optional(number, 0)
      throughput       = optional(number, 0)
      kms_key_arn      = optional(string, "")
      file_system_type = optional(string, "ext4")
    }))

    desired_count      = optional(number, 1)
    subnet_ids         = optional(list(string), [])
    security_group_ids = optional(list(string), [])
    assign_public_ip   = optional(bool, false)

    load_balancers = optional(list(object({
      target_group_arn = string
      container_name   = optional(string, "")
      container_port   = optional(number, 0)
    })), [])
    health_check_grace_period_seconds = optional(number, 0)

    deployment = optional(object({
      minimum_healthy_percent        = optional(number)
      maximum_percent                = optional(number, 200)
      circuit_breaker                = optional(bool, true)
      rollback                       = optional(bool, true)
      alarm_names                    = optional(list(string), [])
      wait_for_steady_state          = optional(bool, false)
      availability_zone_rebalancing  = optional(bool, true)
      ignore_task_definition_changes = optional(bool, false)
    }), {})

    autoscaling = optional(object({
      min                 = optional(number, 1)
      max                 = number
      cpu_target          = optional(number, 70)
      memory_target       = optional(number, 0)
      requests_per_target = optional(number, 0)
      alb_resource_label  = optional(string, "")
      custom = optional(map(object({
        target_value = number
        namespace    = string
        metric_name  = string
        statistic    = optional(string, "Average")
        unit         = optional(string, "")
        dimensions   = optional(map(string), {})
      })), {})
      scale_in_cooldown  = optional(number, 300)
      scale_out_cooldown = optional(number, 60)
      disable_scale_in   = optional(bool, false)
      schedules = optional(map(object({
        schedule = string
        min      = number
        max      = number
        timezone = optional(string, "UTC")
      })), {})
    }))

    schedule = optional(object({
      expression                    = string
      timezone                      = optional(string, "UTC")
      enabled                       = optional(bool, true)
      task_count                    = optional(number, 1)
      flexible_window_minutes       = optional(number, 0)
      maximum_retry_attempts        = optional(number, 2)
      maximum_event_age_seconds     = optional(number, 3600)
      dead_letter_queue_arn         = optional(string, "")
      dead_letter_queue_kms_key_arn = optional(string, "")
    }))

    service_connect = optional(object({
      namespace_arn = optional(string, "")
      log_proxy     = optional(bool, true)
      expose = optional(map(object({
        discovery_name              = optional(string, "")
        dns_name                    = optional(string, "")
        port                        = optional(number, 0)
        ingress_port_override       = optional(number, 0)
        idle_timeout_seconds        = optional(number, 0)
        per_request_timeout_seconds = optional(number, 0)
      })), {})
    }))
    service_discovery = optional(object({
      namespace_id    = optional(string, "")
      registry_arn    = optional(string, "")
      name            = optional(string, "")
      dns_record_type = optional(string, "A")
      ttl             = optional(number, 10)
      routing_policy  = optional(string, "MULTIVALUE")
      container_name  = optional(string, "")
      container_port  = optional(number, 0)
    }))

    log_group = optional(object({
      create         = optional(bool, true)
      name           = optional(string, "")
      retention_days = optional(number)
      kms_key_arn    = optional(string, "")
    }), {})

    placement_constraints = optional(list(object({
      type       = string
      expression = optional(string, "")
    })), [])
    ordered_placement_strategy = optional(list(object({
      type  = string
      field = optional(string, "")
    })), [])

    enable_execute_command = optional(bool, false)
    propagate_tags         = optional(string, "SERVICE")
    force_delete           = optional(bool, false)

    task_role = optional(object({
      create           = optional(bool, true)
      arn              = optional(string, "")
      policies         = optional(map(string), {})
      managed_policies = optional(map(string), {})
    }), {})
    execution_role = optional(object({
      create           = optional(bool, true)
      arn              = optional(string, "")
      managed_policies = optional(map(string), {})
    }), {})

    alarms = optional(object({
      enabled           = optional(bool, true)
      cpu_percent       = optional(number, 0)
      memory_percent    = optional(number, 0)
      min_running_tasks = optional(number)
    }), {})

    tags = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  # --- names --------------------------------------------------------------

  validation {
    condition     = alltrue([for k, s in var.services : can(regex("^[a-z][a-z0-9-]{0,31}$", k))])
    error_message = "services keys must be 1-32 lowercase letters, digits or hyphens, starting with a letter."
  }

  validation {
    condition     = alltrue([for k, s in var.services : length("${var.name}-${k}-exec") <= 64])
    error_message = "A service key is too long for this name: the role <name>-<service>-exec must fit in 64 characters. Shorten name or the service key."
  }

  # --- workload shape -----------------------------------------------------

  validation {
    condition     = alltrue([for k, s in var.services : contains(["service", "daemon", "scheduled", "task"], s.workload)])
    error_message = "services[*].workload must be service, daemon, scheduled or task."
  }

  validation {
    condition     = alltrue([for k, s in var.services : contains(["FARGATE", "EC2"], s.launch)])
    error_message = "services[*].launch must be FARGATE or EC2."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.workload == "daemon" ? s.launch == "EC2" : true])
    error_message = "A daemon workload runs one task per container instance, so it needs launch = \"EC2\"."
  }

  validation {
    condition     = alltrue([for k, s in var.services : (s.workload == "scheduled") == (s.schedule != null)])
    error_message = "schedule is required on a scheduled workload and only allowed there."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.autoscaling == null ? true : s.workload == "service"])
    error_message = "autoscaling is only for workload = \"service\": a daemon follows the instances, and scheduled or task workloads have no service to scale."
  }

  validation {
    condition = alltrue([for k, s in var.services : contains(["scheduled", "task"], s.workload) ? alltrue([
      length(s.load_balancers) == 0, s.service_connect == null, s.service_discovery == null, !s.deployment.ignore_task_definition_changes,
    ]) : true])
    error_message = "load_balancers, service_connect, service_discovery and deployment.ignore_task_definition_changes need an ECS service; a scheduled or task workload has none."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.desired_count >= 0])
    error_message = "services[*].desired_count must be 0 or more."
  }

  # --- containers -----------------------------------------------------------

  validation {
    condition     = alltrue([for k, s in var.services : (s.image != "") != (length(s.containers) > 0)])
    error_message = "Each service sets either image (one container named after the service) or containers, not both and not neither."
  }

  validation {
    condition = alltrue([for k, s in var.services : length(s.containers) == 0 ? true : alltrue([
      s.port == 0, length(s.command) == 0, length(s.environment) == 0, length(s.secrets) == 0, length(s.health_check) == 0,
    ])])
    error_message = "port, command, environment, secrets and health_check on a service belong to its image shortcut; with containers, set them on the container."
  }

  validation {
    condition     = alltrue([for k, s in var.services : length(s.containers) == 0 ? true : anytrue([for c in values(s.containers) : c.essential])])
    error_message = "Each service needs at least one essential container."
  }

  validation {
    condition     = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,254}$", n))])])
    error_message = "Container names (the keys of containers) must be letters, digits, hyphens and underscores, starting with a letter or digit."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : alltrue([
      for d, cond in c.depends_on : contains(keys(s.containers), d) ? contains(["START", "COMPLETE", "SUCCESS", "HEALTHY"], cond) : false
    ])])])
    error_message = "containers[*].depends_on maps another container of the same service to START, COMPLETE, SUCCESS or HEALTHY."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : alltrue([
      for v in c.volumes_from : contains(keys(s.containers), v.source_container)
    ])])])
    error_message = "containers[*].volumes_from names a container that is not in the same service."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : alltrue([
      for m in c.mount_points : contains(keys(s.volumes), m.source_volume)
    ])])])
    error_message = "containers[*].mount_points names a source_volume that is not a key of the service's volumes."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : alltrue([
      for p in c.port_mappings : alltrue([contains(["tcp", "udp"], p.protocol), p.container_port >= 1, p.container_port <= 65535,
      p.app_protocol == "" ? true : contains(["http", "http2", "grpc"], p.app_protocol)])
    ])])])
    error_message = "containers[*].port_mappings: protocol is tcp or udp, container_port is 1-65535, app_protocol is empty, http, http2 or grpc."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.port >= 0 && s.port <= 65535])
    error_message = "services[*].port must be 0 (no port) or 1-65535."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : c.log_driver != "awsfirelens" ? true : anytrue([
      for o in values(s.containers) : o.firelens != null
    ])])])
    error_message = "A container that logs with awsfirelens needs a log router: another container in the service with firelens set."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      for v in concat(values(s.secrets), flatten([for c in values(s.containers) : concat(values(c.secrets), values(c.log_secret_options))])) :
      can(regex("^arn:aws[a-z-]*:(secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:|ssm:[a-z0-9-]+:[0-9]{12}:parameter/)", v))
    ])])
    error_message = "Secret values must be Secrets Manager secret ARNs (optionally with :json-key:version-stage:version-id) or SSM parameter ARNs. A bare name cannot be scoped in the execution role's policy."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : alltrue([
      for f in c.environment_files : can(regex("^arn:aws[a-z-]*:s3:::[a-z0-9.-]+/.+\\.env$", f))
    ])])])
    error_message = "containers[*].environment_files must be S3 object ARNs ending in .env (ECS's requirement for environment files)."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, c in s.containers : c.repository_credentials_arn == "" ? true :
    can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:", c.repository_credentials_arn))])])
    error_message = "containers[*].repository_credentials_arn must be empty or a Secrets Manager secret ARN."
  }

  # --- task size and platform ---------------------------------------------

  validation {
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size
    condition = alltrue([for k, s in var.services : s.launch != "FARGATE" ? true : contains(lookup({
      "256"   = [512, 1024, 2048]
      "512"   = [1024, 2048, 3072, 4096]
      "1024"  = [for g in range(2, 9) : g * 1024]
      "2048"  = [for g in range(4, 17) : g * 1024]
      "4096"  = [for g in range(8, 31) : g * 1024]
      "8192"  = [for g in range(16, 61, 4) : g * 1024]
      "16384" = [for g in range(32, 121, 8) : g * 1024]
      "32768" = [61440, 122880, 249856]
    }, tostring(s.cpu), []), s.memory)])
    error_message = "A Fargate service's cpu and memory (MiB) must be a pair Fargate offers: 256 with 512-2048; 512 with 1024-4096; 1024 with 2048-8192; 2048 with 4096-16384; 4096 with 8192-30720 (1 GB steps); 8192 with 16384-61440 (4 GB steps); 16384 with 32768-122880 (8 GB steps); 32768 with 61440, 122880 or 249856."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.launch == "FARGATE" ? true : alltrue([s.cpu >= 128, s.memory >= 128])])
    error_message = "An EC2 task needs at least 128 CPU units and 128 MiB."
  }

  validation {
    condition     = alltrue([for k, s in var.services : contains(["X86_64", "ARM64"], s.cpu_architecture)])
    error_message = "services[*].cpu_architecture must be X86_64 or ARM64."
  }

  validation {
    condition     = alltrue([for k, s in var.services : contains(["LINUX", "WINDOWS_SERVER_2019_FULL", "WINDOWS_SERVER_2019_CORE", "WINDOWS_SERVER_2022_FULL", "WINDOWS_SERVER_2022_CORE", "WINDOWS_SERVER_2025_FULL", "WINDOWS_SERVER_2025_CORE"], s.operating_system_family)])
    error_message = "services[*].operating_system_family must be LINUX or a WINDOWS_SERVER_<2019|2022|2025>_<FULL|CORE> value."
  }

  validation {
    condition     = alltrue([for k, s in var.services : contains(["awsvpc", "bridge", "host", "none"], s.network_mode)])
    error_message = "services[*].network_mode must be awsvpc, bridge, host or none."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.launch != "FARGATE" ? true : alltrue([
      s.network_mode == "awsvpc",
      length(s.placement_constraints) == 0,
      length(s.ordered_placement_strategy) == 0,
      alltrue([for c in values(s.containers) : !c.privileged]),
      alltrue([for v in values(s.volumes) : v.host_path == "" ? v.docker == null : false]),
    ])])
    error_message = "Fargate supports only network_mode = awsvpc, and no placement constraints or strategies, privileged containers, host_path volumes or Docker volumes."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.ephemeral_storage_gib == 0 ? true : (s.launch == "FARGATE" ? (s.ephemeral_storage_gib >= 21 ? s.ephemeral_storage_gib <= 200 : false) : false)])
    error_message = "services[*].ephemeral_storage_gib is Fargate only, and must be 0 (the 20 GiB default) or 21-200."
  }

  validation {
    # On Fargate (Linux) the only valid value is task.
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html
    condition     = alltrue([for k, s in var.services : s.pid_mode == "" ? true : (s.launch == "EC2" ? contains(["host", "task"], s.pid_mode) : s.pid_mode == "task")])
    error_message = "services[*].pid_mode must be empty, task, or host on an EC2 launch (Fargate accepts only task)."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.ipc_mode == "" ? true : (s.launch == "EC2" ? contains(["host", "task", "none"], s.ipc_mode) : false)])
    error_message = "services[*].ipc_mode must be empty, or host, task or none on an EC2 launch (Fargate does not support it)."
  }

  # --- volumes ------------------------------------------------------------

  validation {
    condition     = alltrue([for k, s in var.services : alltrue([for n, v in s.volumes : length([for x in [v.host_path != "", v.efs != null, v.docker != null, v.configure_at_launch] : x if x]) <= 1])])
    error_message = "A volume is one of: a bind mount (nothing set), host_path, efs, docker, or configure_at_launch (a managed EBS volume)."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for n, v in s.volumes : v.efs == null ? true : alltrue([
      can(regex("^fs-[0-9a-f]{8,40}$", v.efs.file_system_id)),
      v.efs.access_point_id == "" ? true : can(regex("^fsap-[0-9a-f]{8,40}$", v.efs.access_point_id)),
      v.efs.transit_encryption ? true : !v.efs.iam_authorization,
      v.efs.transit_encryption ? true : v.efs.access_point_id == "",
      v.efs.access_point_id == "" ? true : contains(["", "/"], v.efs.root_directory),
    ])])])
    error_message = "volumes[*].efs: file_system_id is fs-..., access_point_id is empty or fsap-...; IAM authorization and access points need transit_encryption; with an access point, root_directory is empty or \"/\" (the access point sets the path)."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.managed_ebs_volume == null ? true : alltrue([
      contains(keys(s.volumes), s.managed_ebs_volume.volume_name) ? s.volumes[s.managed_ebs_volume.volume_name].configure_at_launch : false,
      contains(["gp2", "gp3", "io1", "io2", "st1", "sc1", "standard"], s.managed_ebs_volume.volume_type),
      contains(["ext3", "ext4", "xfs", "ntfs"], s.managed_ebs_volume.file_system_type),
      s.managed_ebs_volume.size_in_gb > 0 ? true : s.managed_ebs_volume.snapshot_id != "",
      s.managed_ebs_volume.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", s.managed_ebs_volume.kms_key_arn)),
      s.workload == "service",
    ])])
    error_message = "managed_ebs_volume: volume_name is a key of volumes with configure_at_launch = true; volume_type is gp2, gp3, io1, io2, st1, sc1 or standard; file_system_type is ext3, ext4, xfs or ntfs; size_in_gb or snapshot_id is set; kms_key_arn is empty or a key ARN; and the workload is a service."
  }

  validation {
    condition     = alltrue([for k, s in var.services : alltrue([for n, v in s.volumes : v.configure_at_launch ? (s.managed_ebs_volume == null ? false : s.managed_ebs_volume.volume_name == n) : true])])
    error_message = "A volume with configure_at_launch = true needs the service's managed_ebs_volume to name it; ECS refuses to start the task otherwise."
  }

  # --- capacity -----------------------------------------------------------

  validation {
    condition = alltrue([for k, s in var.services : s.capacity == "" ? true : (s.launch == "FARGATE"
      ? contains(["on_demand", "balanced", "spot_preferred", "spot_only"], s.capacity)
    : contains(concat(keys(var.ec2_capacity_providers), var.external_capacity_providers), s.capacity))])
    error_message = "services[*].capacity is a preset (on_demand, balanced, spot_preferred, spot_only) on FARGATE, or an ec2_capacity_providers key or external_capacity_providers name on EC2."
  }

  validation {
    # A strategy holds Fargate or Auto Scaling group providers, never both.
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-capacity-providers.html
    condition = alltrue([for k, s in var.services : alltrue([for p in s.capacity_provider_strategy : s.launch == "FARGATE"
      ? contains(["FARGATE", "FARGATE_SPOT"], p.capacity_provider)
    : contains(concat(keys(var.ec2_capacity_providers), var.external_capacity_providers), p.capacity_provider)])])
    error_message = "capacity_provider_strategy entries are FARGATE or FARGATE_SPOT on a FARGATE launch, and ec2_capacity_providers keys or external_capacity_providers names on an EC2 launch. ECS does not mix the two in one strategy."
  }

  validation {
    condition = alltrue([for k, s in var.services : length(s.capacity_provider_strategy) == 0 ? true : alltrue([
      length(s.capacity_provider_strategy) <= 20,
      length([for p in s.capacity_provider_strategy : p if p.base > 0]) <= 1,
      anytrue([for p in s.capacity_provider_strategy : p.weight > 0]),
      alltrue([for p in s.capacity_provider_strategy : p.weight >= 0 ? (p.weight <= 1000 ? (p.base >= 0 ? p.base <= 100000 : false) : false) : false]),
    ])])
    error_message = "capacity_provider_strategy: at most 20 entries, only one with a base, at least one with a weight above 0, weights 0-1000 and bases 0-100000."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.launch == "EC2" && s.workload != "daemon" ? (s.capacity != "" ? true : length(s.capacity_provider_strategy) > 0) : true])
    error_message = "An EC2 workload other than a daemon needs capacity (an ec2_capacity_providers key) or capacity_provider_strategy."
  }

  # --- service settings ---------------------------------------------------

  validation {
    condition     = alltrue([for k, s in var.services : contains(["SERVICE", "TASK_DEFINITION", "NONE"], s.propagate_tags)])
    error_message = "services[*].propagate_tags must be SERVICE, TASK_DEFINITION or NONE."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.assign_public_ip ? var.allow_public_ip : true])
    error_message = "assign_public_ip = true needs allow_public_ip = true at the module level."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      s.deployment.minimum_healthy_percent == null ? true : (s.deployment.minimum_healthy_percent >= 0 ? s.deployment.minimum_healthy_percent <= 100 : false),
      s.deployment.maximum_percent >= 100,
      s.deployment.maximum_percent <= 200,
      s.deployment.circuit_breaker ? true : !s.deployment.rollback,
    ])])
    error_message = "deployment: minimum_healthy_percent is 0-100 (unset: 100 for a service, 0 for a daemon, the API's defaults), maximum_percent is 100-200, and rollback needs circuit_breaker."
  }

  validation {
    condition     = alltrue([for k, s in var.services : s.health_check_grace_period_seconds >= 0 && s.health_check_grace_period_seconds <= 2147483647])
    error_message = "services[*].health_check_grace_period_seconds must be 0 or more."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for lb in s.load_balancers :
    can(regex("^arn:aws[a-z-]*:elasticloadbalancing:[a-z0-9-]+:[0-9]{12}:targetgroup/", lb.target_group_arn))])])
    error_message = "load_balancers[*].target_group_arn must be a target group ARN. Classic Load Balancers are not supported."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([for lb in s.load_balancers : length(s.containers) == 0
      ? (lb.container_name == "" ? true : lb.container_name == k) ? (lb.container_port == 0 ? s.port > 0 : true) : false
      : contains(keys(s.containers), lb.container_name) ? (lb.container_port > 0 ? true : length(s.containers[lb.container_name].port_mappings) == 1) : false
    ])])
    error_message = "load_balancers[*]: with the image shortcut, container_name is empty or the service key, and the port defaults to port; with containers, container_name is one of them and container_port is set unless that container has exactly one port mapping."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.service_connect == null ? true : alltrue([
      s.service_connect.namespace_arn != "" ? true : var.service_connect_namespace_arn != "",
      s.service_connect.namespace_arn == "" ? true : can(regex("^arn:aws[a-z-]*:servicediscovery:", s.service_connect.namespace_arn)),
    ])])
    error_message = "service_connect needs a namespace: service_connect.namespace_arn on the service, or service_connect_namespace_arn on the module."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.service_connect == null ? true : (length(s.containers) == 0
      ? alltrue([for p, e in s.service_connect.expose : p == k ? s.port > 0 : false])
      : alltrue([for p, e in s.service_connect.expose : contains(flatten([for c in values(s.containers) : [for m in c.port_mappings : m.name]]), p)])
    )])
    error_message = "service_connect.expose is keyed by port name: with the image shortcut the only port name is the service key (and port must be set); with containers, a port_mappings name."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.service_discovery == null ? true : alltrue([
      (s.service_discovery.namespace_id != "") != (s.service_discovery.registry_arn != ""),
      s.service_discovery.namespace_id == "" ? true : can(regex("^ns-[a-z0-9]{16}$", s.service_discovery.namespace_id)),
      s.service_discovery.registry_arn == "" ? true : can(regex("^arn:aws[a-z-]*:servicediscovery:[a-z0-9-]+:[0-9]{12}:service/srv-", s.service_discovery.registry_arn)),
      contains(["A", "SRV"], s.service_discovery.dns_record_type),
      contains(["MULTIVALUE", "WEIGHTED"], s.service_discovery.routing_policy),
      s.service_discovery.ttl >= 0,
      s.service_discovery.name == "" ? true : can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,62}$", s.service_discovery.name)),
    ])])
    error_message = "service_discovery: exactly one of namespace_id (ns-..., the module creates the Cloud Map service) or registry_arn (an existing Cloud Map service); dns_record_type A or SRV; routing_policy MULTIVALUE or WEIGHTED; ttl 0 or more."
  }

  validation {
    # Bridge and host tasks share the instance's IP, so only SRV records carry their port.
    # https://docs.aws.amazon.com/AmazonECS/latest/developerguide/service-discovery.html
    condition = alltrue([for k, s in var.services : s.service_discovery == null ? true : alltrue([
      s.network_mode == "awsvpc" ? true : s.service_discovery.dns_record_type == "SRV",
      s.service_discovery.dns_record_type != "SRV" ? true : (s.service_discovery.container_port > 0 ? true : (length(s.containers) == 0 ? s.port > 0 : false)),
      s.service_discovery.container_name == "" ? true : (length(s.containers) == 0 ? s.service_discovery.container_name == k : contains(keys(s.containers), s.service_discovery.container_name)),
      s.service_discovery.dns_record_type != "SRV" ? true : (length(s.containers) == 0 ? true : s.service_discovery.container_name != ""),
    ])])
    error_message = "service_discovery: bridge and host networking need SRV records; SRV needs container_port (or the image shortcut's port) and, with containers, container_name naming one of them."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      s.log_group.create ? true : s.log_group.name != "",
      s.log_group.name == "" ? true : can(regex("^[A-Za-z0-9._/#-]{1,512}$", s.log_group.name)) ? !startswith(s.log_group.name, "aws/") : false,
      s.log_group.retention_days == null ? true : contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], s.log_group.retention_days),
      s.log_group.create ? true : s.log_group.retention_days == null,
      s.log_group.kms_key_arn == "" ? true : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", s.log_group.kms_key_arn)),
    ])])
    error_message = "log_group: create = false needs name (an existing group, whose retention is its owner's); name is 1-512 of letters, digits . _ - / # and not under aws/; retention_days is a CloudWatch Logs retention period or 0; kms_key_arn is empty or a key ARN (the group's key: for a created group it replaces log_kms_key_arn, for an existing one it is the key its owner set)."
  }

  validation {
    condition     = length(distinct([for k, s in var.services : s.log_group.name if s.log_group.create && s.log_group.name != ""])) == length([for k, s in var.services : s.log_group.name if s.log_group.create && s.log_group.name != ""])
    error_message = "Two workloads ask the module to create the same log_group.name. Create it once (on one workload) and point the others at it with create = false."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      alltrue([for c in s.placement_constraints : contains(["distinctInstance", "memberOf"], c.type)]),
      alltrue([for p in s.ordered_placement_strategy : contains(["binpack", "random", "spread"], p.type)]),
      length(s.ordered_placement_strategy) <= 5,
      length(s.placement_constraints) <= 10,
    ])])
    error_message = "placement_constraints types are distinctInstance or memberOf (at most 10); ordered_placement_strategy types are binpack, random or spread (at most 5)."
  }

  # --- roles --------------------------------------------------------------

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      s.task_role.create ? s.task_role.arn == "" : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", s.task_role.arn)),
      s.execution_role.create ? s.execution_role.arn == "" : can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/", s.execution_role.arn)),
      s.task_role.create ? true : length(s.task_role.policies) + length(s.task_role.managed_policies) == 0,
      s.execution_role.create ? true : length(s.execution_role.managed_policies) == 0,
    ])])
    error_message = "task_role and execution_role: create = true (the default) with no arn, or create = false with an IAM role ARN. policies and managed_policies are only applied to a role the module creates."
  }

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      alltrue([for n, d in s.task_role.policies : can(regex("^[A-Za-z0-9+=,.@_-]{1,128}$", n)) ? n != "ecs-module" : false]),
      alltrue([for n, d in s.task_role.policies : can(jsondecode(d).Statement)]),
    ])])
    error_message = "task_role.policies maps an inline policy name (letters, digits, +=,.@_-; not ecs-module, which the module uses) to an IAM policy document with a Statement."
  }

  # --- autoscaling --------------------------------------------------------

  validation {
    condition = alltrue([for k, s in var.services : s.autoscaling == null ? true : alltrue([
      s.autoscaling.min >= 0,
      s.autoscaling.max >= 1,
      s.autoscaling.min <= s.autoscaling.max,
      s.autoscaling.cpu_target == 0 ? true : (s.autoscaling.cpu_target >= 10 ? s.autoscaling.cpu_target <= 90 : false),
      s.autoscaling.memory_target == 0 ? true : (s.autoscaling.memory_target >= 10 ? s.autoscaling.memory_target <= 90 : false),
      s.autoscaling.requests_per_target >= 0,
      s.autoscaling.requests_per_target == 0 ? true : can(regex("^app/[^/]+/[0-9a-f]+/targetgroup/[^/]+/[0-9a-f]+$", s.autoscaling.alb_resource_label)),
      s.autoscaling.scale_in_cooldown >= 0,
      s.autoscaling.scale_out_cooldown >= 0,
    ])])
    error_message = "autoscaling: 0 <= min <= max, max >= 1; cpu_target and memory_target are 0 (off) or 10-90; requests_per_target needs alb_resource_label (app/<lb>/<id>/targetgroup/<tg>/<id>); cooldowns are 0 or more."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.autoscaling == null ? true : anytrue([
      s.autoscaling.cpu_target > 0, s.autoscaling.memory_target > 0, s.autoscaling.requests_per_target > 0,
      length(s.autoscaling.custom) > 0, length(s.autoscaling.schedules) > 0,
    ])])
    error_message = "autoscaling needs at least one of cpu_target, memory_target, requests_per_target, custom or schedules; otherwise nothing ever changes the task count."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.autoscaling == null ? true : alltrue([for n, sc in s.autoscaling.schedules : alltrue([
      can(regex("^(cron|rate|at)\\(.+\\)$", sc.schedule)), sc.min >= 0, sc.min <= sc.max,
    ])])])
    error_message = "autoscaling.schedules: schedule is cron(...), rate(...) or at(...), and 0 <= min <= max."
  }

  validation {
    condition = alltrue([for k, s in var.services : s.autoscaling == null ? true : alltrue([for n, c in s.autoscaling.custom :
    contains(["Average", "Minimum", "Maximum", "SampleCount", "Sum"], c.statistic)])])
    error_message = "autoscaling.custom[*].statistic must be Average, Minimum, Maximum, SampleCount or Sum."
  }

  # --- schedules ----------------------------------------------------------

  validation {
    condition = alltrue([for k, s in var.services : s.schedule == null ? true : alltrue([
      can(regex("^(cron|rate|at)\\(.+\\)$", s.schedule.expression)),
      s.schedule.task_count >= 1, s.schedule.task_count <= 10,
      s.schedule.flexible_window_minutes >= 0, s.schedule.flexible_window_minutes <= 1440,
      s.schedule.maximum_retry_attempts >= 0, s.schedule.maximum_retry_attempts <= 185,
      s.schedule.maximum_event_age_seconds >= 60, s.schedule.maximum_event_age_seconds <= 86400,
      s.schedule.dead_letter_queue_arn == "" ? true : can(regex("^arn:aws[a-z-]*:sqs:[a-z0-9-]+:[0-9]{12}:", s.schedule.dead_letter_queue_arn)),
      s.schedule.dead_letter_queue_kms_key_arn == "" ? true : (s.schedule.dead_letter_queue_arn == "" ? false : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", s.schedule.dead_letter_queue_kms_key_arn))),
    ])])
    error_message = "schedule: expression is cron(...), rate(...) or at(...); task_count 1-10; flexible_window_minutes 0-1440; maximum_retry_attempts 0-185; maximum_event_age_seconds 60-86400; dead_letter_queue_arn empty or an SQS queue ARN; dead_letter_queue_kms_key_arn empty, or a key ARN with a queue."
  }

  # --- alarms ---------------------------------------------------------------

  validation {
    condition = alltrue([for k, s in var.services : alltrue([
      s.alarms.cpu_percent >= 0, s.alarms.cpu_percent <= 100, s.alarms.memory_percent >= 0, s.alarms.memory_percent <= 100,
      s.alarms.min_running_tasks == null ? true : s.alarms.min_running_tasks >= 0,
    ])])
    error_message = "services[*].alarms: cpu_percent and memory_percent are 0 (the module default) or 1-100; min_running_tasks is unset (the lowest count the workload may run) or 0 (no running-task alarm) or more."
  }
}
