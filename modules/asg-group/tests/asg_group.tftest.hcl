# Properties of the rendered configuration, one run per property. The baseline
# is a fully configured module, so its own advisory checks pass.
#
# What a mock cannot show: replacement (mock_provider never reports
# RequiresReplace), AWS accepting a request, or whether an instance launches.
# The group's name is computed, so anything built from it is unknown at plan.

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
  mock_data "aws_ssm_parameter" {
    defaults = { insecure_value = "ami-0fedcba9876543210" }
  }
}

variables {
  name               = "orders"
  ami                = "ami-0123456789abcdef0"
  subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  min_size           = 2
  max_size           = 4
  kms_key_arn        = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  sns_topic_arn      = "arn:aws:sns:eu-west-2:111122223333:alerts"
  tags               = { CostCenter = "cc-1", Environment = "test" }
}

# ---------------------------------------------------------------------------
# Launch template
# ---------------------------------------------------------------------------

run "instances_launch_hardened_by_default" {
  command = plan

  assert {
    condition = alltrue([
      aws_launch_template.this[0].metadata_options[0].http_tokens == "required",
      aws_launch_template.this[0].metadata_options[0].http_put_response_hop_limit == 1,
      aws_launch_template.this[0].metadata_options[0].http_endpoint == "enabled",
    ])
    error_message = "IMDSv2 is required, with a hop limit that keeps containers away from instance credentials."
  }

  assert {
    condition = alltrue([
      aws_launch_template.this[0].block_device_mappings[0].ebs[0].encrypted == "true",
      aws_launch_template.this[0].block_device_mappings[0].ebs[0].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555",
      aws_launch_template.this[0].block_device_mappings[0].ebs[0].volume_type == "gp3",
      aws_launch_template.this[0].block_device_mappings[0].ebs[0].volume_size == 30,
    ])
    error_message = "the root volume is an encrypted 30 GiB gp3 under the customer key."
  }

  assert {
    condition     = aws_launch_template.this[0].key_name == null && aws_launch_template.this[0].vpc_security_group_ids == toset(["sg-0a1b2c3d4e5f60001"])
    error_message = "no SSH key, and the security groups sit on the template."
  }

  assert {
    condition     = aws_launch_template.this[0].credit_specification[0].cpu_credits == "standard" && aws_launch_template.this[0].instance_type == "t3.medium"
    error_message = "a burstable single-type fleet launches with standard credits, so its CPU bill has a ceiling."
  }

  assert {
    condition     = aws_launch_template.this[0].update_default_version == true
    error_message = "the template's default version follows the latest."
  }
}

run "extra_volumes_are_always_encrypted" {
  command = plan

  variables {
    ebs_volumes = {
      "/dev/sdf" = { size_gib = 100, iops = 6000 }
      "/dev/sdg" = { type = "st1", size_gib = 500, delete_on_termination = false }
    }
  }

  assert {
    condition = alltrue([for b in aws_launch_template.this[0].block_device_mappings : alltrue([
      b.ebs[0].encrypted == "true",
      b.ebs[0].kms_key_id == "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555",
    ])])
    error_message = "every volume, root and extra, is encrypted under the customer key."
  }

  assert {
    condition     = one([for b in aws_launch_template.this[0].block_device_mappings : b.ebs[0].delete_on_termination if b.device_name == "/dev/sdg"]) == "false"
    error_message = "a volume can outlive its instance when asked."
  }
}

run "a_forced_public_ip_setting_moves_the_groups_to_the_interface" {
  command = plan

  variables {
    public_ip = "none"
  }

  assert {
    condition     = aws_launch_template.this[0].vpc_security_group_ids == null
    error_message = "with a network interface, the template carries no top-level security groups (EC2 refuses both)."
  }

  assert {
    condition     = aws_launch_template.this[0].network_interfaces[0].associate_public_ip_address == "false" && aws_launch_template.this[0].network_interfaces[0].security_groups == toset(["sg-0a1b2c3d4e5f60001"])
    error_message = "the interface refuses a public IP and carries the security groups."
  }
}

