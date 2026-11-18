# Every input, in the shape of a migrated on-premises application: an API
# behind an ALB that scales on requests and releases as a canary, a queue
# worker on Spot, a nightly batch job, a schema migration run from the
# pipeline, a stateful service on a managed EBS volume, a document renderer on
# Managed Instances, and a log shipper on EC2 capacity.

terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 6.57.1, < 7.0.0" }
  }
}

provider "aws" {
  region = "eu-west-2"
}

locals {
  account = "111122223333"
  region  = "eu-west-2"
  ecr     = "${local.account}.dkr.ecr.${local.region}.amazonaws.com"
  key     = "arn:aws:kms:${local.region}:${local.account}:key/11111111-2222-3333-4444-555555555555"
  db_url  = "arn:aws:secretsmanager:${local.region}:${local.account}:secret:orders/db-AbCdEf"
}

variable "private_subnet_ids" {
  description = "Private subnets in three AZs."
  type        = list(string)
  default     = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002", "subnet-0a1b2c3d4e5f60003"]
}

variable "task_security_group_id" {
  description = "Security group for the tasks."
  type        = string
  default     = "sg-0a1b2c3d4e5f60001"
}

variable "api_target_group_arn" {
  description = "Target group of the API's ALB listener."
  type        = string
  default     = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/orders-api/0123456789abcdef"
}

variable "api_alternate_target_group_arn" {
  description = "Second target group of the API, which ECS starts each new revision behind."
  type        = string
  default     = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/orders-api-next/0123456789abcdef"
}

variable "api_listener_rule_arns" {
  description = "The ALB listener rules ECS moves between the API's target groups: production, and the test rule that matches X-Release-Test."
  type        = object({ production = string, test = string })
  default = {
    production = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/orders/0123456789abcdef/0123456789abcdef/0123456789abcdef"
    test       = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/orders/0123456789abcdef/0123456789abcdef/fedcba9876543210"
  }
}

variable "log_shipper_asg_arn" {
  description = "Auto Scaling group of the EC2 container instances."
  type        = string
  default     = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:11111111-2222-3333-4444-555555555555:autoScalingGroupName/orders-ecs"
}

module "ecs" {
  source = "../.."

  create             = true
  name               = "orders-prod"
  subnet_ids         = var.private_subnet_ids
  security_group_ids = [var.task_security_group_id]
  allow_public_ip    = false

  tags              = { CostCenter = "cc-1042", Environment = "prod", Owner = "orders-team", Application = "orders" }
  required_tag_keys = ["CostCenter", "Environment", "Owner"]

  container_insights                    = "enhanced"
  fargate_ephemeral_storage_kms_key_arn = local.key
  managed_storage_kms_key_arn           = local.key
  service_connect_namespace_arn         = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-abcdef0123456789"
  execute_command = {
    kms_key_arn    = local.key
    logging        = "OVERRIDE"
    log_group_name = "/ecs/orders-prod/exec-sessions"
  }

  default_capacity = "on_demand"
  ec2_capacity_providers = {
    shippers = {
      auto_scaling_group_arn         = var.log_shipper_asg_arn
      managed_termination_protection = "DISABLED"
      managed_draining               = "ENABLED"
      managed_scaling                = { target_capacity = 90, maximum_scaling_step_size = 4 }
    }
  }

  # Compute-optimized instances for the renderer, chosen and patched by AWS.
  managed_instances_capacity_providers = {
    compute = {
      storage_size_gib = 60
      instance_requirements = {
        vcpu_min                                         = 2
        vcpu_max                                         = 16
        memory_mib_min                                   = 4096
        cpu_manufacturers                                = ["amazon-web-services"]
        allowed_instance_types                           = ["c7g.*", "c8g.*"]
        burstable_performance                            = "excluded"
        on_demand_max_price_percentage_over_lowest_price = 20
      }
    }
  }

  # GPU instances the platform team runs in its own Auto Scaling group.
  external_capacity_providers = ["platform-gpu"]

  log_retention_days = 90
  log_kms_key_arn    = local.key
  log_skip_destroy   = true

  global_environment   = { APP_ENV = "prod", AWS_REGION = local.region }
  global_secrets       = { DATABASE_URL = "${local.db_url}:url::" }
  secrets_kms_key_arns = [local.key]

