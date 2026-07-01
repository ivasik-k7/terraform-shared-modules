# ECS Orchestrator

The canonical Amazon ECS orchestration module for the platform. It manages the
ECS-native resources — cluster, capacity-provider registration, task
definitions, services, application auto scaling, Service Connect, Cloud Map
discovery, ECS Exec, and the task + execution IAM roles — and **composes** with
the rest of the AWS ecosystem rather than reimplementing it.

It supports **multiple launch types** (Fargate, Fargate Spot, and EC2 capacity
providers) on the same cluster, driven per service by `capacity_provider_strategy`
— there is no `launch_type` enum to box you in.

## Design principles

- **Orchestrator, not builder.** Creates ECS resources only. VPCs, subnets, load
  balancers, EFS/FSx file systems, EC2 Auto Scaling Groups, KMS keys, and secrets
  are **referenced by id/ARN**, never created here.
- **Works standalone.** With nothing but a `cluster_name`, subnets, and a
  `services` map you get a running Fargate service — no other modules required.
  Composition with `lb`/`efs`/`asg` is optional, not assumed.
- **Multi-launch by strategy.** Fargate + EC2 in any mix via
  `capacity_provider_strategy`; `network_mode`/`requires_compatibilities` are
  configurable per service.
- **AWS-native vocabulary.** Inputs/outputs mirror the ECS API
  (`capacity_provider_strategy`, `deployment_circuit_breaker`,
  `service_connect_configuration`, `runtime_platform`, `ephemeral_storage`,
  `volume_configuration`, `placement_constraints`).
- **Secure & cost-aware defaults.** Secrets referenced by ARN only (with a scoped
  execution-role read policy generated automatically); Container Insights and
  detailed signals off by default; least-privilege task/execution roles.

## Standalone — no other modules

```hcl
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter { name = "vpc-id" values = [data.aws_vpc.default.id] }
}

module "ecs" {
  source = "../../modules/ecs-orchestrator"

  cluster_name    = "demo"
  default_subnets = data.aws_subnets.default.ids

  services = {
    web = {
      image = "nginx:alpine"
      port  = 80
      # capacity_provider_strategy defaults to nothing -> uses the cluster
      # default / Fargate. Add a strategy to pin Fargate or mix in EC2.
      capacity_provider_strategy = [{ capacity_provider = "FARGATE", weight = 1, base = 1 }]
    }
  }
}
```

That's it — cluster, task definition (IMDSv2-safe awslogs logging), execution
role, log group, and service, with zero dependency on `lb`, `efs`, or `asg`.

Mixed launch types, references (ALB/EFS/secrets), Service Connect, and
autoscaling are all covered in **Examples** below.

## Storage: reference vs task-native

| Need                                | Use                                                                          |
| ----------------------------------- | ---------------------------------------------------------------------------- |
| Shared/persistent filesystem        | `volumes.*.efs` (file system from the `efs` module)                          |
| FSx                                 | `volumes.*` (FSx referenced)                                                 |
| Scratch space (Fargate)             | `ephemeral_storage_gib`                                                      |
| Task-managed EBS attached at launch | `managed_ebs_volume` (+ a `volumes` entry with `configure_at_launch = true`) |
| Host disks for EC2 capacity         | the `ebs` module, on the ASG hosts (not here)                                |

## Examples

Five end-to-end scenarios, inlined in full below — copy-paste runnable, no
external files to chase.

| #   | Scenario                    | Shows                                                                                  |
| --- | --------------------------- | -------------------------------------------------------------------------------------- |
| 1   | Cost-optimized Fargate Spot | Spot + on-demand baseline, ALB, autoscaling (incl. scheduled), CloudWatch alarms → SNS |
| 2   | Service Connect mesh        | edge → api → worker over one namespace, public edge only                               |
| 3   | EC2 capacity provider       | mixed Fargate + EC2 ASG-backed capacity on one service                                 |
| 4   | Composed references         | ALB + EFS + secrets referenced by ARN/id                                               |
| 5   | EC2 launch type             | plain EC2 hosts joined to the cluster, `launch_type = "EC2"`, bridge networking        |

### 1. Cost-optimized Fargate Spot (ALB + autoscaling + alarms)

