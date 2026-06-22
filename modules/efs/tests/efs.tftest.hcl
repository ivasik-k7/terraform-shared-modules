# Native `terraform test` suite for the EFS module (plan-only).
# Uses a credential-free provider so no real AWS resources or credentials are
# required. Exercises happy-path planning and every input validation.
# Run with: terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Happy path: a basic encrypted file system plans cleanly -----------------
run "basic_file_system" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = aws_efs_file_system.this.encrypted == true
    error_message = "File system should be encrypted by default"
  }

  assert {
    condition     = aws_efs_file_system.this.performance_mode == "generalPurpose"
    error_message = "Default performance mode should be generalPurpose"
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 2
    error_message = "One mount target should be planned per subnet"
  }

  assert {
    condition     = aws_efs_file_system.this.creation_token == "test"
    error_message = "creation_token should default to name"
  }

  assert {
    condition     = length(aws_efs_backup_policy.this) == 1
    error_message = "Backup policy should be enabled by default"
  }
}

# --- No subnets means no mount targets ---------------------------------------
run "no_mount_targets" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = []
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 0
    error_message = "No mount targets should be created without subnets"
  }
}

# --- Created security group + IPv4/IPv6 ingress ------------------------------
run "security_group_with_rules" {
  command = plan

  variables {
    name                       = "test"
    subnet_ids                 = ["subnet-aaaa1111"]
    create_security_group      = true
    vpc_id                     = "vpc-12345678"
    allowed_cidr_blocks        = ["10.0.0.0/16"]
    allowed_ipv6_cidr_blocks   = ["2600:1f18::/32"]
    allowed_security_group_ids = ["sg-aaaa1111", "sg-bbbb2222"]
  }

  assert {
    condition     = length(aws_security_group.efs) == 1
    error_message = "A security group should be created"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) == 1
    error_message = "One IPv4 ingress rule per CIDR should be planned"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_ipv6_cidr) == 1
    error_message = "One IPv6 ingress rule per CIDR should be planned"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_security_group) == 2
    error_message = "One ingress rule per allowed security group should be planned"
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.allow_all) == 1
    error_message = "An egress rule should be planned"
  }
}

# --- Provisioned throughput is forwarded -------------------------------------
run "provisioned_throughput" {
  command = plan

  variables {
    name                            = "test"
    subnet_ids                      = ["subnet-aaaa1111"]
    throughput_mode                 = "provisioned"
    provisioned_throughput_in_mibps = 128
  }

  assert {
    condition     = aws_efs_file_system.this.provisioned_throughput_in_mibps == 128
    error_message = "Provisioned throughput should be forwarded for provisioned mode"
  }
}

# --- Elastic throughput leaves provisioned throughput unset ------------------
run "elastic_throughput" {
  command = plan

  variables {
    name            = "test"
    subnet_ids      = ["subnet-aaaa1111"]
    throughput_mode = "elastic"
  }

  assert {
    condition     = aws_efs_file_system.this.provisioned_throughput_in_mibps == null
    error_message = "Provisioned throughput should be null for elastic mode"
  }
}

# --- Lifecycle policies are emitted ------------------------------------------
run "lifecycle_policies" {
  command = plan

  variables {
    name                                                 = "test"
    subnet_ids                                           = ["subnet-aaaa1111"]
    lifecycle_policy_transition_to_ia                    = "AFTER_30_DAYS"
    lifecycle_policy_transition_to_primary_storage_class = "AFTER_1_ACCESS"
    lifecycle_policy_transition_to_archive               = "AFTER_90_DAYS"
  }

  assert {
    condition     = length(aws_efs_file_system.this.lifecycle_policy) == 3
    error_message = "Three lifecycle policy blocks should be emitted"
  }
}

# --- Enforce-in-transit-encryption generates a policy ------------------------
run "enforce_tls_policy" {
  command = plan

  variables {
    name                          = "test"
    subnet_ids                    = ["subnet-aaaa1111"]
    enforce_in_transit_encryption = true
  }

  assert {
    condition     = length(aws_efs_file_system_policy.this) == 1
    error_message = "A file system policy should be created when enforcing TLS"
  }

  assert {
    condition     = length(data.aws_iam_policy_document.enforce_tls) == 1
    error_message = "The TLS policy document should be generated"
  }
}

# --- Access points are created -----------------------------------------------
run "access_points" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111"]
    access_points = {
      app = {
        posix_user = { gid = 1000, uid = 1000 }
        root_directory = {
          path          = "/app"
          creation_info = { owner_gid = 1000, owner_uid = 1000, permissions = "0755" }
        }
      }
    }
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 1
    error_message = "One access point should be planned"
  }
}

# --- CloudWatch alarms scale to mode/perf ------------------------------------
run "alarms_bursting_generalpurpose" {
  command = plan

  variables {
    name                     = "test"
    subnet_ids               = ["subnet-aaaa1111"]
    throughput_mode          = "bursting"
    performance_mode         = "generalPurpose"
    create_cloudwatch_alarms = true
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.burst_credit_balance) == 1
    error_message = "Burst credit balance alarm should exist for bursting mode"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.percent_io_limit) == 1
    error_message = "Percent IO limit alarm should exist for generalPurpose mode"
  }
}