  permissions_boundary_arn     = "arn:aws:iam::111122223333:policy/workload-boundary"
  infrastructure_role          = { create = true }
  task_definition_skip_destroy = true

  sns_topic_arn         = "arn:aws:sns:eu-west-2:111122223333:orders-alerts"
  sns_topic_kms_key_arn = local.key
  create_alarms         = true
  create_event_rules    = true
  alarm_cpu_percent     = 80
  alarm_memory_percent  = 85
  # The topic, and the on-call integration directly.
  alarm_actions            = ["arn:aws:sns:eu-west-2:111122223333:orders-alerts", "arn:aws:lambda:eu-west-2:111122223333:function:opsgenie-forwarder"]
  ok_actions               = ["arn:aws:sns:eu-west-2:111122223333:orders-alerts"]
  alarm_period             = 60
  alarm_evaluation_periods = 3
  trusted_s3_account_ids   = ["111122223333"]

  services = {
    # The web tier: two to twenty tasks, scaled on ALB requests and CPU.
    api = {
      cpu    = 1024
      memory = 2048
      containers = {
        app = {
          image                    = "${local.ecr}/orders-api:1.4.2"
          port_mappings            = [{ container_port = 8080, name = "http", app_protocol = "http" }]
          environment              = { LOG_FORMAT = "json" }
          secrets                  = { STRIPE_KEY = "arn:aws:ssm:eu-west-2:111122223333:parameter/orders/stripe-key" }
          health_check             = { command = ["CMD-SHELL", "curl -fs http://localhost:8080/health || exit 1"], start_period = 30 }
          readonly_root_filesystem = true
          mount_points             = [{ source_volume = "uploads", container_path = "/srv/uploads" }]
          depends_on               = { migrations-check = "SUCCESS" }
          ulimits                  = { nofile = { soft = 65536, hard = 65536 } }
          stop_timeout             = 30
        }
        migrations-check = {
          image     = "${local.ecr}/orders-api:1.4.2"
          essential = false
          command   = ["./bin/check-schema-version"]
        }
      }
      volumes = {
        uploads = { efs = { file_system_id = "fs-0123456789abcdef0", access_point_id = "fsap-0123456789abcdef0" } }
      }
      load_balancers = [{
        target_group_arn             = var.api_target_group_arn
        container_name               = "app"
        alternate_target_group_arn   = var.api_alternate_target_group_arn
        production_listener_rule_arn = var.api_listener_rule_arns.production
        test_listener_rule_arn       = var.api_listener_rule_arns.test
      }]
      service_connect = {
        access_logs = { format = "JSON" }
        expose      = { http = { discovery_name = "orders-api", port = 80, test_traffic_header = { name = "x-release-test", value = "1" } } }
      }
      # 10% of traffic for 15 minutes, then the rest; the old revision stays
      # 10 minutes more, and a smoke test must pass before production traffic.
      deployment = {
        strategy            = "CANARY"
        canary_percent      = 10
        canary_bake_minutes = 15
        bake_time_minutes   = 10
        alarm_names         = ["orders-prod-api-5xx"]
        lifecycle_hooks = {
          smoke = {
            function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:orders-smoke-test"
            stages       = ["POST_TEST_TRAFFIC_SHIFT"]
            details      = jsonencode({ path = "/health", header = "x-release-test" })
          }
        }
      }
      autoscaling = {
        min                 = 2
        max                 = 20
        cpu_target          = 60
        requests_per_target = 500
        alb_resource_label  = "app/orders/0123456789abcdef/targetgroup/orders-api/0123456789abcdef"
        schedules = {
          business-hours = { schedule = "cron(0 7 ? * MON-FRI *)", min = 4, max = 20, timezone = "Europe/London" }
          night          = { schedule = "cron(0 20 ? * MON-FRI *)", min = 2, max = 8, timezone = "Europe/London" }
        }
      }
      task_role = {
        policies = {
          read-documents = jsonencode({
            Version   = "2012-10-17"
            Statement = [{ Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::orders-documents/*" }]
          })
        }
      }
      tags = { Component = "api" }
    }

    # Queue consumer: interruptible, so mostly Spot with one on-demand task.
    worker = {
      image    = "${local.ecr}/orders-worker:1.4.2"
      command  = ["./bin/worker", "--queue", "orders"]
      capacity = "balanced"
      # Shell access for on-call; acknowledged below and listed in governance.
      enable_execute_command = true
      # The worker's pipeline registers and deploys its own revisions.
      deployment = { ignore_task_definition_changes = true }
      autoscaling = {
        min        = 2
        max        = 10
        cpu_target = 0
        custom = {
          backlog = {
            target_value = 100
            namespace    = "AWS/SQS"
            metric_name  = "ApproximateNumberOfMessagesVisible"
            statistic    = "Average"
            dimensions   = { QueueName = "orders" }
          }
        }
      }
      service_connect = {}
    }

    # Nightly reconciliation, 02:00 London time, failed invocations kept in SQS.
    reconcile = {
      workload = "scheduled"
      image    = "${local.ecr}/orders-jobs:1.4.2"
      command  = ["./bin/reconcile"]
      cpu      = 512
      memory   = 1024
      capacity = "spot_preferred"
      # Reconciliation output is audit evidence: seven years.
      log_group = { retention_days = 2557 }
      schedule = {
        expression            = "cron(0 2 * * ? *)"
        timezone              = "Europe/London"
        dead_letter_queue_arn = "arn:aws:sqs:eu-west-2:111122223333:orders-schedule-dlq"
      }
    }

    # Run by the pipeline before each release: output.run_task_commands.migrate.
    migrate = {
      workload = "task"
      image    = "${local.ecr}/orders-api:1.4.2"
      command  = ["./bin/migrate", "up"]
    }

    # A stateful search index on its own gp3 volume, restored from a snapshot.
    search = {
      cpu    = 2048
      memory = 8192
      containers = {
        search = {
          image         = "${local.ecr}/search:8.11.1"
          port_mappings = [{ container_port = 9200, name = "search" }]
          mount_points  = [{ source_volume = "index", container_path = "/usr/share/search/data" }]
        }
      }
      volumes            = { index = { configure_at_launch = true } }
      managed_ebs_volume = { volume_name = "index", size_in_gb = 100, snapshot_id = "snap-0123456789abcdef0", throughput = 250 }
      desired_count      = 2
      service_connect    = { expose = { search = {} } }
      # Also resolvable by clients outside ECS, as search.<namespace>.
      service_discovery = { namespace_id = "ns-abcdef0123456789" }
      alarms            = { min_running_tasks = 2 }
      deployment        = { minimum_healthy_percent = 50, maximum_percent = 100 }
    }

    # PDF rendering: CPU-heavy and bursty, packed onto Managed Instances.
    renderer = {
      launch           = "MANAGED_INSTANCES"
      capacity         = "compute"
      cpu_architecture = "ARM64" # compute allows only Graviton types
      image            = "${local.ecr}/orders-renderer:1.4.2"
      port             = 8080
      cpu              = 2048
      memory           = 4096
      desired_count    = 2
      service_connect  = {}
    }

    # One log shipper per EC2 container instance.
    shipper = {
      workload     = "daemon"
      launch       = "EC2"
      network_mode = "bridge"
      cpu          = 128
      memory       = 256
      containers = {
        shipper = {
          image        = "${local.ecr}/log-shipper:2.3.0"
          mount_points = [{ source_volume = "docker-logs", container_path = "/var/lib/docker/containers", read_only = true }]
        }
      }
      volumes = { docker-logs = { host_path = "/var/lib/docker/containers" } }
      # The platform's shared group, forwarded to the SIEM by its owner.
      log_group  = { create = false, name = "/platform/node-logs" }
      deployment = { minimum_healthy_percent = 0 }
    }
  }

  acknowledged_checks = [
    "shell_access_is_intended",
    "containers_stay_on_their_side", # the log shipper reads the host's Docker logs
  ]
}

output "service_arns" {
  value = module.ecs.service_arns
}

output "run_migrations" {
  value = module.ecs.run_task_commands["migrate"]
}

output "governance" {
  value = module.ecs.governance
}

output "network_contract" {
  value = module.ecs.network_contract
}

output "kms_key_policy_requirements" {
  value = module.ecs.kms_key_policy_requirements
}

output "notification_requirements" {
  value = module.ecs.notification_requirements
}

output "deployer_requirements" {
  value = module.ecs.deployer_requirements
}

output "verify_commands" {
  value = module.ecs.verify_commands
}
