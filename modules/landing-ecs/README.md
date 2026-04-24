# landing-ecs

Terraform module for Amazon ECS on Fargate. Given a single `services` map it
provisions the cluster, services, task definitions, IAM, log groups, alarms,
and autoscaling.

Fargate-only. The module hard-pins `network_mode = "awsvpc"` and the Fargate
launch type; it does not support EC2 capacity, DAEMON scheduling, or classic
networking.

What the module handles for you:

- Five capacity strategies (`stable`, `balanced`, `spot_preferred`,
  `spot_only`, `economy`) plus scheduled scale-to-zero windows.
- A built-in container definition builder. Start with flat shortcuts
  (`image`, `port`, `environment`, `secrets`) or declare a multi-container
  task via the `containers` map for sidecars, init containers, or Firelens
  log routing.
- Full container fields exposed: `command`, `entrypoint`, `working_directory`,
  `user`, `docker_labels`, `ulimits`, `linux_parameters`, `depends_on`,
  `health_check`, `start_timeout`, `stop_timeout`, any log driver.
- Autoscaling: CPU + memory target tracking by default, with per-service
  overrides and arbitrary custom target-tracking policies (ALB request
  count, SQS depth, any CloudWatch metric).
- Per-service alarm overrides (thresholds and SNS actions) on top of module
  defaults.
- Deployment controller choice per service (`ECS`, `CODE_DEPLOY`, `EXTERNAL`).
- Multiple target groups per service, Service Connect with client aliases,
  EFS volumes, EventBridge scheduled tasks.
- CloudWatch log groups and per-service alarms. No dashboard (opinionated
  cut — use Grafana/Datadog/CloudWatch custom dashboards per team).