A small on-demand baseline for availability, everything above it on
`FARGATE_SPOT` for ~70% savings. Fronted by an ALB, target-tracked autoscaling
with a day/night schedule, and CPU/memory alarms wired to SNS.

```hcl
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "alb" {
  source  = "../../modules/lb"
  name    = "spot-web-alb"
  vpc_id  = data.aws_vpc.default.id
  subnets = data.aws_subnets.default.ids

  security_group_ingress_rules = {
    http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
  }
  target_groups = {
    web = {
      port         = 8080
      protocol     = "HTTP"
      target_type  = "ip"
      health_check = { path = "/", matcher = "200-399" }
    }
  }
  listeners = {
    http = {
      port           = 80
      default_action = { type = "forward", target_group_key = "web" }
    }
  }
}

# service SG the ALB can reach (created here so there's no module<->module cycle)
resource "aws_security_group" "service" {
  name_prefix = "spot-web-svc-"
  description = "spot web tasks"
  vpc_id      = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  security_group_id            = aws_security_group.service.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
}

resource "aws_sns_topic" "alerts" { name_prefix = "spot-web-alerts-" }

module "ecs" {
  source          = "../../modules/ecs-orchestrator"
  cluster_name    = "spot-web"
  default_subnets = data.aws_subnets.default.ids

  create_cloudwatch_alarms = true # CPU/mem alarms need no Insights
  alarm_cpu_threshold      = 75
  alarm_actions            = [aws_sns_topic.alerts.arn]
  ok_actions               = [aws_sns_topic.alerts.arn]

  services = {
    web = {
      cpu    = 512
      memory = 1024

      # one task always on-demand, everything above it on spot
      capacity_provider_strategy = [
        { capacity_provider = "FARGATE", weight = 1, base = 1 },
        { capacity_provider = "FARGATE_SPOT", weight = 4, base = 0 },
      ]

      image           = "public.ecr.aws/nginx/nginx:latest"
      port            = 8080
      security_groups = [aws_security_group.service.id]

      load_balancers = [{
        target_group_arn = module.alb.target_group_arns["web"]
        container_name   = "web"
        container_port   = 8080
      }]

      autoscaling = {
        min_capacity = 2
        max_capacity = 20
        cpu_target   = 60

        # trim spend overnight
        scheduled = {
          night = { schedule = "cron(0 2 * * ? *)", min_capacity = 1, max_capacity = 4 }
          day   = { schedule = "cron(0 7 * * ? *)", min_capacity = 2, max_capacity = 20 }
        }
      }
    }
  }
}
```

### 2. Service Connect mesh (edge → api → worker)

One Cloud Map namespace shared by every service via `service_connect_namespace`.
`edge` is public (ALB); `api`/`worker` are internal and reachable only by their
Service Connect DNS aliases — no service talks to another by IP.

