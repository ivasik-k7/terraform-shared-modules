# ============================================================================
# Fargate showcase - the major configurations of ecs-orchestrator in one file.
#
# Three services, three shapes:
#   web    - public nginx image, multi-container (app + OTEL sidecar), behind
#            the ALB as the catch-all app, safe deploys (circuit breaker +
#            auto-rollback on ALB 5xx), CPU + request-rate autoscaling
#   api    - image from a module-created ECR repo, single-container shortcut,
#            ARM64 (Graviton), routed by ALB path rule + Service Connect for
#            east-west, memory-target autoscaling
#   worker - headless queue consumer on 100% FARGATE_SPOT, SQS-depth
#            autoscaling + scheduled scale-down, EFS volume, ECS Exec
#
# The ALB is set up production-style for MANY applications: local.apps is the
# single registry - target group, routing rule, and SG port are all derived
# from it. Onboarding app #4..#10 is one entry there + one service below.
#
# Everything is Fargate; the commented "asg-group" blocks at the bottom of the
# ECS section show the exact migration path to EC2 capacity when needed.
#
# Uses the default VPC so it applies in a sandbox with zero prerequisites.
# In a real VPC: private subnets + NAT, drop assign_public_ip everywhere.
# ============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.50.0, < 6.0.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

locals {
  cluster_name = "platform-fargate"

  tags = {
    Project     = "platform-demo"
    Environment = "prod"
    ManagedBy   = "Terraform"
  }

  # --------------------------------------------------------------------------
  # THE APP REGISTRY - one ALB for all of them.
  #
  # Each entry produces: a target group, a routing rule (path and/or host),
  # and the ALB->task port opening. priority 0 = the catch-all app served by
  # the listener's default action (exactly one entry should have it).
  #
  # Scaling this to 10 apps is 10 entries; priorities just need to be unique
  # (leave gaps - 20, 30, 40 - so inserting app #11 never renumbers the rest).
  # --------------------------------------------------------------------------
  apps = {
    web = {
      port          = 80
      health_path   = "/"
      priority      = 0 # catch-all: listener default action
      path_patterns = []
      host_headers  = []
    }
    api = {
      port          = 80
      health_path   = "/"
      priority      = 20
      path_patterns = ["/api", "/api/*"]
      host_headers  = [] # or route by host instead: ["api.example.com"]
    }
    # reports = {
    #   port          = 8080
    #   health_path   = "/healthz"
    #   priority      = 30
    #   path_patterns = ["/reports", "/reports/*"]
    #   host_headers  = []
    # }
    # checkout = {
    #   port          = 3000
    #   health_path   = "/health"
    #   priority      = 40
    #   path_patterns = []
    #   host_headers  = ["checkout.example.com"] # host-based routing
    # }
  }

  # the entry marked as catch-all (priority 0) gets the default action
  default_app = one([for k, a in local.apps : k if a.priority == 0])
}

# ============================================================================
# ECR - repo per service, created here, referenced by the services below.
# Immutable tags + scan-on-push are the production defaults; force_delete
# keeps the sandbox disposable (drop it in production).
# ============================================================================

module "ecr" {
  source   = "../../modules/ecr"
  for_each = toset(["api", "worker"])

  repository_name      = "${local.cluster_name}/${each.key}"
  image_tag_mutability = "IMMUTABLE"
  scan_on_push         = true
  force_delete         = true

  tags = local.tags
}

# ============================================================================
# ALB - one load balancer, production posture, N applications.
# Target groups and routing rules are derived from local.apps.
# ============================================================================

module "alb" {
  source = "../../modules/lb"

  name    = "${local.cluster_name}-alb"
  vpc_id  = data.aws_vpc.default.id
  subnets = data.aws_subnets.default.ids

  # production posture
  drop_invalid_header_fields = true
  idle_timeout               = 60
  # enable_deletion_protection = true                      # on in production
  # access_logs = { bucket = "my-alb-access-logs", prefix = local.cluster_name }

