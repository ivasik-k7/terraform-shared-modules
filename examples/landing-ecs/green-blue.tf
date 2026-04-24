# Blue/green deployment example, implemented on top of the landing-ecs module.
#
# Why not CodeDeploy?
#   The module uses the default ECS deployment controller (rolling updates +
#   circuit-breaker rollback). CodeDeploy BLUE_GREEN would require
#   `deployment_controller = "CODE_DEPLOY"` on the service, which the module
#   intentionally does not expose. Instead this example uses an ALB-native
#   pattern: two parallel services, one ALB listener doing weighted forward,
#   traffic shift driven by a single variable.
#
# Cost
#   Both colors warm at once = 2x compute while fully scaled. Between
#   deployments you can manually scale the idle color to zero:
#     aws ecs update-service --cluster bg-demo --service bg-demo-api_green \
#                            --desired-count 0
#   Promotion then takes ~2-5 min (cold start) instead of being instant.
#
# Deployment flow
#   Initial:
#     bg_blue_image_tag  = "1.0.0"   (current prod)
#     bg_green_image_tag = "1.0.0"   (idle, matches blue)
#     bg_traffic_split   = "blue"    -> 100% blue
#
#   Release v2:
#     1. bump bg_green_image_tag to "2.0.0" and apply
#        (green rolls to 2.0.0; still 0% live traffic)
#        smoke-test green directly via the X-Deploy-Color header
#     2. set bg_traffic_split = "canary" and apply
#        90/10 split; watch error rate, latency, business metrics
#     3. ramp: "fifty_fifty" -> "green" (all traffic on v2)
#     4. promote: set bg_blue_image_tag = bg_green_image_tag = "2.0.0",
#        set bg_traffic_split = "blue" and apply
#
# Rollback
#   bg_traffic_split = "blue" and apply. Listener weights update atomically.
#
# Smoke tests without a traffic shift
#   curl -H "X-Deploy-Color: green" http://<alb-dns>/
#   curl -H "X-Deploy-Color: blue"  http://<alb-dns>/

variable "bg_image_base" {
  description = "Container image base URI (registry + repo, no tag). Example: 123456789012.dkr.ecr.eu-west-1.amazonaws.com/checkout. Defaults to public nginx for a working demo out of the box."
  type        = string
  default     = "public.ecr.aws/nginx/nginx"
}

variable "bg_blue_image_tag" {
  description = "Image tag running on BLUE (current production version)."
  type        = string
  default     = "stable-alpine"
}

variable "bg_green_image_tag" {
  description = "Image tag running on GREEN (version being released). Equal to blue when no release is in-flight."
  type        = string
  default     = "stable-alpine"
}

variable "bg_traffic_split" {
  description = "Routing mode: blue (100/0), canary (100-N/N), fifty_fifty (50/50), green (0/100)."
  type        = string
  default     = "blue"

  validation {
    condition     = contains(["blue", "canary", "fifty_fifty", "green"], var.bg_traffic_split)
    error_message = "bg_traffic_split must be one of: blue, canary, fifty_fifty, green."
  }
}

variable "bg_canary_green_weight" {
  description = "Percent of traffic sent to GREEN when bg_traffic_split = canary."
  type        = number
  default     = 10

  validation {
    condition     = var.bg_canary_green_weight > 0 && var.bg_canary_green_weight < 100
    error_message = "bg_canary_green_weight must be between 1 and 99."
  }
}

locals {
  bg_cluster_name   = "bg-demo"
  bg_app_name       = "api"
  bg_container_port = 80

  bg_green_weight = (
    var.bg_traffic_split == "blue" ? 0 :
    var.bg_traffic_split == "green" ? 100 :
    var.bg_traffic_split == "fifty_fifty" ? 50 :
    var.bg_canary_green_weight
  )
  bg_blue_weight = 100 - local.bg_green_weight
}

# Default VPC for simplicity. Swap to private subnets in prod.
data "aws_vpc" "bg_default" {
  default = true
}

data "aws_subnets" "bg_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.bg_default.id]
  }
}

# ALB: one listener, two target groups, weighted forwarding.
resource "aws_security_group" "bg_alb" {
  name        = "${local.bg_cluster_name}-alb"
  description = "ALB ingress for blue/green demo"
  vpc_id      = data.aws_vpc.bg_default.id
}

resource "aws_vpc_security_group_ingress_rule" "bg_alb_http" {
  security_group_id = aws_security_group.bg_alb.id
  description       = "HTTP from anywhere"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "bg_alb_all" {
  security_group_id = aws_security_group.bg_alb.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_lb" "bg" {
  name               = "${local.bg_cluster_name}-${local.bg_app_name}"
  internal           = false
  load_balancer_type = "application"
  subnets            = data.aws_subnets.bg_default.ids
  security_groups    = [aws_security_group.bg_alb.id]
}

resource "aws_lb_target_group" "bg_blue" {
  name        = "${local.bg_cluster_name}-${local.bg_app_name}-blue"
  port        = local.bg_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.bg_default.id

  # Short deregistration delay so rollbacks drain quickly.
  deregistration_delay = 30

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200-399"
  }

  tags = { Color = "blue" }
}

