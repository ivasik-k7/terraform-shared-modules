# plan-only checks, no creds needed. `terraform test`

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Happy path: SSM-only isolated bastion, no inbound -----------------------
run "isolated_ssm_only" {
  command = plan

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = aws_launch_template.this[0].image_id == "ami-0123456789abcdef0"
    error_message = "The provided AMI should be used verbatim"
  }

  assert {
    condition     = aws_launch_template.this[0].metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required"
  }

  assert {
    condition     = length(aws_iam_role.this) == 1 && length(aws_iam_instance_profile.this) == 1
    error_message = "An IAM role + instance profile should be created by default"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1
    error_message = "SSM core policy should be attached by default"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 0
    error_message = "No inbound rules by default (SSM-only)"
  }

  assert {
    condition     = aws_autoscaling_group.this[0].desired_capacity == 1
    error_message = "Default desired capacity should be 1"
  }
}

# --- Auto-shutdown produces scale-down + scale-up schedules ------------------
run "auto_shutdown_schedules" {
  command = plan

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    auto_shutdown = {
      time_zone = "Europe/London"
    }
  }

  assert {
    condition     = length(aws_autoscaling_schedule.this) == 2
    error_message = "Auto-shutdown should create two scheduled actions"
  }

  assert {
    condition     = aws_autoscaling_schedule.this["test-scale-down"].desired_capacity == 0
    error_message = "Scale-down should set desired capacity to 0"
  }

  assert {
    condition     = aws_autoscaling_schedule.this["test-scale-up"].desired_capacity == 1
    error_message = "Scale-up should restore working-hours capacity"
  }

  assert {
    condition     = aws_autoscaling_schedule.this["test-scale-down"].time_zone == "Europe/London"
    error_message = "Schedule time zone should be forwarded"
  }
}

# --- Auto-shutdown can be disabled -------------------------------------------
run "auto_shutdown_disabled" {
  command = plan

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    auto_shutdown = {
      enabled = false
    }
  }

  assert {
    condition     = length(aws_autoscaling_schedule.this) == 0
    error_message = "No schedules when auto_shutdown is disabled"
  }
}

# --- Arbitrary scheduled actions merge with auto-shutdown --------------------
run "custom_scheduled_actions" {
  command = plan

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    scheduled_actions = {
      weekend-down = { recurrence = "0 0 * * SAT", min_size = 0, max_size = 0, desired_capacity = 0 }
    }
  }

  assert {
    condition     = length(aws_autoscaling_schedule.this) == 1
    error_message = "Custom scheduled action should be created"
  }
}

# --- SSH convenience opens inbound on the SSH port --------------------------
run "ssh_ingress" {
  command = plan

  variables {
    name                           = "test"
    ami_id                         = "ami-0123456789abcdef0"
    vpc_id                         = "vpc-12345678"
    subnet_ids                     = ["subnet-aaaa1111"]
    ssh_allowed_cidr_blocks        = ["10.0.0.0/16"]
    ssh_allowed_security_group_ids = ["sg-aaaa1111"]
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 2
    error_message = "One ingress rule per allowed CIDR and security group"
  }
}

# --- Spot via mixed instances policy -----------------------------------------
run "spot_mixed_instances" {
  command = plan

  variables {
    name           = "test"
    ami_id         = "ami-0123456789abcdef0"
    vpc_id         = "vpc-12345678"
    subnet_ids     = ["subnet-aaaa1111"]
    instance_types = ["t3.micro", "t3a.micro"]
    spot_enabled   = true
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].mixed_instances_policy) == 1
    error_message = "A mixed instances policy should be used"
  }
}

# --- Bring-your-own instance profile skips IAM creation ----------------------
run "byo_instance_profile" {
  command = plan

  variables {
    name                      = "test"
    ami_id                    = "ami-0123456789abcdef0"
    vpc_id                    = "vpc-12345678"
    subnet_ids                = ["subnet-aaaa1111"]
    iam_instance_profile_name = "my-existing-profile"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "No IAM role should be created when a profile is provided"
  }

  assert {
    condition     = local.instance_profile_name == "my-existing-profile"
    error_message = "The provided instance profile should be used"
  }
}

# --- Attach the ASG to a target group (ELB health check) --------------------
run "target_group_attach" {
  command = plan

  variables {
    name              = "test"
    ami_id            = "ami-0123456789abcdef0"
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-aaaa1111"]
    health_check_type = "ELB"
    target_group_arns = ["arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/x/abc"]
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].target_group_arns) == 1
    error_message = "The ASG should be attached to the provided target group"
  }
}

# --- StatusCheckFailed alarm when enabled (off by default) ------------------
run "status_check_alarm" {
  command = plan

  variables {
    name                     = "test"
    ami_id                   = "ami-0123456789abcdef0"
    vpc_id                   = "vpc-12345678"
    subnet_ids               = ["subnet-aaaa1111"]
    create_cloudwatch_alarms = true
    alarm_actions            = ["arn:aws:sns:us-east-1:123456789012:alerts"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.status_check_failed) == 1
    error_message = "A StatusCheckFailed alarm should be created when enabled"
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.status_check_failed[0].metric_name == "StatusCheckFailed"
    error_message = "Alarm should watch StatusCheckFailed"
  }
}

run "no_alarm_by_default" {
  command = plan

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.status_check_failed) == 0
    error_message = "No alarm by default"
  }
}

# --- create = false builds nothing -------------------------------------------
run "create_false" {
  command = plan

  variables {
    create     = false
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 0 && length(aws_launch_template.this) == 0 && length(aws_security_group.this) == 0
    error_message = "create=false should build nothing"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "invalid_ami_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "not-an-ami"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
  }
  expect_failures = [var.ami_id]
}

run "no_subnets_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = []
  }
  expect_failures = [var.subnet_ids]
}

run "sg_without_vpc_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    subnet_ids = ["subnet-aaaa1111"]
  }
  expect_failures = [var.vpc_id]
}

run "elb_health_check_without_target_group_fails" {
  command = plan
  variables {
    name              = "test"
    ami_id            = "ami-0123456789abcdef0"
    vpc_id            = "vpc-12345678"
    subnet_ids        = ["subnet-aaaa1111"]
    health_check_type = "ELB"
  }
  expect_failures = [aws_autoscaling_group.this]
}

run "invalid_metadata_http_tokens_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    metadata_options = {
      http_tokens = "maybe"
    }
  }
  expect_failures = [var.metadata_options]
}

run "invalid_root_volume_type_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    root_block_device = {
      volume_type = "magnetic"
    }
  }
  expect_failures = [var.root_block_device]
}

run "invalid_metadata_hop_limit_fails" {
  command = plan
  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111"]
    metadata_options = {
      http_put_response_hop_limit = 99
    }
  }
  expect_failures = [var.metadata_options]
}

# --- Wanting SSM but providing neither role nor profile -> precondition fails -
run "ssm_without_profile_fails" {
  command = plan
  variables {
    name            = "test"
    ami_id          = "ami-0123456789abcdef0"
    vpc_id          = "vpc-12345678"
    subnet_ids      = ["subnet-aaaa1111"]
    create_iam_role = false # but enable_ssm defaults true and no profile provided
  }
  expect_failures = [aws_launch_template.this]
}