  security_group_ingress_rules = {
    http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
    # https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }

  # one target group per app, straight from the registry.
  # target_type = "ip" is required for Fargate (awsvpc) tasks.
  target_groups = {
    for k, a in local.apps : k => {
      port        = a.port
      protocol    = "HTTP"
      target_type = "ip"
      health_check = {
        path                = a.health_path
        matcher             = "200-399"
        interval            = 15
        healthy_threshold   = 2
        unhealthy_threshold = 3
      }
      deregistration_delay = 30
    }
  }

  # Sandbox: single HTTP listener, catch-all app as the default action.
  # Production: uncomment the HTTPS listener (ACM cert), and flip the HTTP
  # default_action to the redirect - all app rules then live on "https".
  listeners = {
    http = {
      port           = 80
      default_action = { type = "forward", target_group_key = local.default_app }
      # default_action = { type = "redirect", redirect = { status_code = "HTTP_301", port = "443", protocol = "HTTPS" } }
    }
    # https = {
    #   port            = 443
    #   protocol        = "HTTPS"
    #   certificate_arn = "arn:aws:acm:us-east-1:111122223333:certificate/..."
    #   ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    #   # unknown host/path -> 404, never accidentally another team's app
    #   default_action = {
    #     type           = "fixed-response"
    #     fixed_response = { content_type = "text/plain", message_body = "not found", status_code = "404" }
    #   }
    # }
  }

  # one routing rule per non-catch-all app: path-based, host-based, or both
  listener_rules = {
    for k, a in local.apps : k => {
      listener_key = "http" # "https" in production
      priority     = a.priority
      actions      = [{ type = "forward", target_group_key = k }]
      conditions = concat(
        length(a.path_patterns) > 0 ? [{ path_patterns = a.path_patterns }] : [],
        length(a.host_headers) > 0 ? [{ host_headers = a.host_headers }] : [],
      )
    } if a.priority > 0
  }

  # the ALB watches itself: 5xx / slow responses / unhealthy hosts -> SNS
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.ops.arn]

  tags = local.tags
}

# shared SG for tasks; the ALB may reach every app port from the registry
resource "aws_security_group" "task" {
  name_prefix = "${local.cluster_name}-task-"
  description = "fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle { create_before_destroy = true }

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "from_alb" {
  for_each = toset(distinct([for a in local.apps : tostring(a.port)]))

  security_group_id            = aws_security_group.task.id
  from_port                    = tonumber(each.value)
  to_port                      = tonumber(each.value)
  ip_protocol                  = "tcp"
  referenced_security_group_id = module.alb.security_group_id
  description                  = "app traffic from the ALB (port ${each.value})"
}

# Per-app deployment guards, one per registry entry: ECS watches the app's OWN
# target group 5xx during rollouts and auto-rolls-back a release that starts
# broken (the circuit breaker only catches tasks that fail to START). Scoped
# per target group on purpose - with 10 apps on one ALB, an ALB-wide alarm
# would let app #7's bad day roll back web's perfectly good deploy.
# (ALB-wide ops alerting comes from the lb module's create_cloudwatch_alarms.)
resource "aws_cloudwatch_metric_alarm" "app_5xx" {
  for_each = local.apps

  alarm_name          = "${local.cluster_name}-${each.key}-target-5xx"
  alarm_description   = "Elevated 5xx from ${each.key} targets - bad deploy or unhealthy backend."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 10
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    LoadBalancer = module.alb.arn_suffix
    TargetGroup  = module.alb.target_group_arn_suffixes[each.key]
  }
  alarm_actions = [aws_sns_topic.ops.arn]
  tags          = local.tags
}

# ============================================================================
# SUPPORTING RESOURCES the services reference (the orchestrator never creates
# external things - target groups, queues, secrets, namespaces come by ARN/id)
# ============================================================================

