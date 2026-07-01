# plan-level checks, no creds. `terraform test`

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- on-demand single-type fleet, no IAM/SG (most generic shape) ------------
run "basic_on_demand" {
  command = plan

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    security_group_ids = ["sg-existing01"] # BYO SG (no managed SG created)
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 1 && length(aws_launch_template.this) == 1
    error_message = "An ASG and a launch template should be planned"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_security_group.this) == 0
    error_message = "No IAM role or managed SG here (BYO SG, generic minimal)"
  }

  assert {
    condition     = contains(aws_launch_template.this[0].vpc_security_group_ids, "sg-existing01")
    error_message = "The launch template should carry the provided security group"
  }

  assert {
    condition     = aws_launch_template.this[0].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 should be enforced"
  }

  assert {
    condition     = aws_launch_template.this[0].image_id == "ami-0123456789abcdef0"
    error_message = "Explicit AMI should be used"
  }
}

# --- comprehensive: IAM + SG + extra EBS + target tracking + scheduled ------
run "comprehensive" {
  command = plan

  variables {
    name                    = "fleet"
    ami                     = "ami-0123456789abcdef0"
    subnet_ids              = ["subnet-aaaa1111"]
    vpc_id                  = "vpc-12345678"
    create_instance_profile = true
    iam_role_policies = {
      ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    create_security_group = true
    security_group_ingress_rules = {
      ssh = { from_port = 22, to_port = 22, cidr_ipv4 = "10.0.0.0/8" }
    }
    ebs_block_devices = [
      { device_name = "/dev/sdf", volume_size = 100, volume_type = "gp3" },
    ]
    target_tracking_policies = {
      cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 60 }
    }
    scheduled_actions = {
      night = { recurrence = "0 2 * * *", min_size = 0, max_size = 2 }
    }
    create_cloudwatch_alarms = true
  }

  assert {
    condition     = length(aws_iam_role.this) == 1 && length(aws_iam_role_policy_attachment.this) == 1
    error_message = "IAM role + the ssm policy attachment should be planned"
  }

  assert {
    condition     = length(aws_security_group.this) == 1 && length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "Managed SG with one ingress rule should be planned"
  }

  assert {
    condition     = length(aws_autoscaling_policy.target_tracking) == 1 && length(aws_autoscaling_schedule.this) == 1
    error_message = "A target-tracking policy and a scheduled action should be planned"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1 && length(aws_cloudwatch_metric_alarm.in_service_low) == 1
    error_message = "Both CloudWatch alarms should be planned"
  }
}

# --- ALB request-count target tracking (needs resource_label) ---------------
run "alb_request_tracking" {
  command = plan

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    target_group_arns  = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/tg/abc"]
    health_check_type  = "ELB"
    target_tracking_policies = {
      reqs = {
        predefined_metric_type = "ALBRequestCountPerTarget"
        target_value           = 1000
        resource_label         = "app/my-alb/abc/targetgroup/tg/def"
      }
    }
  }

  assert {
    condition     = length(aws_autoscaling_policy.target_tracking) == 1
    error_message = "ALB request-count policy should be planned"
  }
}

# --- AMI resolved from SSM --------------------------------------------------
run "ami_from_ssm" {
  command = plan

  variables {
    name               = "fleet"
    ami_ssm_parameter  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
  }

  override_data {
    target = data.aws_ssm_parameter.ami[0]
    values = { value = "ami-0aaaa1111bbbb2222" }
  }

  assert {
    condition     = aws_launch_template.this[0].image_id == "ami-0aaaa1111bbbb2222"
    error_message = "Launch template should use the SSM-resolved AMI"
  }
}

# --- spot mixed-instances ---------------------------------------------------
run "spot_mixed" {
  command = plan

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    instance_types     = ["t3.medium", "t3a.medium", "t3.large"]
    spot = {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 0
    }
  }

  assert {
    condition     = aws_autoscaling_group.this[0].capacity_rebalance == true
    error_message = "Capacity rebalancing should be forced on for spot"
  }

  assert {
    condition     = local.override_instance_types == tolist(["t3.medium", "t3a.medium", "t3.large"])
    error_message = "All three instance types should drive the mixed-instances overrides"
  }
}

