# Every module-level input, in the shape of a web fleet behind an ALB: a mixed
# on-demand and Spot fleet across three instance types, scaled on CPU, ALB
# requests and a queue metric, forecast by predictive scaling, refreshed in
# checkpoints with alarm-driven rollback, encrypted with a customer key.

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
  key     = "arn:aws:kms:eu-west-2:${local.account}:key/11111111-2222-3333-4444-555555555555"
}

variable "private_subnet_ids" {
  description = "Private subnets in three AZs."
  type        = list(string)
  default     = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002", "subnet-0a1b2c3d4e5f60003"]
}

variable "instance_security_group_id" {
  description = "Security group for the instances, open to the ALB's group on the app port."
  type        = string
  default     = "sg-0a1b2c3d4e5f60001"
}

variable "target_group_arn" {
  description = "The ALB target group the instances register with."
  type        = string
  default     = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/orders-web/0123456789abcdef"
}

module "fleet" {
  source = "../.."

  create = true
  name   = "orders-web"

  tags                   = { CostCenter = "cc-1042", Environment = "prod", Owner = "orders-team", Application = "orders" }
  required_tag_keys      = ["CostCenter", "Environment", "Owner"]
  instance_tags          = { BackupPlan = "none" }
  autoscaling_group_tags = { Tier = "web" }

  subnet_ids                     = var.private_subnet_ids
  security_group_ids             = [var.instance_security_group_id]
  public_ip                      = "none"
  availability_zone_distribution = "balanced-best-effort"

  ami               = "ami-0123456789abcdef0"
  ami_ssm_parameter = ""
  instance_type     = "m7i.large"
  instance_types    = ["m7i.large", "m6i.large", "m7a.large", "m7i.xlarge"]
  instance_weights  = { "m7i.xlarge" = 2 }

  purchase_options = {
    on_demand_base_capacity                  = 2
    on_demand_percentage_above_base_capacity = 25
    spot_allocation_strategy                 = "price-capacity-optimized"
    on_demand_allocation_strategy            = "prioritized"
  }
  capacity_rebalance = true

  key_name            = ""
  user_data           = file("${path.module}/user-data.sh")
  metadata_hop_limit  = 1
  metadata_tags       = true
  auto_recovery       = "default"
  ebs_optimized       = ""
  detailed_monitoring = true
  cpu_options         = { threads_per_core = 2 }
  capacity_reservation = {
    preference = "open"
  }

  root_volume = { size_gib = 40, type = "gp3", throughput = 250 }
  ebs_volumes = {
    "/dev/sdf" = { size_gib = 100, type = "gp3", iops = 6000 }
  }
  kms_key_arn             = local.key
  service_linked_role_arn = "arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling_orders"

  instance_profile = {
    ssm = true
    policies = {
      read-config = jsonencode({
        Version   = "2012-10-17"
        Statement = [{ Effect = "Allow", Action = ["ssm:GetParameter"], Resource = "arn:aws:ssm:eu-west-2:111122223333:parameter/orders/*" }]
      })
    }
    managed_policies = { cloudwatch-agent = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
  }
  permissions_boundary_arn = "arn:aws:iam::111122223333:policy/workload-boundary"

  min_size                        = 3
  max_size                        = 12
  desired_capacity                = 4
  ignore_desired_capacity_changes = true
  protect_from_scale_in           = false
  max_instance_lifetime           = 1209600 # 14 days: nothing runs unpatched for longer
  health_check_type               = "ELB"
  health_check_grace_period       = 180
  default_instance_warmup         = 120
  termination_policies            = ["AllocationStrategy", "OldestLaunchTemplate", "Default"]
  suspended_processes             = []
  target_group_arns               = [var.target_group_arn]
  wait_for_capacity_timeout       = "15m"
  wait_for_elb_capacity           = 3
  enabled_metrics                 = ["GroupInServiceInstances", "GroupDesiredCapacity", "GroupPendingInstances", "GroupTotalInstances"]

  # Launch before terminate when an instance is replaced.
  instance_maintenance_policy = { min_healthy_percentage = 100, max_healthy_percentage = 125 }

  instance_refresh = {
    min_healthy_percentage   = 100
    max_healthy_percentage   = 125
    instance_warmup          = 120
    checkpoint_percentages   = [25, 100]
    checkpoint_delay_seconds = 600
    alarm_names              = ["orders-web-5xx"]
    triggers                 = ["tag"]
  }

  lifecycle_hooks = {
    # The deployment agent registers the instance with the release, including the first ones.
    register = { transition = "LAUNCHING", default_result = "ABANDON", heartbeat_timeout = 600, initial = true }
    # Drain connections and ship the last logs before termination.
    drain = {
      transition              = "TERMINATING"
      default_result          = "CONTINUE"
      heartbeat_timeout       = 300
      notification_target_arn = "arn:aws:sqs:eu-west-2:111122223333:orders-web-drain"
      role_arn                = "arn:aws:iam::111122223333:role/orders-web-hook-publisher"
    }
  }

  target_tracking_policies = {
    cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 55 }
    requests = {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "app/orders/0123456789abcdef/targetgroup/orders-web/0123456789abcdef"
      target_value           = 800
    }
    backlog = {
      target_value     = 100
      disable_scale_in = true
      customized       = { namespace = "AWS/SQS", metric_name = "ApproximateNumberOfMessagesVisible", dimensions = { QueueName = "orders" } }
    }
  }

  predictive_scaling = {
    enabled      = true
    metric       = "cpu"
    target_value = 55
    mode         = "ForecastOnly"
  }

  scheduled_actions = {
    business-hours = { min_size = 6, recurrence = "0 7 * * MON-FRI", time_zone = "Europe/London" }
    night          = { min_size = 3, recurrence = "0 20 * * MON-FRI", time_zone = "Europe/London" }
  }

  sns_topic_arn            = "arn:aws:sns:eu-west-2:111122223333:orders-alerts"
  sns_topic_kms_key_arn    = local.key
  create_event_rules       = true
  create_alarms            = true
  alarm_cpu_percent        = 80
  alarm_min_in_service     = -1
  alarm_period             = 60
  alarm_evaluation_periods = 3
  alarm_actions            = ["arn:aws:sns:eu-west-2:111122223333:orders-alerts"]
  ok_actions               = []

  acknowledged_checks = []
}

output "autoscaling_group_arn" {
  value = module.fleet.autoscaling_group_arn
}

output "governance" {
  value = module.fleet.governance
}

output "kms_key_policy_requirements" {
  value = module.fleet.kms_key_policy_requirements
}

output "notification_requirements" {
  value = module.fleet.notification_requirements
}

output "deployer_requirements" {
  value = module.fleet.deployer_requirements
}

output "network_contract" {
  value = module.fleet.network_contract
}

output "verify_commands" {
  value = module.fleet.verify_commands
}