run "an_ami_from_ssm_is_resolved_at_plan" {
  command = plan

  variables {
    ami                 = ""
    ami_ssm_parameter   = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    acknowledged_checks = ["ami_is_pinned"]
  }

  assert {
    condition     = aws_launch_template.this[0].image_id == "ami-0fedcba9876543210"
    error_message = "the template pins the AMI ID the parameter holds at plan, never resolve:ssm:, which would rule out rollback and skip matching."
  }
}

run "tags_reach_every_instance_and_cannot_be_overridden" {
  command = plan

  variables {
    tags                   = { CostCenter = "cc-1", Environment = "test", ManagedBy = "someone", Module = "other" }
    instance_tags          = { BackupPlan = "daily" }
    autoscaling_group_tags = { AmazonECSManaged = "" }
  }

  assert {
    condition = alltrue([for s in aws_launch_template.this[0].tag_specifications : alltrue([
      s.tags["CostCenter"] == "cc-1", s.tags["BackupPlan"] == "daily", s.tags["ManagedBy"] == "Terraform", s.tags["Module"] == "asg-group", s.tags["Name"] == "orders",
    ])])
    error_message = "instances, volumes and interfaces carry the cost tags, the instance tags and the module's own."
  }

  assert {
    condition     = toset([for s in aws_launch_template.this[0].tag_specifications : s.resource_type]) == toset(["instance", "volume", "network-interface"])
    error_message = "every billable thing an instance creates is tagged at launch."
  }

  assert {
    condition = alltrue([
      contains([for t in aws_autoscaling_group.this[0].tag : t.key if t.propagate_at_launch], "AmazonECSManaged"),
      one([for t in aws_autoscaling_group.this[0].tag : t.value if t.key == "Module"]) == "asg-group",
    ])
    error_message = "group tags propagate, and the module's keys win."
  }
}

# ---------------------------------------------------------------------------
# The group
# ---------------------------------------------------------------------------

run "the_group_spreads_refreshes_and_reports_by_default" {
  command = plan

  assert {
    condition     = length(aws_autoscaling_group.this) == 1 && length(aws_autoscaling_group.static) == 0
    error_message = "by default something else owns the instance count, so the ignoring resource holds the group."
  }

  assert {
    condition     = aws_autoscaling_group.this[0].desired_capacity == 2 && aws_autoscaling_group.this[0].vpc_zone_identifier == toset(["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"])
    error_message = "the group starts at min_size, across every subnet."
  }

  assert {
    condition = alltrue([
      aws_autoscaling_group.this[0].instance_refresh[0].strategy == "Rolling",
      aws_autoscaling_group.this[0].instance_refresh[0].preferences[0].auto_rollback == true,
      aws_autoscaling_group.this[0].instance_refresh[0].preferences[0].skip_matching == true,
      aws_autoscaling_group.this[0].instance_refresh[0].preferences[0].min_healthy_percentage == 90,
    ])
    error_message = "a template change rolls the fleet, rolls back on failure and skips instances already up to date."
  }

  assert {
    condition     = length(aws_autoscaling_group.this[0].launch_template) == 1 && length(aws_autoscaling_group.this[0].mixed_instances_policy) == 0
    error_message = "a single-type on-demand fleet uses the plain launch template, not a mixed policy."
  }

  assert {
    condition     = contains(aws_autoscaling_group.this[0].enabled_metrics, "GroupInServiceInstances") && aws_autoscaling_group.this[0].metrics_granularity == "1Minute"
    error_message = "group metrics are collected, for the in-service alarm."
  }
}

run "terraform_owns_the_count_when_asked" {
  command = plan

  variables {
    ignore_desired_capacity_changes = false
    desired_capacity                = 3
  }

  assert {
    condition     = alltrue([length(aws_autoscaling_group.this) == 0, aws_autoscaling_group.static[0].desired_capacity == 3])
    error_message = "with ignore_desired_capacity_changes = false the group is .static, and desired_capacity is Terraform's."
  }

  assert {
    condition     = output.governance.instance_count_owner == "terraform"
    error_message = "governance says who owns the count."
  }
}