```hcl
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_service_discovery_private_dns_namespace" "mesh" {
  name = "mesh.internal"
  vpc  = data.aws_vpc.default.id
}

module "alb" {
  source  = "../../modules/lb"
  name    = "mesh-edge"
  vpc_id  = data.aws_vpc.default.id
  subnets = data.aws_subnets.default.ids

  security_group_ingress_rules = {
    http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
  }
  target_groups = {
    edge = {
      port         = 8080
      protocol     = "HTTP"
      target_type  = "ip"
      health_check = { path = "/", matcher = "200-399" }
    }
  }
  listeners = {
    http = {
      port           = 80
      default_action = { type = "forward", target_group_key = "edge" }
    }
  }
}

# shared task SG: intra-mesh traffic + ALB to edge
resource "aws_security_group" "tasks" {
  name_prefix = "mesh-tasks-"
  description = "mesh tasks"
  vpc_id      = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_vpc_security_group_ingress_rule" "mesh_self" {
  security_group_id            = aws_security_group.tasks.id
  from_port                    = 8080
  to_port                      = 9090
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.tasks.id
}

resource "aws_vpc_security_group_ingress_rule" "edge_from_alb" {
  security_group_id            = aws_security_group.tasks.id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
}

module "ecs" {
  source                     = "../../modules/ecs-orchestrator"
  cluster_name               = "mesh-demo"
  default_subnets            = data.aws_subnets.default.ids
  default_security_group_ids = [aws_security_group.tasks.id]
  service_connect_namespace  = aws_service_discovery_private_dns_namespace.mesh.arn

  services = {
    # public client of the mesh
    edge = {
      image = "public.ecr.aws/nginx/nginx:latest"
      port  = 8080
      load_balancers = [{
        target_group_arn = module.alb.target_group_arns["edge"]
        container_name   = "edge"
        container_port   = 8080
      }]
      service_connect = {
        services = [{
          port_name    = "edge"
          client_alias = { dns_name = "edge", port = 8080 }
        }]
      }
      autoscaling = { min_capacity = 2, max_capacity = 10, cpu_target = 60 }
    }

    api = {
      cpu    = 512
      memory = 1024
      containers = {
        api = {
          image         = "public.ecr.aws/nginx/nginx:latest"
          port_mappings = [{ container_port = 8080, name = "api" }]
          environment   = { WORKER_URL = "http://worker:9090" }
        }
      }
      service_connect = {
        services = [{
          port_name      = "api"
          discovery_name = "api"
          client_alias   = { dns_name = "api", port = 8080 }
        }]
      }
      autoscaling = { min_capacity = 2, max_capacity = 20, cpu_target = 65 }
    }

    worker = {
      cpu    = 512
      memory = 1024
      containers = {
        worker = {
          image         = "public.ecr.aws/nginx/nginx:latest"
          port_mappings = [{ container_port = 9090, name = "worker" }]
        }
      }
      service_connect = {
        services = [{
          port_name      = "worker"
          discovery_name = "worker"
          client_alias   = { dns_name = "worker", port = 9090 }
        }]
      }
      autoscaling = { min_capacity = 1, max_capacity = 10, cpu_target = 70 }
    }
  }
}
```

### 3. EC2 capacity provider (mixed with Fargate)

Build EC2 capacity with an ASG (the `asg`/`ec2`/launch-template modules), hand
the ASG ARN to this module to create + register the capacity provider, then split
a service across Fargate (baseline) and EC2 (scale-out).

```hcl
module "ecs" {
  source          = "../../modules/ecs-orchestrator"
  cluster_name    = "platform"
  default_subnets = var.private_subnet_ids

  ec2_capacity_providers = {
    ec2-od = { auto_scaling_group_arn = module.ecs_asg.autoscaling_group_arn }
  }

  services = {
    api = {
      cpu    = 512
      memory = 1024
      image  = "myapp:1"
      port   = 8080

      # task must declare EC2 to land on the provider
      requires_compatibilities = ["FARGATE", "EC2"]

      capacity_provider_strategy = [
        { capacity_provider = "FARGATE", weight = 1, base = 1 }, # baseline on Fargate
        { capacity_provider = "ec2-od", weight = 4, base = 0 },  # scale-out on EC2
      ]
    }
  }
}
```

### 4. Composed references (ALB + EFS + secrets, all by ARN/id)

Everything external is referenced, never created here: the target group comes
from the `lb` module, the file system from the `efs` module, the secret ARN
drives an auto-generated scoped read policy on the execution role.

```hcl
module "ecs" {
  source          = "../../modules/ecs-orchestrator"
  cluster_name    = "platform"
  default_subnets = var.private_subnet_ids

  services = {
    api = {
      cpu    = 512
      memory = 1024
      containers = {
        api = {
          image         = "myapp:1"
          port_mappings = [{ container_port = 8080, name = "http" }]
          environment   = { LOG_LEVEL = "info" }

          # scoped read policy auto-created from the ARN
          secrets = { DB_PASSWORD = aws_secretsmanager_secret.db.arn }

          mount_points = [{ source_volume = "shared", container_path = "/data" }]
        }
      }

      # target group from the lb module
      load_balancers = [{
        target_group_arn = module.alb.target_group_arns["api"]
        container_name   = "api"
        container_port   = 8080
      }]

      # EFS from the efs module
      volumes = {
        shared = {
          efs = {
            file_system_id  = module.efs.file_system_id
            access_point_id = module.efs.access_point_ids["api"]
          }
        }
      }

      autoscaling = { min_capacity = 2, max_capacity = 20, cpu_target = 60 }
    }
  }
}
```

### 5. EC2 launch type (plain hosts, no capacity provider)

