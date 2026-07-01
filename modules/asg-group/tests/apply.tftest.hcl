# mocked-provider apply. proves the resources assemble end to end without creds.

mock_provider "aws" {
  # the assume-role doc must be valid JSON for aws_iam_role to accept it
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\"}"
    }
  }

  # the ASG validates that launch_template.id begins with 'lt-'
  mock_resource "aws_launch_template" {
    defaults = {
      id = "lt-00000000000000000"
    }
  }
}

run "full_apply" {
  command = apply

  variables {
    name                    = "fleet"
    ami                     = "ami-0123456789abcdef0"
    subnet_ids              = ["subnet-aaaa1111", "subnet-bbbb2222"]
    vpc_id                  = "vpc-12345678"
    create_instance_profile = true
    iam_role_policies = {
      ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      cw  = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    }
    create_security_group = true
    ebs_block_devices = [
      { device_name = "/dev/sdf", volume_size = 100 },
    ]
    instance_types = ["t3.medium", "t3a.medium"]
    spot = {
      on_demand_base_capacity                  = 1
      on_demand_percentage_above_base_capacity = 25
    }
    instance_refresh = { min_healthy_percentage = 90 }
    target_tracking_policies = {
      cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 60 }
    }
    create_cloudwatch_alarms = true
    alarm_actions            = ["arn:aws:sns:us-east-1:123456789012:alerts"]
    tags                     = { Project = "platform", ManagedBy = "Terraform" }
  }

  assert {
    condition     = aws_autoscaling_group.this[0].arn != null
    error_message = "ASG should be created and expose an ARN"
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].mixed_instances_policy) == 1 && length(aws_autoscaling_group.this[0].launch_template) == 0
    error_message = "Spot fleet should use a mixed_instances_policy block"
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override) == 2
    error_message = "Both instance types should appear as mixed-instances overrides"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.this) == 2
    error_message = "Both managed policies should attach"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_high) == 1 && length(aws_cloudwatch_metric_alarm.in_service_low) == 1
    error_message = "Both alarms should be created"
  }
}

run "on_demand_minimal_apply" {
  command = apply

  variables {
    name               = "fleet"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-aaaa1111"]
    security_group_ids = ["sg-existing01"] # BYO SG (no managed SG, no default fallback)
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].launch_template) == 1 && length(aws_autoscaling_group.this[0].mixed_instances_policy) == 0
    error_message = "On-demand fleet should use a plain launch_template block"
  }

  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_security_group.this) == 0
    error_message = "Minimal generic fleet creates no role or managed SG (BYO SG)"
  }
}
