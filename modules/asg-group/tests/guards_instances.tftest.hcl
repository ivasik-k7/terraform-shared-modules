# Every validation of identity, network, image, instance shape, storage and role, with the input that trips it.
# expect_failures names the exact address: var.x for a validation, the
# resource for a precondition, check.x for a check. The baseline is fully
# configured, so each run changes only what it needs to trip one guard.

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

run "the_baseline_passes_every_guard" {
  command = plan
}

run "a_name_too_long_for_the_role_prefix_is_rejected" {
  command = plan

  variables {
    name = "a-fleet-name-that-is-much-too-long-xyz"
  }

  expect_failures = [var.name]
}

run "a_reserved_tag_prefix_is_rejected" {
  command = plan

  variables {
    tags = { "aws:owner" = "x" }
  }

  expect_failures = [var.tags]
}

run "an_unknown_acknowledged_check_is_rejected" {
  command = plan

  variables {
    acknowledged_checks = ["no_such_check"]
  }

  expect_failures = [var.acknowledged_checks]
}

run "no_subnets_are_rejected" {
  command = plan

  variables {
    subnet_ids = []
  }

  expect_failures = [var.subnet_ids]
}

run "a_subnet_that_is_not_an_id_is_rejected" {
  command = plan

  variables {
    subnet_ids = ["private-a"]
  }

  expect_failures = [var.subnet_ids]
}

run "no_security_groups_are_rejected" {
  command = plan

  variables {
    security_group_ids = []
  }

  expect_failures = [var.security_group_ids]
}

run "an_unknown_public_ip_mode_is_rejected" {
  command = plan

  variables {
    public_ip = "yes"
  }

  expect_failures = [var.public_ip]
}

run "an_unknown_az_distribution_is_rejected" {
  command = plan

  variables {
    availability_zone_distribution = "spread"
  }

  expect_failures = [var.availability_zone_distribution]
}

run "an_ami_that_is_not_an_id_is_rejected" {
  command = plan

  variables {
    ami = "amazon-linux"
  }

  expect_failures = [var.ami]
}

run "both_ami_and_ssm_parameter_are_rejected" {
  command = plan

  variables {
    ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  }

  expect_failures = [var.ami_ssm_parameter]
}

run "neither_ami_nor_ssm_parameter_is_rejected" {
  command = plan

  variables {
    ami = ""
  }

  expect_failures = [var.ami_ssm_parameter]
}

run "an_ssm_parameter_that_is_not_a_path_is_rejected" {
  command = plan

  variables {
    ami               = ""
    ami_ssm_parameter = "golden-ami"
  }

  expect_failures = [var.ami_ssm_parameter]
}

run "an_instance_type_that_is_not_a_type_is_rejected" {
  command = plan

  variables {
    instance_type = "large"
  }

  expect_failures = [var.instance_type]
}

run "an_instance_types_entry_that_is_not_a_type_is_rejected" {
  command = plan

  variables {
    instance_types = ["m7i"]
  }

  expect_failures = [var.instance_types]
}

run "a_zero_weight_is_rejected" {
  command = plan

  variables {
    instance_weights = { "t3.medium" = 0 }
  }

  expect_failures = [var.instance_weights]
}

run "instance_requirements_with_max_below_min_are_rejected" {
  command = plan

  variables {
    instance_requirements = { vcpu_min = 4, vcpu_max = 2 }
  }

  expect_failures = [var.instance_requirements]
}

run "instance_requirements_allowing_and_excluding_types_are_rejected" {
  command = plan

  variables {
    instance_requirements = { vcpu_min = 2, allowed_instance_types = ["m7i.*"], excluded_instance_types = ["t3.*"] }
  }

  expect_failures = [var.instance_requirements]
}

run "user_data_in_both_forms_is_rejected" {
  command = plan

  variables {
    user_data        = "echo hi"
    user_data_base64 = "ZWNobyBoaQ=="
  }

  expect_failures = [var.user_data_base64]
}