- **Per-service task execution role by default** (least-privilege: one
  service's compromised role can't read another's secrets). Opt into a
  shared role with `per_service_execution_role = false`.
- Per-service task role with IAM condition-key support; secret-access IAM
  is derived from declared secrets.
- Extra capacity providers (e.g. EC2 ASG-backed) registerable on the cluster.

## Quick start

```hcl
module "ecs" {
  source = "git::https://github.com/your-org/tf-modules.git//modules/landing-ecs"

  cluster_name = "my-app-prod"
  environment  = "prod"

  tags = {
    Project    = "my-app"
    Team       = "platform"
    CostCenter = "ENG-042"
  }

  default_subnets = data.aws_subnets.private.ids
  vpc_id          = data.aws_vpc.main.id

  services = {
    api = {
      image  = "ghcr.io/acme/api:1.4.2"
      cpu    = 512
      memory = 1024
      port   = 8080

      # Defaults: capacity_strategy = "stable", enable_autoscaling = true.

      load_balancer = {
        target_group_arn = aws_lb_target_group.api.arn
        container_port   = 8080
      }
      health_check_grace_period_seconds = 30

      secrets = {
        DATABASE_URL = aws_secretsmanager_secret.db.arn
      }
    }

    worker = {
      image             = "ghcr.io/acme/worker:1.4.2"
      capacity_strategy = "economy" # 100% Fargate Spot
      cpu_architecture  = "ARM64"   # opt into Graviton (image must be multi-arch)
      min_count         = 0
      max_count         = 20
    }
  }
}
```

The module creates the cluster, both services, per-service execution + task
roles, log groups, CPU/memory alarms, and autoscaling targets + policies.

## Concepts

### Configuring services

Services are configured field-by-field — no `role` abstraction. Useful
defaults:

| Knob | Default | Common overrides |
|---|---|---|
| `capacity_strategy` | `"stable"` (100% on-demand) | `"spot_preferred"` for workers; `"spot_only"` for batch |
| `cpu_architecture` | `"X86_64"` | `"ARM64"` for Graviton savings (image must have a `linux/arm64` manifest) |
| `enable_autoscaling` | `true` (via `var.enable_autoscaling_default`) | `false` for batch / scheduled (`run_schedule`) |
| `desired_count` / `min_count` / `max_count` | `1` / `1` / `10` | tune per service |
| `deployment_controller` | `"ECS"` | `"CODE_DEPLOY"` for blue/green |

### Capacity strategies

| Strategy | Providers | Rough savings vs on-demand | Notes |
|---|---|---|---|
| `stable` | 100% FARGATE | 0% | SLA-bound paths |
| `balanced` | FARGATE base (1) + FARGATE_SPOT (weight 3) | 30-40% | Mixed-risk services in non-prod |
| `spot_preferred` | FARGATE_SPOT (weight 4) + FARGATE fallback (weight 1) | ~60% | Default for workers |
| `spot_only` | 100% FARGATE_SPOT | ~70% | Stateless, interruption-tolerant |
| `economy` | 100% FARGATE_SPOT | ~70% | Same providers as `spot_only`; combine with `cpu_architecture = "ARM64"` for Graviton savings on top |

Capacity strategy and CPU architecture are independent axes. `economy` does
not imply ARM64 anymore — set `cpu_architecture = "ARM64"` explicitly, and
make sure the image has a `linux/arm64` manifest (`docker buildx build
--platform linux/amd64,linux/arm64 ...`).

### Execution roles

Default (`per_service_execution_role = true`): each service gets its own
task-execution role, scoped to just that service's declared secrets. A
compromised role exposes one service's secrets, not all of them.

Set `per_service_execution_role = false` for a single shared execution role.
Cheaper on IAM resource count but the shared role sees every secret.

### Tagging

Four tags are always set by the module and win over `var.tags`:
`Environment`, `Name`, `ManagedBy`, `Module`. Everything else (including
FinOps tags like `Project`, `Team`, `CostCenter`) comes from `var.tags`.

## Multi-container tasks

A service can declare one or many containers via `containers`. Flat
shortcuts (`image`, `port`, ...) act as sugar for the simple case and build
a single container under the hood.

```hcl
services = {
  web = {
    # Task-level sizing (Fargate requires specific cpu+memory combinations).
    task_cpu    = 1024
    task_memory = 2048

    containers = {
      app = {
        image     = "ghcr.io/acme/api:1.4.2"
        cpu       = 512
        memory    = 1024
        essential = true
        port      = 8080

        command           = ["node", "server.js"]
        working_directory = "/app"
        user              = "1000:1000"
        docker_labels     = { "com.datadoghq.ad.logs" = "[{\"source\":\"node\"}]" }

        ulimits = [
          { name = "nofile", soft_limit = 65536, hard_limit = 65536 },
        ]

        linux_parameters = {
          init_process_enabled = true
        }

        health_check = {
          command      = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
          start_period = 30
        }
      }

      # Reverse proxy that only starts once the app is HEALTHY.
      nginx = {
        image     = "nginx:alpine"
        cpu       = 256
        memory    = 512
        essential = true
        port      = 80

        depends_on = [
          { container_name = "app", condition = "HEALTHY" },
        ]

        readonly_root_filesystem = true
      }
    }
  }
}
```

## Custom autoscaling policies

Per-service CPU + memory target tracking stays on by default (toggle with
`enable_cpu_autoscaling` / `enable_memory_autoscaling`). Anything else goes
in `custom_scaling_policies`:

```hcl
services = {
  api = {
    # ...

    # Default target values overridden per service.
    cpu_target_value    = 55
    memory_target_value = 70

    custom_scaling_policies = [
      # Built-in ECS/ALB metric.
      {
        name                   = "request-count"
        target_value           = 1000
        predefined_metric_type = "ALBRequestCountPerTarget"
        resource_label         = "app/my-alb/xxx/targetgroup/my-tg/yyy"
      },

      # Any CloudWatch metric (example: SQS queue depth for workers).
      {
        name         = "sqs-depth"
        target_value = 50
        customized_metric = {
          metric_name = "ApproximateNumberOfMessagesVisible"
          namespace   = "AWS/SQS"
          statistic   = "Average"
          dimensions  = [{ name = "QueueName", value = "jobs" }]
        }
      },
    ]
  }
}
```

## Per-service alarm overrides

Module defaults apply to every service; any service can raise or lower its
thresholds and re-route alarm actions to a different SNS topic:

```hcl
services = {
  api = {
    # ...
    alarm_cpu_threshold    = 90
    alarm_memory_threshold = 95
    alarm_actions          = [aws_sns_topic.pager.arn]
  }

  batch = {
    # ...
    # Long CPU spikes are normal on the batch job, so skip the CPU alarm.
    enable_cpu_autoscaling = false
    alarm_cpu_threshold    = 99 # effectively disabled
  }
}
```

## Module inputs

### Cluster & tagging

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | *(required)* | Prefix for every resource the module creates |
| `environment` | `string` | `"dev"` | One of `dev`, `staging`, `prod`, `sandbox`, `test`. Drives some defaults and emitted as the `Environment` tag. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. Put FinOps tags (Project, Team, CostCenter, ...) here. |
| `enable_container_insights` | `bool` | `true` | Adds ~$0.35/task/month |
| `cluster_settings` | `map(string)` | `{}` | Extra key/value settings passed to aws_ecs_cluster.setting |
| `capacity_providers` | `list(string)` | `[]` | Additional capacity providers beyond FARGATE/FARGATE_SPOT |
| `default_capacity_provider_strategy` | list of objects | FARGATE base=1 | Fallback strategy for tasks launched without their own strategy |

### Networking

| Name | Type | Default | Description |
|---|---|---|---|
| `vpc_id` | `string` | `""` | Required when `create_service_security_groups = true` |
| `default_subnets` | `list(string)` | `[]` | Default subnets for tasks; overridable per service |

### Defaults

| Name | Type | Default | Description |
|---|---|---|---|
| `enable_execute_command` | `bool` | `false` | Module-wide ECS Exec |
| `create_service_security_groups` | `bool` | `false` | Auto-create a per-service SG |
| `enable_autoscaling_default` | `bool` | `true` | |
| `propagate_tags` | `string` | `"TASK_DEFINITION"` | `TASK_DEFINITION`, `SERVICE`, or `NONE` |
| `default_deployment_controller` | `string` | `"ECS"` | Used when a service doesn't specify one |
| `default_cpu_target_value` | `number` | `60` | CPU target % for the default CPU autoscaling policy |
| `default_memory_target_value` | `number` | `70` | Memory target % for the default memory autoscaling policy |
| `default_scale_in_cooldown` | `number` | `300` | Default scale-in cooldown seconds |
| `default_scale_out_cooldown` | `number` | `60` | Default scale-out cooldown seconds |

### Config injection

| Name | Type | Default | Description |
|---|---|---|---|
| `global_environment` | `map(string)` | `{}` | Env vars injected into every container |
| `global_secrets` | `map(string)` | `{}` | Secrets injected into every container; per-service merges on top |

### Observability

| Name | Type | Default | Description |
|---|---|---|---|
| `log_retention_days` | `number` | `30` | CloudWatch retention (0 = never expire) |
| `kms_key_arn` | `string` | `null` | KMS CMK for log encryption |
| `create_cloudwatch_alarms` | `bool` | `true` | CPU + memory alarms per service |
| `alarm_cpu_threshold` | `number` | `80` | Default; services can override |
| `alarm_memory_threshold` | `number` | `80` | Default; services can override |
| `alarm_evaluation_periods` | `number` | `2` | 60s periods an alarm must breach before firing |
| `alarm_actions` | `list(string)` | `[]` | Default SNS topic ARNs; services can override |

### IAM

| Name | Type | Default | Description |
|---|---|---|---|
| `per_service_execution_role` | `bool` | `true` | One execution role per service (least-privilege). Set false to share a single execution role across all services. |

### Service Connect

| Name | Type | Default | Description |
|---|---|---|---|
| `service_connect_namespace` | `string` | `null` | Cloud Map namespace ARN; required if any service sets `service_connect_enabled` |

### Services

`var.services` is a `map(object({...}))`, one entry per service. Every field
below is optional unless marked `*(required)*`. Fields that feed the single
main container (`image`/`command`/`environment`/...) act as shortcuts; when
`containers` is set, those shortcuts are ignored.

```hcl
services = {
  <name> = {
    # ─── Main-container shortcuts ──────────────────────────────────────
    # image is *(required)* when `containers` is empty.
    image             = "ghcr.io/acme/api:1.4.2"
    command           = null
    entrypoint        = null
    working_directory = null
    user              = null
    environment       = { LOG_LEVEL = "info" }
    secrets           = { DATABASE_URL = "arn:aws:secretsmanager:..." }
    port              = 8080
    protocol          = "tcp"
    docker_labels     = {}
    ulimits           = []
    linux_parameters  = null
    health_check = {
      command      = ["CMD-SHELL", "curl -sf http://localhost/health || exit 1"]
      start_period = 30
    }
    stop_timeout             = 30
    start_timeout            = null
    readonly_root_filesystem = false
    mount_points             = []
    log_driver               = "awslogs"
    log_options              = {}
    log_secret_options       = {}

    # ─── Multi-container form (ignores the shortcuts above when set) ───
    containers = {
      app = {
        image      = "ghcr.io/acme/api:1.4.2"
        cpu        = 512
        memory     = 1024
        essential  = true
        port       = 8080
        # plus: command, entrypoint, working_directory, user,
        # environment, secrets, health_check, docker_labels, ulimits,
        # linux_parameters, depends_on, mount_points, volumes_from,
        # log_driver, log_options, log_secret_options, stop_timeout,
        # start_timeout, readonly_root_filesystem, additional_ports,
        # memory_reservation.
      }
    }

    # ─── Task-level compute ───────────────────────────────────────────
    task_cpu    = null               # null => cpu shortcut below
    task_memory = null               # null => memory shortcut below
    cpu         = 256
    memory      = 512

    capacity_strategy = "stable"     # stable | balanced | spot_preferred | spot_only | economy
    cpu_architecture  = "X86_64"     # X86_64 | ARM64

    # ─── Networking ───────────────────────────────────────────────────
    subnets          = null          # overrides module default
    security_groups  = []
    assign_public_ip = false

    # ─── Scaling ──────────────────────────────────────────────────────
    desired_count             = 1
    min_count                 = 1
    max_count                 = 10
    enable_autoscaling        = null     # null => role default
    enable_cpu_autoscaling    = true
    enable_memory_autoscaling = true
    cpu_target_value          = null     # null => module default
    memory_target_value       = null
    scale_in_cooldown         = null
    scale_out_cooldown        = null

    custom_scaling_policies = [
      {
        name                   = "request-count"
        target_value           = 1000
        predefined_metric_type = "ALBRequestCountPerTarget"
        resource_label         = "app/my-alb/xxx/targetgroup/my-tg/yyy"
      }
    ]

    schedule_scaling = {
      scale_down_cron    = "cron(0 20 ? * MON-FRI *)"
      scale_up_cron      = "cron(0 7 ? * MON-FRI *)"
      scale_down_min_cap = 0
      scale_down_max_cap = 0
      scale_up_min_cap   = 1
      scale_up_max_cap   = 5
    }

    # ─── Load balancers ───────────────────────────────────────────────
    load_balancer = {
      target_group_arn = "arn:..."
      container_port   = 8080
      container_name   = null       # defaults to the main container
    }
    additional_load_balancers = [
      { target_group_arn = "...", container_port = 8080 },
    ]

    # ─── Deployment ───────────────────────────────────────────────────
    deployment_controller              = null   # null => module default (ECS)
    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent         = 200
    enable_circuit_breaker             = true
    enable_rollback                    = true
    health_check_grace_period_seconds  = 0

    # ─── IAM: task-role policy statements ─────────────────────────────
    task_role_statements = [
      {
        sid       = "S3Read"
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::my-bucket/*"]
        condition = {
          StringEquals = { "aws:ResourceTag/Env" = ["prod"] }
        }
      }
    ]

    # ─── Service mesh ─────────────────────────────────────────────────
    # X-Ray / Datadog / Firelens etc. run as regular containers in the
    # `containers` map; there is no dedicated sidecar flag.
    service_connect_enabled = false
    service_connect_alias   = null     # default: service name

    # ─── Security ─────────────────────────────────────────────────────
    readonly_root_filesystem = false
    enable_exec              = null    # null => module default
    create_security_group    = null

    # ─── Storage ──────────────────────────────────────────────────────
    ephemeral_storage_gib = 21
    volumes = [
      {
        name = "shared"
        efs_volume_configuration = {
          file_system_id  = "fs-xxxx"
          access_point_id = "fsap-xxxx"
        }
      }
    ]

    # ─── Per-service alarm overrides (null => module default) ─────────
    alarm_cpu_threshold    = null
    alarm_memory_threshold = null
    alarm_actions          = null

    # ─── Scheduled execution (requires enable_autoscaling = false) ────
    run_schedule = "cron(0 2 * * ? *)"

    tags = { Component = "api" }

    # Escape hatch: supply a raw container_definitions list yourself.
    container_definitions_override = null
  }
}
```

## Recipes

### Production API with autoscaling and X-Ray sidecar

```hcl
api = {
  task_cpu    = 544
  task_memory = 1280

  containers = {
    app = {
      image     = "ghcr.io/acme/api:1.4.2"
      cpu       = 512
      memory    = 1024
      essential = true
      port      = 8080

      health_check = {
        command      = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
        start_period = 60
      }

      stop_timeout = 60 # give in-flight requests time to finish
    }

    xray = {
      image     = "amazon/aws-xray-daemon:3"
      cpu       = 32
      memory    = 256
      essential = false
      port      = 2000
      protocol  = "udp"
    }
  }

  desired_count = 3
  min_count     = 3
  max_count     = 20

  load_balancer = {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "app"
    container_port   = 8080
  }
  health_check_grace_period_seconds = 30

  task_role_statements = [
    {
      sid       = "XRayWrite"
      actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
      resources = ["*"]
    },
  ]
}
```

### Queue worker on Spot + Graviton

```hcl
worker = {
  image             = "..."         # must be multi-arch
  capacity_strategy = "economy"     # 100% Fargate Spot
  cpu_architecture  = "ARM64"       # Graviton; image needs a linux/arm64 manifest
  cpu               = 256
  memory            = 512

  min_count = 0    # scale to zero when queue is empty
  max_count = 30

  task_role_statements = [
    {
      actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage"]
      resources = [aws_sqs_queue.jobs.arn]
    }
  ]
}
```

### Nightly batch job via EventBridge

```hcl
nightly_reports = {
  image        = "..."
  cpu          = 1024
  memory       = 2048

  # run_schedule + autoscaling are mutually exclusive. The service stays at
  # desired_count = 0 and EventBridge calls RunTask on the cadence.
  run_schedule       = "cron(0 2 * * ? *)"   # 2am UTC daily
  desired_count      = 0
  min_count          = 0
  max_count          = 1
  enable_autoscaling = false

  # Scheduled-kickoff services also need a zero min-healthy percent so ECS
  # can start the first task from a zero baseline.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100

  capacity_strategy = "spot_only" # cheap; rerun on interruption

  task_role_statements = [
    {
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.reports.arn}/*"]
    }
  ]
}
```

### EFS-backed stateful service

```hcl
cms = {
  image = "..."
  port  = 80

  volumes = [
    {
      name = "uploads"
      efs_volume_configuration = {
        file_system_id  = aws_efs_file_system.uploads.id
        access_point_id = aws_efs_access_point.uploads.id
      }
    }
  ]

  mount_points = [
    { volume_name = "uploads", container_path = "/var/www/uploads" }
  ]
}
```

### Scale non-prod to zero overnight

```hcl
schedule_scaling = {
  scale_down_cron    = "cron(0 20 ? * MON-FRI *)"
  scale_up_cron      = "cron(0 7 ? * MON-FRI *)"
  scale_down_min_cap = 0
  scale_down_max_cap = 0
  scale_up_min_cap   = 1
  scale_up_max_cap   = 5
}
```

## Outputs

Core outputs (typical downstream wiring):

| Name | Description |
|---|---|
| `cluster_name` / `cluster_arn` | The ECS cluster |
| `service_names` | Service name to ECS service name |
| `task_role_arns` | Per-service task role ARNs |
| `task_execution_role_arns` | Per-service execution role ARNs (all equal when `per_service_execution_role = false`) |
| `log_group_names` | Per-service CloudWatch log group names |
| `service_security_group_ids` | Managed SG IDs (empty when `create_security_group` is false) |
| `summary` | Flat object combining the above |

Advanced outputs (inspection, wiring, CI):

| Name | Description |
|---|---|
| `cluster_id` / `cluster_capacity_providers` | Cluster details |
| `service_ids` / `service_deployment_controllers` | Service metadata |
| `task_definition_arns` / `task_definition_families` / `task_definition_revisions` | Task definition metadata |
| `container_names` | Per-service resolved container list |
| `task_role_names` / `log_group_arns` | IAM/logs name/ARN variants |
| `alarm_arns` | Per-service CPU and memory alarm ARNs |
| `autoscaling_target_resource_ids` / `custom_scaling_policy_arns` | Autoscaling wiring |
| `scheduled_task_rule_arns` / `scheduled_task_rule_names` | EventBridge rules for `run_schedule` services |

## Design notes

**Why split `aws_ecs_service.autoscaled` and `aws_ecs_service.static`?**
Autoscaled services need `lifecycle { ignore_changes = [desired_count] }` so
Terraform doesn't fight App Autoscaling after creation. Static services
benefit from Terraform managing `desired_count` normally. A `lifecycle`
block can't be dynamic, so the module uses two separate resources. The
resource bodies share `local.service_common_args` to keep them in sync.

**Why no dashboard?**
CloudWatch dashboards auto-generated in a module don't scale past a handful
of services (widget limits), bake in opinionated layouts, and most teams
ship observability elsewhere (Grafana, Datadog, New Relic). The module
emits the raw metrics; build dashboards where your alerting + SLO tooling
already lives.

**Why no cost-estimate output?**
An accurate number would have to account for region, Savings Plans,
reserved Fargate, NAT egress, CloudWatch cost, and sidecars. An inaccurate
number is worse than no number. Use tags + CUR/Cost Explorer for real
attribution.

**Why per-service execution roles by default?**
Least privilege. A compromised execution role with access to every
service's secrets is a wide blast radius; per-service roles cap it at one
service. The shared-role option remains for small clusters where the
tradeoff is acceptable.

**Why does `mount_points` require an explicit `volumes` block?**
That's how ECS works. `mountPoints` in the container definition references
a named volume declared on the task definition; the module surfaces both so
the mapping stays explicit.

**Why Service Connect but not App Mesh?**
Service Connect is ECS-native and needs no per-task Envoy sidecar. App Mesh
is being wound down by AWS.

**Why is `platform_version` hard-coded to `LATEST`?**
AWS recommends `LATEST` for Fargate. If you hit a genuine need to pin an
earlier version, open a PR.

## Known limitations

- No CodeDeploy BLUE_GREEN controller. The module uses rolling deployments
  with circuit breaker and rollback. See `examples/landing-ecs/green-blue.tf`
  for an ALB-weighted-listener pattern that achieves similar outcomes.
- Autoscaling is CPU + memory target tracking only. Add a custom
  `aws_appautoscaling_policy` at the root module if you need request-count
  target tracking or step scaling.
- Five preset capacity strategies; custom weights aren't exposed.
- Volumes support EFS only. Bind mounts and Docker volumes aren't practical
  on Fargate.

## Related docs

- [`examples/landing-ecs/basic.tf`](../../examples/landing-ecs/basic.tf) —
  minimal single-service nginx deployment in the default VPC.
- [`examples/landing-ecs/main.tf`](../../examples/landing-ecs/main.tf) —
  full scenario with an API + worker + scheduled migration service, ALB, Secrets
  Manager, and X-Ray.
- [`examples/landing-ecs/green-blue.tf`](../../examples/landing-ecs/green-blue.tf) —
  blue/green deployment using a weighted ALB listener.
- [`examples/landing-ecs/advanced.tf`](../../examples/landing-ecs/advanced.tf) —
  multi-container tasks (nginx + app with `depends_on`), Firelens log
  routing, custom scaling policies, and per-service alarm overrides.

## Requirements

- Terraform `>= 1.5.0`
- AWS provider `~> 5.0`