run "a_mixed_fleet_diversifies_and_rebalances_spot" {
  command = plan

  variables {
    instance_type    = "m7i.large"
    instance_types   = ["m7i.large", "m6i.large", "m7i.xlarge"]
    instance_weights = { "m7i.xlarge" = 2 }
    purchase_options = { on_demand_base_capacity = 1, on_demand_percentage_above_base_capacity = 25 }
  }

  assert {
    condition = jsonencode([for o in aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override : [o.instance_type, o.weighted_capacity]]) == jsonencode([
      ["m7i.large", null], ["m6i.large", null], ["m7i.xlarge", "2"],
    ])
    error_message = "each type is an override in preference order, with its weight."
  }

  assert {
    condition = alltrue([
      aws_autoscaling_group.this[0].mixed_instances_policy[0].instances_distribution[0].on_demand_base_capacity == 1,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].instances_distribution[0].on_demand_percentage_above_base_capacity == 25,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].instances_distribution[0].spot_allocation_strategy == "price-capacity-optimized",
      aws_autoscaling_group.this[0].capacity_rebalance == true,
    ])
    error_message = "the on-demand floor and share are as asked, Spot is price-capacity-optimized, and capacity rebalancing is on."
  }

  assert {
    condition     = aws_launch_template.this[0].instance_type == null && length(aws_launch_template.this[0].credit_specification) == 0
    error_message = "the overrides choose the type, and no credit setting is sent to non-burstable types."
  }
}

run "attribute_based_selection_lets_ec2_choose_the_types" {
  command = plan

  variables {
    instance_requirements = { vcpu_min = 2, vcpu_max = 8, memory_mib_min = 4096, cpu_manufacturers = ["intel", "amd"] }
    purchase_options      = { on_demand_base_capacity = 1, on_demand_percentage_above_base_capacity = 0 }
  }

  assert {
    condition = alltrue([
      length(aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override) == 1,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override[0].instance_type == null,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override[0].instance_requirements[0].vcpu_count[0].min == 2,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override[0].instance_requirements[0].memory_mib[0].max == null,
      aws_autoscaling_group.this[0].mixed_instances_policy[0].launch_template[0].override[0].instance_requirements[0].burstable_performance == "excluded",
    ])
    error_message = "one requirements override, current-generation non-burstable types by default, with open-ended memory."
  }

  assert {
    condition     = output.governance.instance_selection == "attribute-based"
    error_message = "governance records attribute-based selection."
  }
}

run "a_maintenance_policy_launches_before_it_terminates" {
  command = plan

  variables {
    instance_maintenance_policy    = { min_healthy_percentage = 100, max_healthy_percentage = 110 }
    availability_zone_distribution = "balanced-only"
    max_instance_lifetime          = 604800
  }

  assert {
    condition = alltrue([
      aws_autoscaling_group.this[0].instance_maintenance_policy[0].min_healthy_percentage == 100,
      aws_autoscaling_group.this[0].instance_maintenance_policy[0].max_healthy_percentage == 110,
      aws_autoscaling_group.this[0].availability_zone_distribution[0].capacity_distribution_strategy == "balanced-only",
      aws_autoscaling_group.this[0].max_instance_lifetime == 604800,
    ])
    error_message = "maintenance, AZ distribution and instance lifetime reach the group."
  }
}

