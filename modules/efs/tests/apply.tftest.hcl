# Full-stack apply test using a mocked AWS provider, so the entire resource
# graph (file system, mount targets, security group + rules, backup policy,
# access points, file system policy, alarms, replication) is created offline
# with no real AWS account. Run with: terraform test

mock_provider "aws" {
  # aws_iam_policy_document is pure computation; give the mock valid JSON so the
  # generated TLS file-system policy applies.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_efs_file_system" {
    defaults = {
      arn = "arn:aws:elasticfilesystem:us-east-1:123456789012:file-system/fs-mock123"
      id  = "fs-mock123"
    }
  }
}

# --- Comprehensive file system with most features enabled --------------------
run "full_stack_apply" {
  command = apply

  variables {
    name       = "test"
    subnet_ids = ["subnet-aaaa1111", "subnet-bbbb2222"]

    encrypted        = true
    throughput_mode  = "bursting"
    performance_mode = "generalPurpose"

    create_security_group      = true
    vpc_id                     = "vpc-12345678"
    allowed_cidr_blocks        = ["10.0.0.0/16"]
    allowed_ipv6_cidr_blocks   = ["2600:1f18::/32"]
    allowed_security_group_ids = ["sg-aaaa1111"]

    enforce_in_transit_encryption = true
    enable_backup_policy          = true

    lifecycle_policy_transition_to_ia      = "AFTER_30_DAYS"
    lifecycle_policy_transition_to_archive = "AFTER_90_DAYS"

    access_points = {
      app = {
        posix_user = { gid = 1000, uid = 1000 }
        root_directory = {
          path          = "/app"
          creation_info = { owner_gid = 1000, owner_uid = 1000, permissions = "0755" }
        }
      }
      data = {
        posix_user = { gid = 2000, uid = 2000 }
      }
    }

    create_cloudwatch_alarms = true

    tags = {
      Environment = "test"
      Service     = "efs"
    }
  }

  assert {
    condition     = length(aws_efs_mount_target.this) == 2
    error_message = "Expected two mount targets"
  }

  assert {
    condition     = length(aws_security_group.efs) == 1
    error_message = "Expected one security group"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_security_group) == 1
    error_message = "Expected one source-SG ingress rule"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_ipv6_cidr) == 1
    error_message = "Expected one IPv6 ingress rule"
  }

  assert {
    condition     = length(aws_efs_backup_policy.this) == 1
    error_message = "Expected a backup policy"
  }

  assert {
    condition     = length(aws_efs_access_point.this) == 2
    error_message = "Expected two access points"
  }

  assert {
    condition     = length(aws_efs_file_system_policy.this) == 1
    error_message = "Expected a generated TLS file system policy"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.burst_credit_balance) == 1 && length(aws_cloudwatch_metric_alarm.percent_io_limit) == 1
    error_message = "Expected both CloudWatch alarms"
  }
}

# --- Minimal apply: no optional resources are created ------------------------
run "minimal_apply_creates_nothing_extra" {
  command = apply

  variables {
    name                 = "test-min"
    subnet_ids           = ["subnet-aaaa1111"]
    enable_backup_policy = false
  }

  assert {
    condition     = length(aws_security_group.efs) == 0
    error_message = "No security group by default"
  }

  assert {
    condition     = length(aws_efs_backup_policy.this) == 0
    error_message = "No backup policy when disabled"
  }

  assert {
    condition     = length(aws_efs_file_system_policy.this) == 0
    error_message = "No file system policy by default"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.burst_credit_balance) == 0
    error_message = "No alarms by default"
  }
}

# --- Replication configuration applies ---------------------------------------
run "replication_apply" {
  command = apply

  variables {
    name       = "test-repl"
    subnet_ids = ["subnet-aaaa1111"]
    replication_configuration = {
      region = "us-west-2"
    }
  }

  assert {
    condition     = length(aws_efs_replication_configuration.this) == 1
    error_message = "A replication configuration should be created"
  }
}