The "I just want my own EC2 hosts" path. Container instances join the cluster
directly (the ECS-optimized AMI ships the agent; user-data sets `ECS_CLUSTER`),
and services are pinned with `launch_type = "EC2"` + `network_mode = "bridge"` —
no ASG, no capacity provider, no Fargate.

```hcl
data "aws_vpc" "default" { default = true }
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# the ECS-optimized AMI already has the agent baked in
data "aws_ssm_parameter" "ecs_ami" {
  name = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
}

locals {
  cluster_name = "platform-ec2"
  hosts        = { a = 0, b = 1 } # value = subnet index (spread across AZs)
}

# one shared SG for all hosts
resource "aws_security_group" "hosts" {
  name_prefix = "${local.cluster_name}-hosts-"
  description = "ECS container instances"
  vpc_id      = data.aws_vpc.default.id
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle { create_before_destroy = true }
}

# two container instances via the ec2 module; user-data joins the cluster
module "host" {
  source   = "../../modules/ec2"
  for_each = local.hosts

  name          = "${local.cluster_name}-${each.key}"
  ami           = nonsensitive(data.aws_ssm_parameter.ecs_ami.value)
  instance_type = "t3.medium"
  subnet_id     = element(data.aws_subnets.default.ids, each.value)

  vpc_security_group_ids      = [aws_security_group.hosts.id]
  associate_public_ip_address = true # default VPC has no NAT

  create_iam_instance_profile = true
  iam_role_policies = {
    ecs = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  # the only thing the host needs to join the cluster
  user_data = "#!/bin/bash\necho ECS_CLUSTER=${local.cluster_name} >> /etc/ecs/ecs.config\n"
}

module "ecs" {
  source       = "../../modules/ecs-orchestrator"
  cluster_name = local.cluster_name

  services = {
    # web server placed on the EC2 hosts
    web = {
      launch_type              = "EC2"
      requires_compatibilities = ["EC2"]
      network_mode             = "bridge"
      cpu                      = 256
      memory                   = 512
      image                    = "public.ecr.aws/nginx/nginx:latest"
      port                     = 8080
    }

    # background worker, also on EC2, no ports
    worker = {
      launch_type              = "EC2"
      requires_compatibilities = ["EC2"]
      network_mode             = "bridge"
      cpu                      = 256
      memory                   = 512
      image                    = "public.ecr.aws/docker/library/busybox:latest"
      command                  = ["sh", "-c", "while true; do echo working; sleep 30; done"]
    }
  }
}
```

> **EC2 vs. capacity provider.** Use `launch_type = "EC2"` (this example) when you
> manage the hosts yourself and want tasks placed on them directly. Use
> `ec2_capacity_providers` (example 3) when you want ECS to scale an ASG in/out
> with demand. They're mutually exclusive per service.

---

# Inputs

## Module-level inputs

### General

| Name           | Description                                                                                                  | Type          | Default | Required |
| -------------- | ------------------------------------------------------------------------------------------------------------ | ------------- | ------- | :------: |
| `cluster_name` | Name of the ECS cluster (also used to prefix services, roles, and log groups). 1–255 chars, `[a-zA-Z0-9-_]`. | `string`      | n/a     | **yes**  |
| `create`       | Master switch. When `false` the module creates nothing.                                                      | `bool`        | `true`  |    no    |
| `tags`         | Tags applied to all resources.                                                                               | `map(string)` | `{}`    |    no    |

### Cluster

| Name                            | Description                                                                                                                        | Type        | Default | Required |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------- | :------: |
| `enable_container_insights`     | Enable CloudWatch Container Insights. Off by default — it adds per-metric cost. Required for the `running_tasks_low` alarm.        | `bool`      | `false` |    no    |
| `service_connect_namespace`     | Default Cloud Map namespace ARN/id for Service Connect at the cluster level. Per-service `service_connect.namespace` overrides it. | `string`    | `null`  |    no    |
| `execute_command_configuration` | ECS Exec configuration — log shell sessions to CloudWatch/S3 with encryption for auditable access. See sub-fields below.           | `object(…)` | `null`  |    no    |