run "aws_6_options_reach_the_template_and_the_group" {
  command = plan

  variables {
    instance_type                  = "m7i.large"
    bandwidth_weighting            = "ebs-1"
    cpu_options                    = { nested_virtualization = "enabled" }
    placement_group                = "pg-0123456789abcdef0"
    availability_zone_distribution = "reservations-then-balanced"
  }

  assert {
    condition = alltrue([
      aws_launch_template.this[0].network_performance_options[0].bandwidth_weighting == "ebs-1",
      aws_launch_template.this[0].cpu_options[0].nested_virtualization == "enabled",
      aws_launch_template.this[0].placement[0].group_id == "pg-0123456789abcdef0",
      aws_launch_template.this[0].placement[0].group_name == null,
      aws_autoscaling_group.this[0].availability_zone_distribution[0].capacity_distribution_strategy == "reservations-then-balanced",
    ])
    error_message = "bandwidth weighting, nested virtualization, a placement group by ID and reservation-first AZ distribution are sent as asked."
  }
}

run "an_abandoned_drain_can_retain_the_instance" {
  command = plan

  variables {
    terminate_hook_abandon = "retain"
    lifecycle_hooks        = { drain = { transition = "TERMINATING" } }
    acknowledged_checks    = ["retained_instances_are_cleaned_up"]
  }

  assert {
    condition     = aws_autoscaling_group.this[0].instance_lifecycle_policy[0].retention_triggers[0].terminate_hook_abandon == "retain"
    error_message = "an instance whose drain hook abandons is retained for investigation."
  }

  assert {
    condition     = output.governance.terminate_hook_abandon == "retain" && output.verify_commands.terminate_retained != ""
    error_message = "a reviewer sees the retention, and the operator is given the command that ends it."
  }
}

# ---------------------------------------------------------------------------
# Hooks
# ---------------------------------------------------------------------------

run "hooks_are_separate_unless_they_must_see_the_first_instances" {
  command = plan

  variables {
    lifecycle_hooks = {
      register = { transition = "LAUNCHING", initial = true, heartbeat_timeout = 600 }
      drain    = { transition = "TERMINATING", default_result = "CONTINUE" }
    }
  }

  assert {
    condition     = [for h in aws_autoscaling_group.this[0].initial_lifecycle_hook : h.name] == ["register"]
    error_message = "only the initial hook is on the group, where changing it replaces the group."
  }

  assert {
    condition     = keys(aws_autoscaling_lifecycle_hook.this) == ["drain"] && aws_autoscaling_lifecycle_hook.this["drain"].lifecycle_transition == "autoscaling:EC2_INSTANCE_TERMINATING"
    error_message = "every other hook is its own resource, updated in place."
  }

  assert {
    condition     = jsonencode(output.governance.initial_lifecycle_hooks) == jsonencode(["register"])
    error_message = "a reviewer sees which hooks would replace the group when edited."
  }
}

# ---------------------------------------------------------------------------
# IAM
# ---------------------------------------------------------------------------