# --- ECS compatibility: generic knobs produce an ECS-ready ASG --------------
run "ecs_compatible" {
  command = plan

  variables {
    name                    = "ecs-nodes"
    ami                     = "ami-0123456789abcdef0"
    subnet_ids              = ["subnet-aaaa1111"]
    vpc_id                  = "vpc-12345678"
    protect_from_scale_in   = true
    autoscaling_group_tags  = { AmazonECSManaged = "" }
    create_security_group   = true
    create_instance_profile = true
    iam_role_policies = {
      ecs = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
    }
    user_data = "#!/bin/bash\necho ECS_CLUSTER=platform >> /etc/ecs/ecs.config\n"
  }

  assert {
    condition     = aws_autoscaling_group.this[0].protect_from_scale_in == true
    error_message = "protect_from_scale_in should be settable for ECS managed termination protection"
  }

  assert {
    condition     = length([for t in aws_autoscaling_group.this[0].tag : t if t.key == "AmazonECSManaged"]) == 1
    error_message = "AmazonECSManaged tag should be set via autoscaling_group_tags"
  }
}

# --- create = false builds nothing ------------------------------------------
run "create_false" {
  command = plan

  variables {
    create     = false
    name       = "fleet"
    ami        = "ami-0123456789abcdef0"
    subnet_ids = ["subnet-aaaa1111"]
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 0 && length(aws_launch_template.this) == 0
    error_message = "create=false should build nothing"
  }
}

# --- public IP via network interface ----------------------------------------
run "public_ip" {
  command = plan

  variables {
    name                        = "fleet"
    ami                         = "ami-0123456789abcdef0"
    subnet_ids                  = ["subnet-aaaa1111"]
    security_group_ids          = ["sg-existing01"]
    associate_public_ip_address = true
  }

  assert {
    condition     = length(aws_launch_template.this[0].network_interfaces) == 1
    error_message = "Forcing a public IP should emit a network_interfaces block"
  }
}

# --- AZ-only placement (no subnets) -----------------------------------------
run "az_only_placement" {
  command = plan

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    security_group_ids = ["sg-existing01"]
    subnet_ids         = []
    availability_zones = ["us-east-1a", "us-east-1b"]
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 1
    error_message = "AZ-only placement should satisfy the placement precondition"
  }
}

# --- in-service alarm is gated on the metric being collected -----------------
run "in_service_alarm_gated_off" {
  command = plan

  variables {
    name                     = "fleet"
    ami                      = "ami-0123456789abcdef0"
    subnet_ids               = ["subnet-aaaa1111"]
    security_group_ids       = ["sg-existing01"]
    create_cloudwatch_alarms = true
    enabled_metrics          = [] # GroupInServiceInstances not collected
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1 && length(aws_cloudwatch_metric_alarm.in_service_low) == 0
    error_message = "in-service alarm must be skipped when GroupInServiceInstances isn't collected; CPU alarm still created"
  }
}

# --- long name + IAM: name_prefix is truncated to the IAM 38-char limit ------
run "long_name_with_iam" {
  command = plan

  variables {
    name                    = "platform-prod-ecs-capacity-nodes-group-name-60"
    ami                     = "ami-0123456789abcdef0"
    subnet_ids              = ["subnet-aaaa1111"]
    security_group_ids      = ["sg-existing01"]
    create_instance_profile = true
  }

  assert {
    condition     = length(aws_iam_role.this) == 1
    error_message = "a long name with IAM must still plan (IAM name_prefix truncated to 38)"
  }
}

# --- advanced blocks all plan cleanly (warm pool, refresh, hooks, cpu opts) --
run "advanced_blocks" {
  command = plan

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    ebs_optimized      = true
    cpu_options        = { threads_per_core = 1 }
    instance_refresh   = { min_healthy_percentage = 90 }
    warm_pool          = { pool_state = "Stopped", min_size = 1 }
    initial_lifecycle_hooks = {
      drain = { lifecycle_transition = "autoscaling:EC2_INSTANCE_TERMINATING", heartbeat_timeout = 300 }
    }
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 1
    error_message = "warm pool / instance refresh / lifecycle hooks / cpu options should all plan cleanly"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "max_below_min_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    min_size           = 5
    max_size           = 2
  }
  expect_failures = [var.max_size]
}