run "user_data_base64_that_is_not_base64_is_rejected" {
  command = plan

  variables {
    user_data_base64 = "not base64!"
  }

  expect_failures = [var.user_data_base64]
}

run "a_hop_limit_of_zero_is_rejected" {
  command = plan

  variables {
    metadata_hop_limit = 0
  }

  expect_failures = [var.metadata_hop_limit]
}

run "an_unknown_credit_mode_is_rejected" {
  command = plan

  variables {
    cpu_credits = "burst"
  }

  expect_failures = [var.cpu_credits]
}

run "an_unknown_auto_recovery_is_rejected" {
  command = plan

  variables {
    auto_recovery = "on"
  }

  expect_failures = [var.auto_recovery]
}

run "an_unknown_ebs_optimized_value_is_rejected" {
  command = plan

  variables {
    ebs_optimized = "yes"
  }

  expect_failures = [var.ebs_optimized]
}

run "an_unknown_tenancy_is_rejected" {
  command = plan

  variables {
    tenancy = "shared"
  }

  expect_failures = [var.tenancy]
}

run "three_threads_per_core_are_rejected" {
  command = plan

  variables {
    cpu_options = { threads_per_core = 3 }
  }

  expect_failures = [var.cpu_options]
}

run "an_unknown_nested_virtualization_value_is_rejected" {
  command = plan

  variables {
    cpu_options = { nested_virtualization = "on" }
  }

  expect_failures = [var.cpu_options]
}

run "an_unknown_bandwidth_weighting_is_rejected" {
  command = plan

  variables {
    bandwidth_weighting = "network"
  }

  expect_failures = [var.bandwidth_weighting]
}

run "a_reservation_preference_with_a_target_is_rejected" {
  command = plan

  variables {
    capacity_reservation = { preference = "open", reservation_ids = ["cr-0123456789abcdef0"] }
  }

  expect_failures = [var.capacity_reservation]
}

run "throughput_on_an_io2_root_is_rejected" {
  command = plan

  variables {
    root_volume = { type = "io2", throughput = 250 }
  }

  expect_failures = [var.root_volume]
}

run "an_extra_volume_on_the_root_device_is_rejected" {
  command = plan

  variables {
    ebs_volumes = { "/dev/xvda" = {} }
  }

  expect_failures = [var.ebs_volumes]
}

run "iops_on_an_st1_volume_are_rejected" {
  command = plan

  variables {
    ebs_volumes = { "/dev/sdf" = { type = "st1", iops = 500 } }
  }

  expect_failures = [var.ebs_volumes]
}

run "a_key_that_is_not_a_key_arn_is_rejected" {
  command = plan

  variables {
    kms_key_arn = "alias/ebs"
  }

  expect_failures = [var.kms_key_arn]
}

run "a_service_linked_role_of_another_service_is_rejected" {
  command = plan

  variables {
    service_linked_role_arn = "arn:aws:iam::111122223333:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
  }

  expect_failures = [var.service_linked_role_arn]
}

run "a_profile_name_without_create_false_is_rejected" {
  command = plan

  variables {
    instance_profile = { name = "platform-ec2" }
  }

  expect_failures = [var.instance_profile]
}

run "policies_on_a_supplied_profile_are_rejected" {
  command = plan

  variables {
    instance_profile = { create = false, name = "platform-ec2", managed_policies = { x = "arn:aws:iam::aws:policy/ReadOnlyAccess" } }
  }

  expect_failures = [var.instance_profile]
}

run "an_inline_policy_name_with_spaces_is_rejected" {
  command = plan

  variables {
    instance_profile = { policies = { "read config" = "{}" } }
  }

  expect_failures = [var.instance_profile]
}

run "a_boundary_that_is_not_a_policy_is_rejected" {
  command = plan

  variables {
    permissions_boundary_arn = "boundary"
  }

  expect_failures = [var.permissions_boundary_arn]
}