run "the_instance_role_allows_session_manager_and_what_the_caller_adds" {
  command = plan

  variables {
    instance_profile = {
      policies         = { read-config = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":\"ssm:GetParameter\",\"Resource\":\"*\"}]}" }
      managed_policies = { cw = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
    }
  }

  assert {
    condition     = { for k, a in aws_iam_role_policy_attachment.this : k => a.policy_arn } == { ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", cw = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
    error_message = "Session Manager is attached under the key ssm, next to the caller's policies."
  }

  assert {
    condition     = keys(aws_iam_role_policy.inline) == ["read-config"] && jsondecode(aws_iam_role.this[0].assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" }
    error_message = "inline policies are keyed by name, and the role trusts EC2."
  }
}

run "a_supplied_instance_profile_is_used_and_no_role_is_made" {
  command = plan

  variables {
    instance_profile = { create = false, name = "platform-ec2" }
  }

  assert {
    condition     = alltrue([length(aws_iam_role.this) == 0, aws_launch_template.this[0].iam_instance_profile[0].name == "platform-ec2"])
    error_message = "create = false launches with the named profile and creates no role."
  }

  assert {
    condition     = output.deployer_requirements.passes_a_supplied_profile != null
    error_message = "the deployer is told to pass the supplied profile's role."
  }
}

# ---------------------------------------------------------------------------
# Scaling
# ---------------------------------------------------------------------------

run "scaling_policies_track_predefined_and_custom_metrics_and_forecast" {
  command = plan

  variables {
    target_tracking_policies = {
      cpu     = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 55 }
      backlog = { target_value = 100, customized = { namespace = "AWS/SQS", metric_name = "ApproximateNumberOfMessagesVisible", dimensions = { QueueName = "orders" } } }
    }
    predictive_scaling  = { enabled = true, metric = "cpu", target_value = 55 }
    scheduled_actions   = { night = { min_size = 1, recurrence = "0 20 * * *", time_zone = "Europe/London" } }
    acknowledged_checks = ["fleet_survives_an_az"]
  }

  assert {
    condition     = aws_autoscaling_policy.target_tracking["cpu"].target_tracking_configuration[0].predefined_metric_specification[0].predefined_metric_type == "ASGAverageCPUUtilization"
    error_message = "a predefined metric is tracked."
  }

  assert {
    condition     = aws_autoscaling_policy.target_tracking["backlog"].target_tracking_configuration[0].customized_metric_specification[0].metric_dimension[0].value == "orders"
    error_message = "a customized metric keeps its dimensions."
  }

  assert {
    condition     = aws_autoscaling_policy.predictive[0].predictive_scaling_configuration[0].mode == "ForecastOnly" && aws_autoscaling_policy.predictive[0].predictive_scaling_configuration[0].metric_specification[0].predefined_metric_pair_specification[0].predefined_metric_type == "ASGCPUUtilization"
    error_message = "predictive scaling starts by forecasting only, on the CPU metric pair."
  }

  assert {
    condition     = aws_autoscaling_schedule.this["night"].min_size == 1 && aws_autoscaling_schedule.this["night"].max_size == -1 && aws_autoscaling_schedule.this["night"].time_zone == "Europe/London"
    error_message = "a scheduled action changes only what it names (-1 leaves a bound alone), in its time zone."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.in_service_low[0].threshold == 1
    error_message = "the in-service alarm fires below the lowest count the schedule allows, not the daytime minimum."
  }
}

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

run "alarms_and_events_reach_the_topic" {
  command = plan

  assert {
    condition     = aws_cloudwatch_metric_alarm.in_service_low[0].treat_missing_data == "breaching" && aws_cloudwatch_metric_alarm.in_service_low[0].threshold == 2
    error_message = "the in-service alarm fires below min_size, and on silence."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.cpu_high[0].alarm_actions == toset(["arn:aws:sns:eu-west-2:111122223333:alerts"])
    error_message = "alarms notify the topic."
  }

  assert {
    condition     = toset(keys(aws_cloudwatch_event_rule.this)) == toset(["launch-failed", "terminate-failed", "refresh-failed"])
    error_message = "failed launches, terminations and refreshes each have a rule."
  }

  assert {
    condition     = aws_cloudwatch_event_target.this["launch-failed"].arn == "arn:aws:sns:eu-west-2:111122223333:alerts"
    error_message = "the rules publish to the topic."
  }
}

run "no_in_service_alarm_without_the_metric" {
  command = plan

  variables {
    enabled_metrics = []
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.in_service_low) == 0 && length(aws_cloudwatch_metric_alarm.cpu_high) == 1
    error_message = "without GroupInServiceInstances the alarm would always be in ALARM, so it is not created."
  }
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

run "the_volume_key_admits_the_service_linked_role" {
  command = plan

  assert {
    condition = jsonencode([for r in output.kms_key_policy_requirements : [r.sid, r.principals.arns, r.actions] if startswith(r.sid, "AutoScaling")]) == jsonencode([
      ["AutoScalingVolumes", ["arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"], ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]],
      ["AutoScalingVolumeGrants", ["arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"], ["kms:CreateGrant"]],
    ])
    error_message = "the key owner is asked for exactly AWS's documented grants to the service-linked role."
  }

  assert {
    condition = alltrue([for r in output.kms_key_policy_requirements : alltrue([
      can(regex("^[A-Za-z0-9]+$", r.sid)), can(r.principals.services), can(r.principals.arns), can(r.principals.roles), length(r.actions) > 0, length(r.purpose) > 0,
      alltrue([for c in r.conditions : can(c.test) ? (can(c.variable) ? can(c.values) : false) : false]),
    ])])
    error_message = "every entry is contract v2."
  }
}

run "a_custom_suffix_service_linked_role_gets_the_key_instead" {
  command = plan

  variables {
    service_linked_role_arn = "arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling_orders"
  }

  assert {
    condition     = aws_autoscaling_group.this[0].service_linked_role_arn == "arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling_orders"
    error_message = "the group launches with the custom role."
  }

  assert {
    condition     = one([for r in output.kms_key_policy_requirements : r.principals.arns if r.sid == "AutoScalingVolumes"]) == tolist(["arn:aws:iam::111122223333:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling_orders"])
    error_message = "the key owner is asked to admit only that role."
  }
}

run "the_deployer_and_the_network_are_told_what_they_need" {
  command = plan

  assert {
    condition     = jsonencode(jsondecode(output.deployer_requirements.iam_policy).Statement[0].Action) == jsonencode(["ec2:RunInstances", "ec2:CreateTags"])
    error_message = "creating a group from a template is authorized as RunInstances and CreateTags."
  }

  assert {
    condition     = jsondecode(output.deployer_requirements.iam_policy).Statement[1].Resource == "arn:aws:iam::111122223333:role/orders-*"
    error_message = "PassRole names the instance role by its prefix, so the policy is known before the role exists."
  }

  assert {
    condition     = jsonencode(output.network_contract.session_manager_interface_endpoints) == jsonencode(["com.amazonaws.eu-west-2.ssm", "com.amazonaws.eu-west-2.ssmmessages", "com.amazonaws.eu-west-2.ec2messages"])
    error_message = "the network team is given the Session Manager endpoints."
  }

  assert {
    condition     = length(output.notification_requirements.topic_policy_statements) == 2
    error_message = "the topic owner is asked to admit CloudWatch and EventBridge."
  }
}

# ---------------------------------------------------------------------------
# create = false
# ---------------------------------------------------------------------------

run "create_false_plans_nothing_and_outputs_nothing" {
  command = plan

  variables {
    create                   = false
    ami                      = ""
    ami_ssm_parameter        = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
    target_tracking_policies = { cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 55 } }
    lifecycle_hooks          = { drain = { transition = "TERMINATING" } }
  }

  assert {
    condition = alltrue([
      length(aws_launch_template.this) == 0, length(aws_autoscaling_group.this) == 0, length(aws_autoscaling_group.static) == 0,
      length(aws_iam_role.this) == 0, length(aws_iam_instance_profile.this) == 0, length(aws_iam_role_policy_attachment.this) == 0,
      length(aws_autoscaling_policy.target_tracking) == 0, length(aws_autoscaling_lifecycle_hook.this) == 0,
      length(aws_cloudwatch_metric_alarm.cpu_high) == 0, length(aws_cloudwatch_event_rule.this) == 0,
      length(data.aws_ssm_parameter.ami) == 0, length(data.aws_region.current) == 0,
    ])
    error_message = "create = false plans no resources and reads no data sources."
  }

  assert {
    condition = alltrue([
      output.autoscaling_group_arn == null, output.autoscaling_group_name == null, output.launch_template_id == null,
      output.iam_role_arn == null, output.instance_profile_name == null, output.governance == null,
      output.kms_key_policy_requirements == null, output.notification_requirements == null, output.deployer_requirements == null,
      output.network_contract == null, output.verify_commands == null, length(output.target_tracking_policy_arns) == 0,
      length(output.cloudwatch_alarm_names) == 0, output.predictive_scaling_policy_arn == null,
    ])
    error_message = "create = false leaves every output null or empty."
  }
}