run "sg_without_vpc_fails" {
  command = plan
  variables {
    name                  = "fleet"
    ami                   = "ami-0123456789abcdef0"
    subnet_ids            = ["subnet-aaaa1111"]
    create_security_group = true
    vpc_id                = null
  }
  expect_failures = [var.vpc_id]
}

run "invalid_root_volume_type_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    root_volume_type   = "st1"
  }
  expect_failures = [var.root_volume_type]
}

run "invalid_ami_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "not-an-ami"
    subnet_ids         = ["subnet-aaaa1111"]
  }
  expect_failures = [var.ami]
}

run "alb_tracking_without_label_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    target_tracking_policies = {
      reqs = { predefined_metric_type = "ALBRequestCountPerTarget", target_value = 1000 }
    }
  }
  expect_failures = [var.target_tracking_policies]
}

run "invalid_spot_percentage_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    spot = {
      on_demand_percentage_above_base_capacity = 150
    }
  }
  expect_failures = [var.spot]
}

run "user_data_conflict_fails" {
  command = plan
  variables {
    name               = "fleet"
    security_group_ids = ["sg-existing01"]
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    user_data          = "#!/bin/bash\ntrue\n"
    user_data_base64   = "IyEvYmluL2Jhc2gK"
  }
  expect_failures = [var.user_data_base64]
}

# no security group at all -> instances would fall back to the default SG
run "no_security_group_fails" {
  command = plan
  variables {
    name       = "fleet"
    ami        = "ami-0123456789abcdef0"
    subnet_ids = ["subnet-aaaa1111"]
    # neither create_security_group nor security_group_ids
  }
  expect_failures = [aws_launch_template.this]
}

# no subnets and no AZs -> the ASG has nowhere to place instances
run "no_placement_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    security_group_ids = ["sg-existing01"]
    subnet_ids         = []
  }
  expect_failures = [aws_autoscaling_group.this]
}

# both subnets and AZs set -> ambiguous placement
run "az_and_subnets_conflict_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    security_group_ids = ["sg-existing01"]
    subnet_ids         = ["subnet-aaaa1111"]
    availability_zones = ["us-east-1a"]
  }
  expect_failures = [var.availability_zones]
}

# kms key set but encryption disabled
run "kms_without_encryption_fails" {
  command = plan
  variables {
    name                  = "fleet"
    ami                   = "ami-0123456789abcdef0"
    subnet_ids            = ["subnet-aaaa1111"]
    security_group_ids    = ["sg-existing01"]
    root_volume_encrypted = false
    kms_key_id            = "arn:aws:kms:us-east-1:123456789012:key/abcd-ef01"
  }
  expect_failures = [var.kms_key_id]
}

# spot_instance_pools only valid with lowest-price allocation
run "spot_pools_wrong_strategy_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    spot = {
      spot_instance_pools = 2 # default allocation_strategy is price-capacity-optimized
    }
  }
  expect_failures = [var.spot]
}

# an extra volume reusing the root device name -> duplicate block mapping
run "ebs_device_collides_with_root_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    ebs_block_devices = [
      { device_name = "/dev/xvda", volume_size = 50 }, # same as root_volume_device_name
    ]
  }
  expect_failures = [var.ebs_block_devices]
}

# L1: desired_capacity outside [min, max]
run "desired_capacity_out_of_range_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    min_size           = 2
    max_size           = 5
    desired_capacity   = 9
  }
  expect_failures = [var.desired_capacity]
}

# L2: spot on-demand base exceeds max_size
run "spot_base_exceeds_max_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    max_size           = 3
    spot               = { on_demand_base_capacity = 5 }
  }
  expect_failures = [var.spot]
}

# L3: iops on a volume type that doesn't support it
run "root_iops_on_gp2_fails" {
  command = plan
  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"]
    root_volume_type   = "gp2"
    root_volume_iops   = 3000
  }
  expect_failures = [var.root_volume_iops]
}

# L3: throughput only valid on gp3
run "root_throughput_on_io1_fails" {
  command = plan
  variables {
    name                   = "fleet"
    ami                    = "ami-0123456789abcdef0"
    subnet_ids             = ["subnet-aaaa1111"]
    security_group_ids     = ["sg-existing01"]
    root_volume_type       = "io1"
    root_volume_iops       = 3000
    root_volume_throughput = 250
  }
  expect_failures = [var.root_volume_throughput]
}
