# landing-ecs

Terraform module for Amazon ECS on Fargate. Given a single `services` map it
provisions the cluster, services, task definitions, IAM, log groups, alarms,
and autoscaling.

What the module handles for you:

- Role-based services (`master`, `worker`, `scheduled`, `daemon`) that seed
  capacity strategy, autoscaling, and deployment defaults.
- Five capacity strategies including `spot_only` and `economy` (Spot + ARM64),
  plus scheduled scale-to-zero windows.
- A built-in container definition builder so callers describe `image`, `port`,
  `environment`, `secrets`, and the JSON is assembled for them.
- CloudWatch log groups, CPU/memory alarms, and an auto-generated dashboard.
- ECS Exec, Service Connect, X-Ray sidecar, EFS volumes, and EventBridge
  scheduled tasks as opt-ins.
- One shared task execution role plus a per-service task role; secret-access
  IAM is derived from the `secrets` references you actually declare.

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
      role   = "master"
      image  = "ghcr.io/acme/api:1.4.2"
      cpu    = 512
      memory = 1024
      port   = 8080

      load_balancer = {
        target_group_arn = aws_lb_target_group.api.arn
        container_port   = 8080
      }

      secrets = {
        DATABASE_URL = aws_secretsmanager_secret.db.arn
      }
    }

    worker = {
      role              = "worker"
      image             = "ghcr.io/acme/worker:1.4.2"
      capacity_strategy = "economy" # Spot + Graviton
      min_count         = 0
      max_count         = 20
    }
  }
}
```

The module creates the cluster, both services, a task execution role, two
task roles, log groups, CPU/memory alarms, autoscaling targets and policies,
and a CloudWatch dashboard.

## Concepts

### Roles

Every service carries a `role` that decides a few defaults.

| Role | Default capacity strategy | Autoscaling | Typical use |
|---|---|---|---|
| `master` | `stable` (prod) / `balanced` (non-prod) | on | HTTP APIs, latency-sensitive services |
| `worker` | `spot_preferred` | on, can scale to 0 | Queue consumers, async jobs |
| `scheduled` | `spot_only` | off | Cron-style tasks, migrations, batch jobs |
| `daemon` | `stable` | off | Log collectors, agents |

Any default can be overridden by setting the field on the service directly.

### Capacity strategies

| Strategy | Providers | Rough savings vs on-demand | Notes |
|---|---|---|---|
| `stable` | 100% FARGATE | 0% | SLA-bound paths |
| `balanced` | FARGATE base (1) + FARGATE_SPOT (weight 3) | 30-40% | Default for `master` in non-prod |
| `spot_preferred` | FARGATE_SPOT (weight 4) + FARGATE fallback (weight 1) | ~60% | Default for workers |
| `spot_only` | 100% FARGATE_SPOT | ~70% | Stateless, interruption-tolerant |
| `economy` | FARGATE_SPOT + ARM64/Graviton | 75-80% | Requires multi-arch image |

`economy` auto-sets `cpu_architecture = "ARM64"`, so the image needs a
`linux/arm64` manifest. Either build multi-arch with
`docker buildx build --platform linux/amd64,linux/arm64 ...` or override
`cpu_architecture = "X86_64"` explicitly.

### Tagging

Four tags are always set by the module and win over `var.tags`:
`Environment`, `Name`, `ManagedBy`, `Module`. Everything else (including
FinOps tags like `Project`, `Team`, `CostCenter`) comes from `var.tags`.

### Cost estimate

The `cost_estimates` output returns a rough monthly USD per task per service:

```
cost_estimates = {
  api = {
    strategy                       = "stable"
    vcpu_per_task                  = 0.5
    memory_gb_per_task             = 1
    estimated_monthly_usd_per_task = 17.78
  }
  worker = {
    strategy                       = "economy"
    vcpu_per_task                  = 0.25
    memory_gb_per_task             = 0.5
    estimated_monthly_usd_per_task = 1.77
  }
}
```

Numbers use us-east-1 on-demand Fargate pricing with spot/economy discounts.
Real bills depend on region, reserved capacity, and actual usage.

## Module inputs

### Cluster & tagging

| Name | Type | Default | Description |
|---|---|---|---|
| `cluster_name` | `string` | *(required)* | Prefix for every resource the module creates |
| `environment` | `string` | `"dev"` | One of `dev`, `staging`, `prod`, `sandbox`, `test`. Drives some defaults and emitted as the `Environment` tag. |
| `tags` | `map(string)` | `{}` | Tags applied to every resource. Put FinOps tags (Project, Team, CostCenter, ...) here. |
| `enable_container_insights` | `bool` | `true` | Adds ~$0.35/task/month |

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
| `alarm_cpu_threshold` | `number` | `80` | |
| `alarm_memory_threshold` | `number` | `80` | |
| `alarm_actions` | `list(string)` | `[]` | SNS topic ARNs |
| `create_cloudwatch_dashboard` | `bool` | `true` | |

### Service Connect

| Name | Type | Default | Description |
|---|---|---|---|
| `service_connect_namespace` | `string` | `null` | Cloud Map namespace ARN; required if any service sets `service_connect_enabled` |

### Services

`var.services` is a `map(object({...}))`, one entry per service.

```hcl
services = {
  <name> = {
    role  = "master"            # master | worker | scheduled | daemon
    image = "..."               # required

    cpu    = 256
    memory = 512

    capacity_strategy = "stable"   # stable | balanced | spot_preferred | spot_only | economy
    cpu_architecture  = "X86_64"   # X86_64 | ARM64

    port             = 8080
    protocol         = "tcp"
    subnets          = null        # overrides module default
    security_groups  = []
    assign_public_ip = false

    desired_count      = 1
    min_count          = 1
    max_count          = 10
    enable_autoscaling = null      # null => role default

    schedule_scaling = {
      scale_down_cron    = "cron(0 20 ? * MON-FRI *)"
      scale_up_cron      = "cron(0 7 ? * MON-FRI *)"
      scale_down_min_cap = 0
      scale_down_max_cap = 0
      scale_up_min_cap   = 1
      scale_up_max_cap   = 5
    }

    environment = { LOG_LEVEL = "info" }
    secrets     = { DATABASE_URL = "arn:aws:secretsmanager:..." }

    load_balancer = {
      target_group_arn = "arn:..."
      container_port   = 8080
    }

    health_check = {
      command      = ["CMD-SHELL", "curl -sf http://localhost/health || exit 1"]
      interval     = 30
      timeout      = 5
      retries      = 3
      start_period = 60
    }

    deployment_minimum_healthy_percent = 100
    deployment_maximum_percent         = 200
    enable_circuit_breaker             = true
    enable_rollback                    = true
    health_check_grace_period_seconds  = 0

    task_role_statements = [
      {
        sid       = "S3Read"
        actions   = ["s3:GetObject"]
        resources = ["arn:aws:s3:::my-bucket/*"]
      }
    ]

    xray_enabled = false

    service_connect_enabled = false

    readonly_root_filesystem = false
    enable_exec              = null   # null => module default
    create_security_group    = null

    ephemeral_storage_gib = 21        # AWS minimum
    volumes = [
      {
        name = "shared"
        efs_volume_configuration = {
          file_system_id  = "fs-xxxx"
          access_point_id = "fsap-xxxx"
        }
      }
    ]
    mount_points = [
      { volume_name = "shared", container_path = "/data" }
    ]

    stop_timeout = 30                 # graceful shutdown window, seconds

    # only valid when role = "scheduled"
    run_schedule = "cron(0 2 * * ? *)"

    tags = { Component = "api" }

    # escape hatch: supply the raw container_definitions list yourself
    container_definitions_override = null
  }
}
```

## Recipes

### Production API with autoscaling and tracing

```hcl
api = {
  role   = "master"
  image  = "..."
  cpu    = 512
  memory = 1024
  port   = 8080

  desired_count = 3
  min_count     = 3
  max_count     = 20

  load_balancer = {
    target_group_arn = aws_lb_target_group.api.arn
    container_port   = 8080
  }

  health_check = {
    command      = ["CMD-SHELL", "curl -sf http://localhost:8080/health || exit 1"]
    start_period = 60
  }

  xray_enabled = true
  stop_timeout = 60   # give in-flight requests time to finish
}
```

### Queue worker on Spot + Graviton

```hcl
worker = {
  role              = "worker"
  image             = "..."         # must be multi-arch
  capacity_strategy = "economy"     # sets cpu_architecture = "ARM64"
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
  role         = "scheduled"
  image        = "..."
  run_schedule = "cron(0 2 * * ? *)"   # 2am UTC daily
  cpu          = 1024
  memory       = 2048

  task_role_statements = [
    {
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.reports.arn}/*"]
    }
  ]
}
```

The service is created with `desired_count = 0`. EventBridge calls `RunTask`
on the service's task definition at the scheduled time.

### EFS-backed stateful service

```hcl
cms = {
  role   = "master"
  image  = "..."
  port   = 80

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

| Name | Description |
|---|---|
| `cluster_id` / `cluster_arn` / `cluster_name` | The ECS cluster |
| `service_ids` / `service_names` | Service name to resource ID/name |
| `task_definition_arns` / `task_definition_families` / `task_definition_revisions` | Per-service task def metadata |
| `task_execution_role_arn` / `task_execution_role_name` | Shared execution role |
| `task_role_arns` / `task_role_names` | Per-service task roles |
| `service_security_group_ids` | Managed SG IDs (empty for services without `create_security_group`) |
| `log_group_names` / `log_group_arns` | Per-service log groups |
| `dashboard_arn` / `dashboard_name` | CloudWatch dashboard |
| `autoscaling_target_resource_ids` | App Autoscaling targets |
| `scheduled_task_rule_arns` / `scheduled_task_rule_names` | EventBridge rules for `run_schedule` services |
| `cost_estimates` | Per-service estimated monthly USD per task |
| `summary` | Consolidated object combining the above |

## Design notes

**Why split `aws_ecs_service.autoscaled` and `aws_ecs_service.static`?**
Autoscaled services need `lifecycle { ignore_changes = [desired_count] }` so
Terraform doesn't fight App Autoscaling after creation. Static services
benefit from Terraform managing `desired_count` normally. A `lifecycle`
block can't be dynamic, so the module uses two separate resources.

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
  full scenario with master + worker + scheduled service, ALB, Secrets
  Manager, and X-Ray.
- [`examples/landing-ecs/green-blue.tf`](../../examples/landing-ecs/green-blue.tf) —
  blue/green deployment using a weighted ALB listener.

## Requirements

- Terraform `>= 1.5.0`
- AWS provider `~> 5.0`