`execute_command_configuration` fields: `kms_key_id`, `logging` (`NONE`\|`DEFAULT`\|`OVERRIDE`, default `DEFAULT`), `log_configuration` = `{ cloud_watch_encryption_enabled, cloud_watch_log_group_name, s3_bucket_name, s3_key_prefix, s3_bucket_encryption_enabled }`.

### Capacity providers

| Name                                 | Description                                                                                                                                      | Type              | Default | Required |
| ------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------- | ------- | :------: |
| `enable_fargate_capacity_providers`  | Register `FARGATE` and `FARGATE_SPOT` on the cluster.                                                                                            | `bool`            | `true`  |    no    |
| `ec2_capacity_providers`             | Map of EC2 capacity providers to **create** from an ASG ARN and register. Key = provider name. The ASG is built elsewhere and referenced by ARN. | `map(object(…))`  | `{}`    |    no    |
| `external_capacity_providers`        | Names of **pre-existing** capacity providers to register on the cluster (e.g. EC2 providers built by another stack).                             | `list(string)`    | `[]`    |    no    |
| `default_capacity_provider_strategy` | Cluster-level default strategy for RunTask calls without an explicit one. Services normally set their own.                                       | `list(object(…))` | `[]`    |    no    |

`ec2_capacity_providers[*]` fields: `auto_scaling_group_arn` (required, must be an `arn:aws:autoscaling:` ARN), `managed_termination_protection` (default `DISABLED`), `managed_draining` (default `ENABLED`), `managed_scaling = { status=ENABLED, target_capacity=100, minimum_scaling_step_size, maximum_scaling_step_size, instance_warmup_period }`.

### IAM

| Name                           | Description                                                                                                                            | Type           | Default | Required |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------- | -------------- | ------- | :------: |
| `create_task_execution_role`   | Create a shared task execution role (ECR pull, log write, secret read). Ignored where a service supplies its own `execution_role_arn`. | `bool`         | `true`  |    no    |
| `task_execution_role_arn`      | ARN of an existing execution role for all services. Overrides `create_task_execution_role`.                                            | `string`       | `null`  |    no    |
| `task_execution_role_policies` | Extra managed policy ARNs to attach to the created execution role.                                                                     | `map(string)`  | `{}`    |    no    |
| `iam_permissions_boundary`     | Permissions boundary ARN applied to every IAM role this module creates.                                                                | `string`       | `null`  |    no    |
| `secrets_kms_key_arns`         | KMS key ARNs encrypting referenced secrets/parameters. Adds `kms:Decrypt` to the execution role so CMK-encrypted secrets can be read.  | `list(string)` | `[]`    |    no    |

### Networking defaults (overridable per service)

| Name                         | Description                                                                | Type           | Default | Required |
| ---------------------------- | -------------------------------------------------------------------------- | -------------- | ------- | :------: |
| `default_subnets`            | Default subnet IDs for `awsvpc` services that don't set their own.         | `list(string)` | `[]`    |    no    |
| `default_security_group_ids` | Default security group IDs for `awsvpc` services that don't set their own. | `list(string)` | `[]`    |    no    |
| `vpc_id`                     | VPC ID. Required only when a service sets `create_security_group = true`.  | `string`       | `null`  |    no    |

### Logging defaults

| Name                 | Description                                                                         | Type     | Default | Required |
| -------------------- | ----------------------------------------------------------------------------------- | -------- | ------- | :------: |
| `log_retention_days` | Default retention for created service log groups. Must be a valid CloudWatch value. | `number` | `30`    |    no    |
| `log_kms_key_id`     | KMS key ARN to encrypt created service log groups.                                  | `string` | `null`  |    no    |

### Monitoring / alarms

Off by default — alarms cost per alarm. `running_tasks_low` needs Container Insights; CPU/memory alarms work without it.

