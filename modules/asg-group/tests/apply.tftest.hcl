# A mocked apply: proves the resources assemble end to end, which a plan
# cannot, because a plan leaves the group's computed name unknown. It proves
# nothing about AWS accepting the requests.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  # The provider checks that a launch template ID starts with lt-.
  mock_resource "aws_launch_template" {
    defaults = { id = "lt-00000000000000000", latest_version = 3 }
  }
  mock_resource "aws_autoscaling_group" {
    defaults = { name = "orders-20261117000000000000000001", arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:11111111-2222-3333-4444-555555555555:autoScalingGroupName/orders-20261117000000000000000001" }
  }
}

run "the_whole_fleet_assembles" {
  command = apply

  variables {
    name               = "orders"
    ami                = "ami-0123456789abcdef0"
    subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
    security_group_ids = ["sg-0a1b2c3d4e5f60001"]
    min_size           = 2
    max_size           = 6
    kms_key_arn        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
    sns_topic_arn      = "arn:aws:sns:eu-west-2:111122223333:alerts"
    instance_types     = ["m7i.large", "m6i.large"]
    purchase_options   = { on_demand_base_capacity = 1, on_demand_percentage_above_base_capacity = 50 }
    lifecycle_hooks    = { drain = { transition = "TERMINATING", default_result = "CONTINUE" } }
    target_tracking_policies = {
      cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 60 }
    }
  }

  assert {
    condition     = aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].launch_template_specification[0].version == "3"
    error_message = "the group launches the template's exact latest version, which instance refresh and rollback need."
  }

  assert {
    condition     = aws_autoscaling_lifecycle_hook.this["drain"].autoscaling_group_name == "orders-20261117000000000000000001" && aws_autoscaling_policy.target_tracking["cpu"].autoscaling_group_name == "orders-20261117000000000000000001"
    error_message = "hooks and policies attach to the group the module created."
  }

  assert {
    condition     = jsondecode(aws_cloudwatch_event_rule.this["launch-failed"].event_pattern).detail.AutoScalingGroupName == ["orders-20261117000000000000000001"]
    error_message = "the launch-failure rule matches this group only."
  }

  assert {
    condition     = output.autoscaling_group_arn == "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:11111111-2222-3333-4444-555555555555:autoScalingGroupName/orders-20261117000000000000000001"
    error_message = "the group's ARN is output for an ECS capacity provider."
  }
}
