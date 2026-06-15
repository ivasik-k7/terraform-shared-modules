# Full-stack apply test using a mocked AWS provider, so the entire resource
# graph (volumes, attachments, KMS, DLM + IAM role, alarms) is created offline
# with no real AWS account or credentials. Run with: terraform test

mock_provider "aws" {
  # aws_iam_policy_document is a pure-computation data source; give the mock a
  # valid JSON value so resources consuming .json (KMS key, IAM role) apply.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Computed ARNs feed into ARN-validated arguments (kms_key_id,
  # execution_role_arn), so the mocks must produce well-formed ARNs.
  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/abcd1234-ab12-cd34-ef56-1234567890ab"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-dlm-role"
    }
  }
}

run "full_stack_apply" {
  command = apply

  variables {
    name              = "test"
    availability_zone = "us-east-1a"

    create_kms_key                = true
    kms_key_additional_principals = ["arn:aws:iam::123456789012:role/ecs-instance"]

    create_lifecycle_policy  = true
    create_cloudwatch_alarms = true

    volumes = {
      data = { size = 100, type = "gp3", instance_id = "i-aaaa1111", device_name = "/dev/sdf" }
      logs = { size = 500, type = "st1" }
      shared = {
        size                 = 200
        type                 = "io2"
        iops                 = 10000
        multi_attach_enabled = true
        attachments = [
          { instance_id = "i-aaaa1111", device_name = "/dev/sdg" },
          { instance_id = "i-bbbb2222", device_name = "/dev/sdg" },
        ]
      }
    }
  }

  assert {
    condition     = length(aws_ebs_volume.this) == 3
    error_message = "Expected 3 EBS volumes"
  }

  assert {
    condition     = length(aws_volume_attachment.this) == 3
    error_message = "Expected 3 attachments (data:1 + shared:2)"
  }

  assert {
    condition     = length(aws_kms_key.ebs) == 1 && length(aws_kms_alias.ebs) == 1
    error_message = "Expected a created CMK and alias"
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.this) == 1 && length(aws_iam_role.dlm) == 1
    error_message = "Expected a DLM policy and its IAM role"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.burst_balance) == 1
    error_message = "BurstBalance alarm should exist only for the st1 volume"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.idle) == 3
    error_message = "Idle alarm should exist for every volume"
  }
}

# Minimal apply: no optional resources are created when toggles are off.
run "minimal_apply_creates_nothing_extra" {
  command = apply

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 50, type = "gp3" }
    }
  }

  assert {
    condition     = length(aws_kms_key.ebs) == 0
    error_message = "No CMK should be created by default"
  }

  assert {
    condition     = length(aws_dlm_lifecycle_policy.this) == 0
    error_message = "No DLM policy should be created by default"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.idle) == 0
    error_message = "No alarms should be created by default"
  }
}