| Name                       | Description                                                                  | Type           | Default | Required |
| -------------------------- | ---------------------------------------------------------------------------- | -------------- | ------- | :------: |
| `create_cloudwatch_alarms` | Create per-service CPU, memory, and (with Insights) low-running-task alarms. | `bool`         | `false` |    no    |
| `alarm_cpu_threshold`      | `CPUUtilization` (%) threshold for the high-CPU alarm.                       | `number`       | `85`    |    no    |
| `alarm_memory_threshold`   | `MemoryUtilization` (%) threshold for the high-memory alarm.                 | `number`       | `85`    |    no    |
| `alarm_min_running_tasks`  | Alarm when `RunningTaskCount` drops below this (needs Insights).             | `number`       | `1`     |    no    |
| `alarm_evaluation_periods` | Evaluation periods for the service alarms.                                   | `number`       | `3`     |    no    |
| `alarm_period`             | Period (seconds) for the alarm statistics.                                   | `number`       | `60`    |    no    |
| `alarm_actions`            | ARNs notified on ALARM (e.g. an SNS topic).                                  | `list(string)` | `[]`    |    no    |
| `ok_actions`               | ARNs notified when an alarm returns to OK.                                   | `list(string)` | `[]`    |    no    |

---

# The `services` object

`services` is a `map(object(…))` keyed by service name — the flexible surface of
the module. Every field is `optional(...)` with the defaults shown. External
resources (target groups, EFS, secrets, namespaces, KMS) are **referenced by
ARN/id**, never created here.

### Task sizing & platform

| Field                      | Type           | Default       | Notes                                                                 |
| -------------------------- | -------------- | ------------- | --------------------------------------------------------------------- |
| `cpu`                      | `number`       | `256`         | Task CPU units. Fargate requires a valid cpu/memory pair (validated). |
| `memory`                   | `number`       | `512`         | Task memory (MiB).                                                    |
| `network_mode`             | `string`       | `"awsvpc"`    | `awsvpc` \| `bridge` \| `host` \| `none`.                             |
| `requires_compatibilities` | `list(string)` | `["FARGATE"]` | Add `"EC2"` to place on EC2 capacity / `launch_type = "EC2"`.         |
| `cpu_architecture`         | `string`       | `"X86_64"`    | `X86_64` \| `ARM64` (Graviton).                                       |
| `operating_system_family`  | `string`       | `"LINUX"`     | Runtime platform OS.                                                  |
| `ephemeral_storage_gib`    | `number`       | `null`        | Fargate scratch, 21–200 (validated).                                  |
| `pid_mode` / `ipc_mode`    | `string`       | `null`        | Task-level PID/IPC namespace.                                         |
| `task_tags`                | `map(string)`  | `{}`          | Tags on the task definition.                                          |

### Containers (`containers` map, keyed by container name)

| Field                                   | Type           | Default | Notes                                                                                                           |
| --------------------------------------- | -------------- | ------- | --------------------------------------------------------------------------------------------------------------- |
| `image`                                 | `string`       | —       | **Required.** Image URI.                                                                                        |
| `essential`                             | `bool`         | `true`  | At least one essential container required (validated).                                                          |
| `cpu` / `memory` / `memory_reservation` | `number`       | `null`  | Per-container reservations.                                                                                     |
| `command` / `entrypoint`                | `list(string)` | `null`  | Override image CMD/ENTRYPOINT.                                                                                  |
| `working_directory` / `user`            | `string`       | `null`  |                                                                                                                 |
| `privileged`                            | `bool`         | `null`  | EC2/bridge only.                                                                                                |
| `readonly_root_filesystem`              | `bool`         | `false` | Harden — flip to `true` where the app allows.                                                                   |
| `stop_timeout`                          | `number`       | `null`  | Seconds before SIGKILL.                                                                                         |
| `environment`                           | `map(string)`  | `{}`    | Plain env vars.                                                                                                 |
| `secrets`                               | `map(string)`  | `{}`    | `NAME => Secrets Manager / SSM ARN`. Drives the scoped exec-role read policy.                                   |
| `port_mappings`                         | `list(object)` | `[]`    | `{ container_port, host_port?, protocol="tcp", name?, app_protocol? }`. `name` is required for Service Connect. |
| `mount_points`                          | `list(object)` | `[]`    | `{ source_volume, container_path, read_only=false }`. `source_volume` must match a `volumes` key (validated).   |
| `depends_on`                            | `list(object)` | `[]`    | `{ container_name, condition }` (START/COMPLETE/SUCCESS/HEALTHY).                                               |
| `ulimits`                               | `list(object)` | `[]`    | `{ name, soft_limit, hard_limit }`.                                                                             |
| `health_check`                          | `object`       | `null`  | `{ command, interval?, timeout?, retries?, start_period? }`.                                                    |
| `linux_parameters`                      | `object`       | `null`  | `{ init_process_enabled?, shared_memory_size? }`.                                                               |
| `log_options`                           | `map(string)`  | `null`  | Override the default awslogs options.                                                                           |

