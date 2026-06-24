# full apply against mocked aws - builds the whole graph offline

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      name = "mock-bastion-profile"
      arn  = "arn:aws:iam::123456789012:instance-profile/mock-bastion-profile"
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-mock123"
      latest_version = 1
    }
  }
}

# --- Comprehensive isolated bastion with auto-shutdown -----------------------
run "full_stack_apply" {
  command = apply

  variables {
    name       = "test"
    ami_id     = "ami-0123456789abcdef0"
    vpc_id     = "vpc-12345678"
    subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]

    instance_type                  = "t3.small"
    enable_detailed_monitoring     = true
    attach_cloudwatch_agent_policy = true
    iam_role_additional_policy_arns = {
      s3ro = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
    }

    root_block_device = {
      volume_size = 20
      volume_type = "gp3"
    }

    ebs_block_devices = {
      data = { device_name = "/dev/xvdf", volume_size = 50, volume_type = "gp3" }
    }

    auto_shutdown = {
      time_zone = "Europe/London"
    }

    instance_refresh = {
      min_healthy_percentage = 100
    }

    create_cloudwatch_alarms = true

    tags = { Environment = "test" }
  }

  assert {
    condition     = length(aws_autoscaling_group.this) == 1 && length(aws_launch_template.this) == 1
    error_message = "ASG and launch template should be created"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.ssm) == 1 && length(aws_iam_role_policy_attachment.cloudwatch_agent) == 1 && length(aws_iam_role_policy_attachment.additional) == 1
    error_message = "SSM + CW agent + one additional policy should be attached"
  }

  assert {
    condition     = length(aws_autoscaling_schedule.this) == 2
    error_message = "Auto-shutdown should create two schedules"
  }

  assert {
    condition     = length(aws_security_group.this) == 1 && length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "SG with default egress should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.status_check_failed) == 1
    error_message = "StatusCheckFailed alarm should be created"
  }
}

# --- Minimal apply with a BYO instance profile and no SG --------------------
run "byo_profile_no_sg_apply" {
  command = apply

  variables {
    name                      = "test-min"
    ami_id                    = "ami-0123456789abcdef0"
    subnet_ids                = ["subnet-aaaa1111"]
    create_security_group     = false
    security_group_ids        = ["sg-existing01"]
    iam_instance_profile_name = "existing-profile"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0
    error_message = "No IAM role created with a BYO profile"
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No security group created when disabled"
  }

  assert {
    condition     = length(aws_autoscaling_schedule.this) == 0
    error_message = "No schedules by default"
  }
}