resource "aws_sns_topic" "ops" {
  name = "${local.cluster_name}-ops"
  tags = local.tags
}

# secrets from BOTH sources on purpose - Secrets Manager and SSM; the module
# wires them into containers and scopes the execution role to exactly these
resource "aws_secretsmanager_secret" "db_password" {
  name_prefix             = "${local.cluster_name}/db-password-"
  recovery_window_in_days = 0
  tags                    = local.tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = "change-me-demo-only"
}

resource "aws_ssm_parameter" "api_key" {
  name  = "/${local.cluster_name}/api-key"
  type  = "SecureString"
  value = "demo-api-key"
  tags  = local.tags
}

# Service Connect namespace: stable east-west DNS (api.<cluster>.internal)
# without a load balancer hop
resource "aws_service_discovery_http_namespace" "internal" {
  name        = "${local.cluster_name}.internal"
  description = "Service Connect namespace for ${local.cluster_name}"
  tags        = local.tags
}

resource "aws_sqs_queue" "jobs" {
  name                       = "${local.cluster_name}-jobs"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
  sqs_managed_sse_enabled    = true
  tags                       = local.tags
}

# EFS is the persistent-volume story on Fargate
resource "aws_efs_file_system" "shared" {
  encrypted = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-shared" })
}

resource "aws_security_group" "efs" {
  name_prefix = "${local.cluster_name}-efs-"
  description = "NFS from fargate tasks"
  vpc_id      = data.aws_vpc.default.id

  lifecycle { create_before_destroy = true }

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_tasks" {
  security_group_id            = aws_security_group.efs.id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.task.id
  description                  = "NFS from the shared task SG"
}