### Single-container shortcut (used only when `containers` is empty)

`image`, `port`, `environment`, `secrets`, `command`, `health_check` (CMD-SHELL
arg list). Or `container_definitions_override` — a raw JSON escape hatch that
bypasses the builder entirely.

### Volumes & storage

`volumes` (map keyed by volume name): `host_path`, `configure_at_launch` (managed
EBS), `efs = { file_system_id (req), root_directory, transit_encryption="ENABLED",
transit_encryption_port, access_point_id, iam }`, `docker = { scope, autoprovision,
driver, driver_opts, labels }`.

`managed_ebs_volume` (one per service, attached at task launch): `name` (req, must
match a `configure_at_launch` volume — validated), `role_arn` (req, infra role with
EBS perms), `size_in_gb`, `volume_type="gp3"`, `iops`, `throughput`,
`encrypted=true`, `kms_key_id`, `snapshot_id`, `file_system_type`, `tags`.

### Capacity / launch type (mutually exclusive)

| Field                        | Type           | Default | Notes                                                                                |
| ---------------------------- | -------------- | ------- | ------------------------------------------------------------------------------------ |
| `capacity_provider_strategy` | `list(object)` | `[]`    | `{ capacity_provider, weight=1, base=0 }`. Mix Fargate + EC2 providers.              |
| `launch_type`                | `string`       | `null`  | `FARGATE` \| `EC2` \| `EXTERNAL` for standalone instances with no capacity provider. |

Set **one** of the two, not both (validated). With neither set, the service falls
back to the cluster default or plain Fargate, so it still runs standalone.

`placement_constraints` (`{ type, expression? }`) and `ordered_placement_strategy`
(`{ type, field? }`) tune EC2 placement.

### Service runtime & deployment

| Field                                                               | Type     | Default                                         |
| ------------------------------------------------------------------- | -------- | ----------------------------------------------- |
| `desired_count`                                                     | `number` | `1`                                             |
| `deployment_controller`                                             | `string` | `"ECS"`                                         |
| `deployment_minimum_healthy_percent` / `deployment_maximum_percent` | `number` | `100` / `200`                                   |
| `enable_circuit_breaker` / `enable_rollback`                        | `bool`   | `true` / `true`                                 |
| `enable_execute_command`                                            | `bool`   | `false` (adds `ssmmessages:*` to the task role) |
| `force_new_deployment` / `wait_for_steady_state`                    | `bool`   | `false` / `false`                               |
| `health_check_grace_period_seconds`                                 | `number` | `null`                                          |
| `propagate_tags`                                                    | `string` | `"SERVICE"`                                     |

### Networking (awsvpc)

`subnets`, `security_groups`, `create_security_group` (default `false`; needs
`vpc_id`), `assign_public_ip` (default `false` — secure default).

### Integrations

- **`load_balancers`** — `[{ target_group_arn, container_name, container_port }]`. `container_name` must match a defined container (validated).
- **`service_connect`** — `{ enabled=true, namespace?, services=[{ port_name, discovery_name?, client_alias={ dns_name, port } }] }`. Needs a namespace from the service or the cluster default (validated).
- **`service_discovery`** — `{ namespace_id (req), name?, dns_record_type="A", dns_ttl=10, routing_policy="MULTIVALUE" }` (creates a Cloud Map service).

### Logging

`create_log_group` (default `true`), `log_group_name` (reference an existing
group instead), `log_retention_days` (per-service override).

### IAM

`execution_role_arn` (override shared exec role), `task_role_arn` (BYO),
`create_task_role` (default `true`), `task_role_policies` (`map` of managed ARNs),
`task_role_inline_policy` (JSON).

### Autoscaling

`autoscaling = { min_capacity (req), max_capacity (req), cpu_target?,
memory_target?, alb_request_target?, alb_resource_label?, scale_in_cooldown=300,
scale_out_cooldown=60, scheduled = map({ schedule, min_capacity, max_capacity,
timezone? }) }`. Services with autoscaling get `ignore_changes = [desired_count]`.

