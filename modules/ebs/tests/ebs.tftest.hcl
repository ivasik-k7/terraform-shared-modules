# Native `terraform test` suite for the EBS module.
# Uses plan-only runs with a mock-friendly provider so no real AWS resources or
# credentials are required. Run with: terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Happy path: a single gp3 volume plans cleanly ----------------------------
run "single_gp3_volume" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 100, type = "gp3" }
    }
  }

  assert {
    condition     = aws_ebs_volume.this["data"].type == "gp3"
    error_message = "Volume type should be gp3"
  }

  assert {
    condition     = aws_ebs_volume.this["data"].encrypted == true
    error_message = "Volumes must be encrypted by default"
  }

  assert {
    condition     = length(aws_volume_attachment.this) == 0
    error_message = "No attachment should be created without instance_id"
  }
}

# --- Multi-Attach: two attachments are produced for one io2 volume ------------
run "multi_attach_flattening" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
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
    condition     = length(aws_volume_attachment.this) == 2
    error_message = "Both Multi-Attach targets should produce attachments"
  }
}

# --- Validation: io1/io2 require iops -----------------------------------------
run "io2_requires_iops" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      bad = { size = 100, type = "io2" }
    }
  }

  expect_failures = [var.volumes]
}

# --- Validation: throughput only valid for gp3 --------------------------------
run "throughput_requires_gp3" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      bad = { size = 100, type = "gp2", throughput = 250 }
    }
  }

  expect_failures = [var.volumes]
}

# --- Validation: multi-instance attach requires io1/io2 + multi_attach --------
run "multi_attach_requires_io" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      bad = {
        size = 100
        type = "gp3"
        attachments = [
          { instance_id = "i-aaaa1111", device_name = "/dev/sdf" },
          { instance_id = "i-bbbb2222", device_name = "/dev/sdg" },
        ]
      }
    }
  }

  expect_failures = [var.volumes]
}

# --- Precondition: missing AZ surfaces a clear error --------------------------
run "missing_az_fails" {
  command = plan

  variables {
    name = "test"
    volumes = {
      data = { size = 100, type = "gp3" }
    }
  }

  expect_failures = [aws_ebs_volume.this]
}

# --- Validation: same instance attached twice is rejected ---------------------
run "duplicate_instance_attachment_fails" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      bad = {
        size                 = 100
        type                 = "io2"
        iops                 = 5000
        multi_attach_enabled = true
        instance_id          = "i-aaaa1111"
        device_name          = "/dev/sdf"
        attachments = [
          { instance_id = "i-aaaa1111", device_name = "/dev/sdg" },
        ]
      }
    }
  }

  expect_failures = [var.volumes]
}

# --- Validation: st1/sc1 minimum size -----------------------------------------
run "st1_min_size_fails" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      bad = { size = 50, type = "st1" }
    }
  }

  expect_failures = [var.volumes]
}

# --- Validation: invalid DLM interval -----------------------------------------
run "invalid_dlm_interval_fails" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 100, type = "gp3" }
    }
    snapshot_schedules = {
      bad = { interval = 5, times = ["03:00"], retain_count = 7 }
    }
  }

  expect_failures = [var.snapshot_schedules]
}

# --- Precondition: lifecycle policy without an available role -----------------
run "lifecycle_without_role_fails" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 100, type = "gp3" }
    }
    create_lifecycle_policy = true
    create_dlm_role         = false
    dlm_role_arn            = null
  }

  expect_failures = [aws_dlm_lifecycle_policy.this]
}

# --- Precondition: lifecycle policy with no schedules -------------------------
run "lifecycle_without_schedules_fails" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 100, type = "gp3" }
    }
    create_lifecycle_policy = true
    snapshot_schedules      = {}
  }

  expect_failures = [aws_dlm_lifecycle_policy.this]
}

# --- Attachment keys stay known at plan time (index-based, not instance_id) ---
# Keying by index means attachment for_each does not depend on instance_id,
# which can be a computed value. The map key here is "data.0".
run "attachment_keyed_by_index" {
  command = plan

  variables {
    name              = "test"
    availability_zone = "us-east-1a"
    volumes = {
      data = { size = 100, type = "gp3", instance_id = "i-aaaa1111", device_name = "/dev/sdf" }
    }
  }

  assert {
    condition     = contains(keys(aws_volume_attachment.this), "data.0")
    error_message = "Attachment should be keyed by <volume>.<index>"
  }
}