resource "aws_efs_mount_target" "shared" {
  for_each = toset(data.aws_subnets.default.ids)

  file_system_id  = aws_efs_file_system.shared.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

resource "aws_efs_access_point" "worker" {
  file_system_id = aws_efs_file_system.shared.id

  posix_user {
    uid = 1000
    gid = 1000
  }

  root_directory {
    path = "/worker"
    creation_info {
      owner_uid   = 1000
      owner_gid   = 1000
      permissions = "0755"
    }
  }

  tags = local.tags
}

# shell access to containers is powerful; log every ECS Exec session
resource "aws_cloudwatch_log_group" "exec" {
  name              = "/ecs/${local.cluster_name}/exec-audit"
  retention_in_days = 90
  tags              = local.tags
}

# ============================================================================
# ECS - the cluster + three service shapes, all Fargate.
#
# At real 10-app scale, don't grow this one call forever: keep the shared
# cluster + ALB in one workspace and split the services across per-team
# module instances (same module, services = { ... } each) so plans stay fast
# and a team's change can't touch another team's state.
# ============================================================================

module "ecs" {
  source = "../../modules/ecs-orchestrator"

  cluster_name = local.cluster_name

  # ---- cluster ---------------------------------------------------------------
  enable_container_insights = true # also unlocks the low-running-tasks alarm
  service_connect_namespace = aws_service_discovery_http_namespace.internal.arn

  execute_command_configuration = {
    logging = "OVERRIDE"
    log_configuration = {
      cloud_watch_log_group_name     = aws_cloudwatch_log_group.exec.name
      cloud_watch_encryption_enabled = false
    }
  }

  # FARGATE / FARGATE_SPOT are registered by default. Services without their
  # own strategy (api below) inherit this cluster default: all Spot.
  default_capacity_provider_strategy = [
    { capacity_provider = "FARGATE_SPOT", weight = 1 },
  ]

  # ---- moving to EC2 capacity later (asg-group) ------------------------------
  # 1) stand up the node group:
  #
  # module "capacity" {
  #   source = "../../modules/asg-group"
  #
  #   name              = "${local.cluster_name}-ec2"
  #   vpc_id            = data.aws_vpc.default.id
  #   subnet_ids        = data.aws_subnets.default.ids
  #   instance_type     = "m6i.large"
  #   ami_ssm_parameter = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  #   user_data         = "#!/bin/bash\necho ECS_CLUSTER=${local.cluster_name} >> /etc/ecs/ecs.config"
  #
  #   min_size              = 0     # managed scaling drives capacity from here
  #   max_size              = 10
  #   protect_from_scale_in = true  # required for managed termination protection
  # }
  #
  # 2) register it as a capacity provider on this cluster:
  #
  # ec2_capacity_providers = {
  #   ec2-general = {
  #     auto_scaling_group_arn         = module.capacity.autoscaling_group_arn
  #     managed_termination_protection = "ENABLED"
  #     managed_scaling                = { target_capacity = 100 }
  #   }
  # }
  #
  # 3) per service, switch the strategy (see the note inside `web` below).

  # ---- shared IAM ------------------------------------------------------------
  task_execution_role_policies = {
    ecr_read = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  }
  # iam_permissions_boundary = "arn:aws:iam::111122223333:policy/team-boundary"
  # secrets_kms_key_arns     = [aws_kms_key.secrets.arn]  # when secrets use a CMK

  # ---- networking / logging defaults (overridable per service) ----------------
  vpc_id                     = data.aws_vpc.default.id # needed by api's create_security_group
  default_subnets            = data.aws_subnets.default.ids
  default_security_group_ids = [aws_security_group.task.id]
  log_retention_days         = 30

  # ---- monitoring: CPU / memory / running-tasks alarms per service ------------
  create_cloudwatch_alarms = true
  alarm_cpu_threshold      = 85
  alarm_memory_threshold   = 85
  alarm_min_running_tasks  = 1
  alarm_actions            = [aws_sns_topic.ops.arn]
  ok_actions               = [aws_sns_topic.ops.arn]

  # ===========================================================================
  # SERVICES
  # ===========================================================================
  services = {

    # ---- web: the full-dress front door (public nginx image) -----------------
    web = {
      cpu                   = 1024
      memory                = 2048
      ephemeral_storage_gib = 30 # Fargate scratch above the 20 GiB default

      containers = {
        web = {
          image     = "public.ecr.aws/nginx/nginx:1.27"
          essential = true

          port_mappings = [{ container_port = 80, name = "http" }]

          environment = {
            APP_ENV       = "prod"
            OTEL_ENDPOINT = "http://localhost:4317"
          }

          # name => ARN; the execution role is granted read on exactly these
          secrets = {
            DB_PASSWORD = aws_secretsmanager_secret.db_password.arn
            API_KEY     = aws_ssm_parameter.api_key.arn
          }

          # official nginx images ship curl since 1.25; slim/alpine variants
          # may not - verify before swapping the image or the task will cycle
          health_check = {
            command      = ["CMD-SHELL", "curl -sf http://localhost/ || exit 1"]
            interval     = 15
            timeout      = 5
            retries      = 3
            start_period = 30
          }

          # app waits for the telemetry pipe to exist
          depends_on = [{ container_name = "otel", condition = "START" }]
        }

        otel = {
          image     = "public.ecr.aws/aws-observability/aws-otel-collector:latest"
          essential = false # sidecar death should not kill the task
          cpu       = 128
          memory    = 256
          command   = ["--config=/etc/ecs/ecs-default-config.yaml"]
        }
      }

      # capacity: guaranteed on-demand floor, Spot for the burst.
      #
      # Moving THIS service to the EC2 capacity provider (asg-group) is:
      #   requires_compatibilities = ["EC2"]
      #   capacity_provider_strategy = [
      #     { capacity_provider = "ec2-general", weight = 1 },
      #   ]
      capacity_provider_strategy = [
        { capacity_provider = "FARGATE", weight = 1, base = 2 },
        { capacity_provider = "FARGATE_SPOT", weight = 3 },
      ]

      # default VPC has no NAT; public IP lets Fargate pull images.
      assign_public_ip = true

      load_balancers = [{
        target_group_arn = module.alb.target_group_arns["web"]
        container_name   = "web"
        container_port   = 80
      }]
      health_check_grace_period_seconds = 60

      # safe deploys, two layers: circuit breaker (tasks that fail to START
      # roll back) + deployment alarm on THIS app's target group (tasks that
      # start but 5xx roll back - other apps' errors can't trigger it)
      enable_circuit_breaker = true
      enable_rollback        = true
      deployment_alarms = {
        alarm_names = [aws_cloudwatch_metric_alarm.app_5xx["web"].alarm_name]
        rollback    = true
      }
      deployment_minimum_healthy_percent = 100
      deployment_maximum_percent         = 200

      # the OTEL collector ships traces/metrics with the task role
      task_role_policies = {
        xray = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
        cw   = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
      }

      # scale on whichever pressure arrives first: CPU or request rate
      autoscaling = {
        min_capacity       = 2
        max_capacity       = 20
        cpu_target         = 60
        alb_request_target = 500 # requests/task/minute
        alb_resource_label = "${module.alb.arn_suffix}/${module.alb.target_group_arn_suffixes["web"]}"
        scale_in_cooldown  = 300
        scale_out_cooldown = 60
      }

      tags = local.tags
    }

    # ---- api: the lean internal service (image from the ECR repo above) ------
    # Single-container shortcut, Graviton, routed at /api/* by the ALB rule and
    # reachable east-west as api.<cluster>.internal via Service Connect.
    # No capacity strategy set -> inherits the cluster default (all Spot).
    #
    # NOTE: the repo starts empty. Either push an image before the first apply:
    #   aws ecr get-login-password | docker login --username AWS --password-stdin <repo-url>
    #   docker build -t <repo-url>:v1 . && docker push <repo-url>:v1
    # or bootstrap with desired_count = 0, push, then raise it - otherwise the
    # service is created but tasks can't pull and /api/* serves 503 until the push.
    api = {
      cpu              = 512
      memory           = 1024
      cpu_architecture = "ARM64"

      image = "${module.ecr["api"].repository_url}:v1"
      port  = 80
      environment = {
        APP_ENV = "prod"
      }

      # same per-app deployment guard as web - derived from the same registry
      deployment_alarms = {
        alarm_names = [aws_cloudwatch_metric_alarm.app_5xx["api"].alarm_name]
        rollback    = true
      }

      load_balancers = [{
        target_group_arn = module.alb.target_group_arns["api"]
        container_name   = "api"
        container_port   = 80
      }]
      health_check_grace_period_seconds = 30

      # module creates an egress-only SG for this service (vpc_id above);
      # ingress is added out of band below via the module's SG output
      create_security_group = true
      assign_public_ip      = true

      # the shortcut names its port mapping after the service key ("api")
      service_connect = {
        services = [{
          port_name = "api"
          client_alias = {
            dns_name = "api.${local.cluster_name}.internal"
            port     = 80
          }
        }]
      }

      autoscaling = {
        min_capacity  = 2
        max_capacity  = 10
        memory_target = 70
      }

      tags = local.tags
    }

    # ---- worker: the headless queue consumer ----------------------------------
    # No ports, no LB. 100% Spot (interruptions are fine - the queue redelivers),
    # scales on queue depth, sleeps outside business hours, persists to EFS,
    # debuggable via audited ECS Exec.
    worker = {
      cpu    = 512
      memory = 1024

      containers = {
        worker = {
          # swap for "${module.ecr["worker"].repository_url}:v1" once pushed
          image     = "public.ecr.aws/docker/library/busybox:stable"
          essential = true
          command   = ["sh", "-c", "while true; do echo processing >> /data/log; sleep 30; done"]

          environment = {
            QUEUE_URL = aws_sqs_queue.jobs.url
          }

          # only /data (EFS) is writable - everything else is immutable
          readonly_root_filesystem = true
          mount_points = [{
            source_volume  = "shared"
            container_path = "/data"
          }]

          # SIGTERM -> finish the in-flight message before SIGKILL
          stop_timeout = 120
        }
      }

      volumes = {
        shared = {
          efs = {
            file_system_id     = aws_efs_file_system.shared.id
            access_point_id    = aws_efs_access_point.worker.id
            transit_encryption = "ENABLED"
            iam                = "ENABLED" # mount authorized by the task role
          }
        }
      }

      capacity_provider_strategy = [
        { capacity_provider = "FARGATE_SPOT", weight = 1 },
      ]
      assign_public_ip = true

      # Spot-friendly rollouts: replace all at once, nothing to keep healthy
      deployment_minimum_healthy_percent = 0
      deployment_maximum_percent         = 100

      # `aws ecs execute-command` into a live task; sessions land in the
      # audit log group configured on the cluster
      enable_execute_command = true

      # least privilege, inline: consume the queue + mount the EFS via IAM
      task_role_inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid      = "ConsumeJobs"
            Effect   = "Allow"
            Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
            Resource = aws_sqs_queue.jobs.arn
          },
          {
            Sid      = "MountSharedEfs"
            Effect   = "Allow"
            Action   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
            Resource = aws_efs_file_system.shared.arn
            Condition = {
              StringEquals = { "elasticfilesystem:AccessPointArn" = aws_efs_access_point.worker.arn }
            }
          },
        ]
      })

      # scale on backlog: target 100 visible messages per task...
      autoscaling = {
        min_capacity = 1
        max_capacity = 30
        custom_metric = {
          namespace    = "AWS/SQS"
          metric_name  = "ApproximateNumberOfMessagesVisible"
          statistic    = "Average"
          dimensions   = { QueueName = aws_sqs_queue.jobs.name }
          target_value = 100
        }
        # ...and keep a bigger floor during business hours
        scheduled = {
          business_hours = {
            schedule     = "cron(0 7 ? * MON-FRI *)"
            timezone     = "Europe/Kyiv"
            min_capacity = 4
            max_capacity = 30
          }
          nights_weekends = {
            schedule     = "cron(0 20 ? * * *)"
            timezone     = "Europe/Kyiv"
            min_capacity = 1
            max_capacity = 10
          }
        }
      }

      tags = local.tags
    }
  }

  tags = local.tags
}

