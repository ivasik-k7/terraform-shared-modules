# Advanced landing-ecs example: multi-container tasks, custom autoscaling,
# per-service alarms, and container-level features (command, entrypoint,
# dockerLabels, ulimits, linuxParameters, dependsOn).
#
# Two services:
#   web      nginx in front of the app container, wired via dependsOn so
#            nginx only starts after the app is healthy. Custom scaling on
#            ALB request count per target.
#   worker   app + firelens log router sidecar pushing logs to an external
#            destination (use-case: datadog, honeycomb, logz, etc).

variable "adv_alb_resource_label" {
  description = "ALB target-group resource label for ALBRequestCountPerTarget. Format: app/<lb-name>/<lb-id>/targetgroup/<tg-name>/<tg-id>."
  type        = string
  default     = null
}

module "advanced" {
  source = "../../modules/landing-ecs"

  cluster_name = "landing-ecs-advanced"

  environment = "staging"
  tags = {
    Project    = "advanced-demo"
    Team       = "platform"
    CostCenter = "DEMO"
  }

  default_subnets = data.aws_subnets.basic_default.ids

  enable_container_insights = false
  log_retention_days        = 14

  # Per-service alarm thresholds can be overridden; module defaults act as
  # the baseline. Tighten the module default here.
  alarm_cpu_threshold    = 75
  alarm_memory_threshold = 85

  services = {
    # Multi-container web service: nginx reverse-proxy in front of the app,
    # with container dependency and graceful shutdown ordering.
    web = {
      task_cpu    = 1024
      task_memory = 2048

      containers = {
        # Main app container.
        app = {
          image     = "public.ecr.aws/nginx/nginx:stable-alpine"
          cpu       = 512
          memory    = 1024
          essential = true
          port      = 8080

          command           = ["/docker-entrypoint.sh", "nginx", "-g", "daemon off;"]
          working_directory = "/usr/share/nginx/html"

          environment = {
            LOG_LEVEL = "info"
          }

          docker_labels = {
            "com.datadoghq.ad.logs" = "[{\"source\":\"nginx\",\"service\":\"web-app\"}]"
          }

          ulimits = [
            { name = "nofile", soft_limit = 65536, hard_limit = 65536 },
          ]

          linux_parameters = {
            init_process_enabled = true
          }

          health_check = {
            command      = ["CMD-SHELL", "curl -sf http://localhost:8080/ || exit 1"]
            start_period = 20
          }

          stop_timeout = 30
        }

        # Front-end reverse proxy. Only starts once the app is HEALTHY.
        nginx = {
          image     = "public.ecr.aws/nginx/nginx:stable-alpine"
          cpu       = 256
          memory    = 512
          essential = true
          port      = 80

          depends_on = [
            { container_name = "app", condition = "HEALTHY" },
          ]

          readonly_root_filesystem = true
          docker_labels            = { role = "edge" }
          stop_timeout             = 10
        }
      }

      desired_count = 2
      min_count     = 2
      max_count     = 10

      assign_public_ip = true

      # Default CPU + memory target-tracking policies are still on. On top
      # of that, scale on ALB request rate when a target-group label is set.
      cpu_target_value    = 55
      memory_target_value = 70

      custom_scaling_policies = var.adv_alb_resource_label == null ? [] : [
        {
          name                   = "request-count"
          target_value           = 1000 # requests per target per minute
          predefined_metric_type = "ALBRequestCountPerTarget"
          resource_label         = var.adv_alb_resource_label
          scale_out_cooldown     = 30
          scale_in_cooldown      = 300
        },
      ]

      # Alarm-only, per-service override: page on CPU > 90, memory > 95.
      alarm_cpu_threshold    = 90
      alarm_memory_threshold = 95

      tags = { Component = "web" }
    }

    # Worker with a Firelens log router sidecar. The main container's log
    # driver is awsfirelens; fluentbit does the forwarding.
    worker = {
      capacity_strategy = "spot_preferred"

      task_cpu    = 512
      task_memory = 1024

      containers = {
        app = {
          image     = "public.ecr.aws/nginx/nginx:stable-alpine"
          cpu       = 384
          memory    = 768
          essential = true

          command = ["sh", "-c", "while true; do echo worker tick; sleep 5; done"]

          # Firelens replaces the awslogs driver: logs flow into the log
          # router container, which forwards them wherever it's configured.
          log_driver = "awsfirelens"
          log_options = {
            Name              = "cloudwatch_logs"
            region            = "us-east-1"
            log_group_name    = "/ecs/external/worker"
            log_stream_prefix = "worker-"
            auto_create_group = "true"
          }
        }

        log_router = {
          image     = "public.ecr.aws/aws-observability/aws-for-fluent-bit:stable"
          cpu       = 64
          memory    = 128
          essential = true # keeps log delivery honest

          docker_labels = {
            "com.amazonaws.ecs.log-router" = "fluentbit"
          }
        }
      }

      # Custom scaling on SQS queue depth - uncomment and point at a real
      # queue to activate.
      # custom_scaling_policies = [
      #   {
      #     name         = "sqs-depth"
      #     target_value = 50
      #     customized_metric = {
      #       metric_name = "ApproximateNumberOfMessagesVisible"
      #       namespace   = "AWS/SQS"
      #       statistic   = "Average"
      #       dimensions = [
      #         { name = "QueueName", value = "my-queue" },
      #       ]
      #     }
      #   },
      # ]

      desired_count = 1
      min_count     = 0
      max_count     = 10

      assign_public_ip = true

      # Disable the default memory policy; this worker is CPU-bound and
      # memory-autoscaling would keep it over-provisioned.
      enable_memory_autoscaling = false

      tags = { Component = "worker" }
    }
  }
}

output "advanced_container_names" {
  value       = module.advanced.container_names
  description = "Containers each service ended up with, after shortcut expansion and X-Ray sidecar resolution."
}

output "advanced_alarm_arns" {
  value       = module.advanced.alarm_arns
  description = "Per-service CPU and memory alarm ARNs."
}