resource "aws_lb_target_group" "bg_green" {
  name        = "${local.bg_cluster_name}-${local.bg_app_name}-green"
  port        = local.bg_container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = data.aws_vpc.bg_default.id

  deregistration_delay = 30

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 15
    timeout             = 5
    matcher             = "200-399"
  }

  tags = { Color = "green" }
}

# The actual blue/green traffic controller: weighted forward on the default
# listener action.
resource "aws_lb_listener" "bg_main" {
  load_balancer_arn = aws_lb.bg.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.bg_blue.arn
        weight = local.bg_blue_weight
      }
      target_group {
        arn    = aws_lb_target_group.bg_green.arn
        weight = local.bg_green_weight
      }

      # Off by default so canary metrics stay statistically clean. Turn on
      # with a short duration if you want a consistent color per session
      # during a long rollout.
      stickiness {
        enabled  = false
        duration = 60
      }
    }
  }
}

# Smoke-test bypass rules: hit a specific color by header, ignoring weights.
# Useful for verifying green is healthy before shifting real traffic.
resource "aws_lb_listener_rule" "bg_direct_blue" {
  listener_arn = aws_lb_listener.bg_main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bg_blue.arn
  }

  condition {
    http_header {
      http_header_name = "X-Deploy-Color"
      values           = ["blue"]
    }
  }
}

resource "aws_lb_listener_rule" "bg_direct_green" {
  listener_arn = aws_lb_listener.bg_main.arn
  priority     = 101

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.bg_green.arn
  }

  condition {
    http_header {
      http_header_name = "X-Deploy-Color"
      values           = ["green"]
    }
  }
}

# Two parallel services, one per color.
module "bg" {
  source = "../../modules/landing-ecs"

  cluster_name = local.bg_cluster_name

  environment = "staging"
  tags = {
    Project    = "bg-demo"
    Team       = "platform"
    CostCenter = "DEMO"
  }

  vpc_id                         = data.aws_vpc.bg_default.id
  default_subnets                = data.aws_subnets.bg_default.ids
  create_service_security_groups = true

  enable_container_insights = false
  log_retention_days        = 14

  services = {
    # BLUE: current production.
    api_blue = {
      image  = "${var.bg_image_base}:${var.bg_blue_image_tag}"
      cpu    = 256
      memory = 512
      port   = local.bg_container_port

      assign_public_ip = true

      desired_count = 2
      min_count     = 2
      max_count     = 6

      load_balancer = {
        target_group_arn = aws_lb_target_group.bg_blue.arn
        container_port   = local.bg_container_port
      }

      stop_timeout                      = 45 # let in-flight requests drain
      health_check_grace_period_seconds = 30 # module requires >= 30 for LB-attached services

      tags = { Color = "blue" }
    }

    # GREEN: next release staging area.
    api_green = {
      image  = "${var.bg_image_base}:${var.bg_green_image_tag}"
      cpu    = 256
      memory = 512
      port   = local.bg_container_port

      assign_public_ip = true

      desired_count = 2
      min_count     = 2
      max_count     = 6

      load_balancer = {
        target_group_arn = aws_lb_target_group.bg_green.arn
        container_port   = local.bg_container_port
      }

      stop_timeout                      = 45
      health_check_grace_period_seconds = 30

      tags = { Color = "green" }
    }
  }
}

# Let each color's tasks accept traffic from the shared ALB SG.
resource "aws_vpc_security_group_ingress_rule" "bg_task_from_alb_blue" {
  security_group_id            = module.bg.service_security_group_ids["api_blue"]
  description                  = "HTTP from ALB to blue tasks"
  ip_protocol                  = "tcp"
  from_port                    = local.bg_container_port
  to_port                      = local.bg_container_port
  referenced_security_group_id = aws_security_group.bg_alb.id
}

resource "aws_vpc_security_group_ingress_rule" "bg_task_from_alb_green" {
  security_group_id            = module.bg.service_security_group_ids["api_green"]
  description                  = "HTTP from ALB to green tasks"
  ip_protocol                  = "tcp"
  from_port                    = local.bg_container_port
  to_port                      = local.bg_container_port
  referenced_security_group_id = aws_security_group.bg_alb.id
}

output "bg_alb_url" {
  description = "ALB entrypoint. Routes to blue/green per bg_traffic_split."
  value       = "http://${aws_lb.bg.dns_name}"
}

output "bg_active_weights" {
  description = "Current traffic split (percent). Reflects bg_traffic_split."
  value = {
    mode  = var.bg_traffic_split
    blue  = local.bg_blue_weight
    green = local.bg_green_weight
  }
}

output "bg_smoke_test_commands" {
  description = "Curl commands that bypass the weighted split (for pre-shift verification)."
  value = {
    blue  = "curl -s -H 'X-Deploy-Color: blue'  http://${aws_lb.bg.dns_name}/ -o /dev/null -w '%%{http_code}\\n'"
    green = "curl -s -H 'X-Deploy-Color: green' http://${aws_lb.bg.dns_name}/ -o /dev/null -w '%%{http_code}\\n'"
  }
}

output "bg_running_versions" {
  description = "Current image tag per color."
  value = {
    blue  = var.bg_blue_image_tag
    green = var.bg_green_image_tag
  }
}