# ingress to the module-created api SG: only web tasks, only the app port
resource "aws_vpc_security_group_ingress_rule" "api_from_web" {
  security_group_id            = module.ecs.service_security_group_ids["api"]
  from_port                    = 80
  to_port                      = 80
  ip_protocol                  = "tcp"
  referenced_security_group_id = aws_security_group.task.id
  description                  = "api traffic from web tasks (Service Connect)"
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "alb_dns_name" {
  description = "Public entry point - / is web, /api/* is api."
  value       = module.alb.dns_name
}

output "ecr_repository_urls" {
  description = "Push application images here (repo per service)."
  value       = { for k, m in module.ecr : k => m.repository_url }
}

output "cluster_name" {
  value = module.ecs.cluster_name
}

output "service_names" {
  value = module.ecs.service_names
}

output "api_internal_dns" {
  description = "How web reaches api inside the cluster (Service Connect alias)."
  value       = "api.${local.cluster_name}.internal"
}

output "jobs_queue_url" {
  description = "Feed this queue to watch the worker scale on backlog."
  value       = aws_sqs_queue.jobs.url
}

output "exec_into_worker" {
  description = "Audited shell into a live worker task."
  value       = "aws ecs execute-command --cluster ${module.ecs.cluster_name} --task <task-id> --container worker --interactive --command /bin/sh"
}

output "alarm_names" {
  description = "Per-service CPU/memory/running-tasks alarms wired to the ops topic."
  value       = module.ecs.cloudwatch_alarm_names
}