### `tags`

Per-service tags merged over the module `tags`.

---

# Validations (fail-fast guardrails)

The `services` variable enforces these at plan time, so misconfigurations fail
before any API call:

- every service defines containers (`containers`, `image`, or `container_definitions_override`);
- Fargate services use a **valid cpu/memory combination** (AWS Fargate task size table);
- `network_mode` ∈ {awsvpc, bridge, host, none};
- `awsvpc` services have subnets (per-service or `default_subnets`);
- each `load_balancers[*].container_name` matches a defined container;
- each `mount_points[*].source_volume` matches a `volumes` key;
- `managed_ebs_volume.name` matches a `configure_at_launch` volume;
- at least one **essential** container per service;
- `ephemeral_storage_gib` ∈ [21, 200];
- non-Fargate capacity providers require `"EC2"` in `requires_compatibilities`;
- `launch_type` ∈ {FARGATE, EC2, EXTERNAL} and is XOR with `capacity_provider_strategy`;
- `launch_type = "EC2"` requires `"EC2"` compatibility;
- `service_connect` requires a namespace (service-level or cluster default);
- module-level: `cluster_name` format, `log_retention_days` value, `ec2_capacity_providers[*]` ASG ARN format, `execute_command_configuration.logging` enum.

---

# Outputs

| Name                          | Description                                                                        |
| ----------------------------- | ---------------------------------------------------------------------------------- |
| `cluster_id`                  | ECS cluster ID.                                                                    |
| `cluster_arn`                 | ECS cluster ARN.                                                                   |
| `cluster_name`                | ECS cluster name.                                                                  |
| `capacity_providers`          | Capacity providers registered on the cluster.                                      |
| `ec2_capacity_provider_names` | Names of the EC2 capacity providers created by this module.                        |
| `service_names`               | Map: service key → ECS service name.                                               |
| `service_arns`                | Map: service key → ECS service ARN (id).                                           |
| `task_definition_arns`        | Map: service key → task definition ARN.                                            |
| `service_security_group_ids`  | Map: service key → SG id (only services with `create_security_group`).             |
| `task_execution_role_arn`     | ARN of the shared execution role (`null` when external/none).                      |
| `task_role_arns`              | Map: service key → task role ARN (created or provided).                            |
| `log_group_names`             | Map: service key → CloudWatch log group name.                                      |
| `service_discovery_arns`      | Map: service key → Cloud Map service ARN (only services with `service_discovery`). |
| `autoscaling_target_ids`      | Map: service key → Application Auto Scaling target resource id.                    |
| `cloudwatch_alarm_names`      | Names of the per-service alarms created (empty when disabled).                     |

---

# Testing

Two offline suites — fully mocked, no AWS credentials, no billable resources:

```bash
cd modules/ecs-orchestrator
terraform init -backend=false
terraform validate
terraform test
terraform test -filter=tests/ecs.tftest.hcl
terraform test -filter=tests/apply.tftest.hcl
```

- **`tests/ecs.tftest.hcl`** — plan-level `run` blocks covering every launch path
  (Fargate, Fargate defaults, EC2 capacity provider, mixed, `launch_type = EC2`),
  multi-container task definitions, the scoped secrets policy, autoscaling,
  Service Connect, service discovery, the CloudWatch alarms (with and without
  Insights), per-service security groups, the default-Fargate fallback, the ECS
  Exec task-role policy, and `create = false`. Each guardrail has a paired
  `expect_failures` run (invalid cpu/memory, bad network mode, bad ASG ARN,
  invalid cluster name / retention, missing essential container, out-of-range
  ephemeral storage, EC2 provider without EC2 compat, Service Connect without a
  namespace, `launch_type` + strategy together, …).
- **`tests/apply.tftest.hcl`** — `command = apply` against a mocked provider:
  `full_stack_apply` (mixed launch, ALB, secrets, managed SG, discovery,
  autoscaling + scheduled) and `minimal_apply` (BYO execution role).

> **Scope of the mocks.** These suites prove schema, wiring, plan logic, and the
> container-definitions JSON _by construction_. They do **not** call the real ECS
> `RegisterTaskDefinition`/`CreateService` APIs — a live `terraform apply` against
> a sandbox account is the final gate before relying on it in production.