run "alarms_elastic_maxio" {
  command = plan

  variables {
    name                     = "test"
    subnet_ids               = ["subnet-aaaa1111"]
    throughput_mode          = "elastic"
    performance_mode         = "maxIO"
    create_cloudwatch_alarms = true
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.burst_credit_balance) == 0
    error_message = "No burst credit alarm should exist outside bursting mode"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.percent_io_limit) == 0
    error_message = "No percent IO limit alarm should exist outside generalPurpose mode"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

# --- Invalid performance mode ------------------------------------------------
run "invalid_performance_mode_fails" {
  command = plan

  variables {
    name             = "test"
    subnet_ids       = ["subnet-aaaa1111"]
    performance_mode = "turbo"
  }

  expect_failures = [var.performance_mode]
}

# --- Invalid throughput mode -------------------------------------------------
run "invalid_throughput_mode_fails" {
  command = plan

  variables {
    name            = "test"
    subnet_ids      = ["subnet-aaaa1111"]
    throughput_mode = "fast"
  }

  expect_failures = [var.throughput_mode]
}

# --- Provisioned mode requires a throughput value ----------------------------
run "provisioned_without_value_fails" {
  command = plan

  variables {
    name            = "test"
    subnet_ids      = ["subnet-aaaa1111"]
    throughput_mode = "provisioned"
  }

  expect_failures = [var.provisioned_throughput_in_mibps]
}

# --- Provisioned throughput set in the wrong mode ----------------------------
run "provisioned_value_in_bursting_fails" {
  command = plan

  variables {
    name                            = "test"
    subnet_ids                      = ["subnet-aaaa1111"]
    throughput_mode                 = "bursting"
    provisioned_throughput_in_mibps = 128
  }

  expect_failures = [var.provisioned_throughput_in_mibps]
}

# --- KMS key without encryption ----------------------------------------------
run "kms_without_encryption_fails" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111"]
    encrypted  = false
    kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abcd"
  }

  expect_failures = [var.kms_key_id]
}

# --- Created security group without a VPC ------------------------------------
run "security_group_without_vpc_fails" {
  command = plan

  variables {
    name                  = "test"
    subnet_ids            = ["subnet-aaaa1111"]
    create_security_group = true
  }

  expect_failures = [var.vpc_id]
}

# --- Enforce TLS conflicts with an explicit policy ---------------------------
run "enforce_tls_and_explicit_policy_fails" {
  command = plan

  variables {
    name                          = "test"
    subnet_ids                    = ["subnet-aaaa1111"]
    enforce_in_transit_encryption = true
    file_system_policy            = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }

  expect_failures = [var.enforce_in_transit_encryption]
}

# --- Invalid lifecycle transition value --------------------------------------
run "invalid_lifecycle_ia_fails" {
  command = plan

  variables {
    name                              = "test"
    subnet_ids                        = ["subnet-aaaa1111"]
    lifecycle_policy_transition_to_ia = "AFTER_45_DAYS"
  }

  expect_failures = [var.lifecycle_policy_transition_to_ia]
}

# --- Invalid primary storage transition --------------------------------------
run "invalid_primary_transition_fails" {
  command = plan

  variables {
    name                                                 = "test"
    subnet_ids                                           = ["subnet-aaaa1111"]
    lifecycle_policy_transition_to_primary_storage_class = "AFTER_2_ACCESS"
  }

  expect_failures = [var.lifecycle_policy_transition_to_primary_storage_class]
}

# --- Name too long -----------------------------------------------------------
run "name_too_long_fails" {
  command = plan

  variables {
    name       = "this-name-is-way-too-long-to-be-used-as-an-efs-creation-token-aaaa"
    subnet_ids = ["subnet-aaaa1111"]
  }

  expect_failures = [var.name]
}

# --- Invalid percent IO limit threshold --------------------------------------
run "invalid_io_threshold_fails" {
  command = plan

  variables {
    name                             = "test"
    subnet_ids                       = ["subnet-aaaa1111"]
    alarm_percent_io_limit_threshold = 150
  }

  expect_failures = [var.alarm_percent_io_limit_threshold]
}

# --- mount_target_ip_addresses key not in subnet_ids -------------------------
run "mount_target_ip_unknown_subnet_fails" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111"]
    mount_target_ip_addresses = {
      "subnet-does-not-exist" = "10.0.1.10"
    }
  }

  expect_failures = [var.mount_target_ip_addresses]
}

# --- Access point with a non-octal permissions string -----------------------
run "access_point_bad_permissions_fails" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111"]
    access_points = {
      bad = {
        root_directory = {
          path          = "/bad"
          creation_info = { owner_gid = 1000, owner_uid = 1000, permissions = "999" }
        }
      }
    }
  }

  expect_failures = [var.access_points]
}

# --- Access point with an out-of-range uid -----------------------------------
run "access_point_bad_uid_fails" {
  command = plan

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111"]
    access_points = {
      bad = {
        posix_user = { gid = 1000, uid = 9999999999 }
      }
    }
  }

  expect_failures = [var.access_points]
}
