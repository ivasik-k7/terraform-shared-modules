# Native `terraform test` suite for the Aurora module (plan-only).
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

# --- Happy path: provisioned PostgreSQL cluster plans cleanly -----------------
run "provisioned_postgres_defaults" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = local.port == 5432
    error_message = "PostgreSQL should default to port 5432"
  }

  assert {
    condition     = aws_rds_cluster.main.engine_mode == "provisioned"
    error_message = "Engine mode should default to provisioned"
  }

  assert {
    condition     = local.subnet_group_name == "test-pg-subnet-group"
    error_message = "Subnet group name should derive from the cluster identifier"
  }

  assert {
    condition     = length(aws_db_subnet_group.main) == 1
    error_message = "A subnet group should be created by default"
  }

  assert {
    condition     = length(aws_rds_cluster_instance.instances) == 1
    error_message = "The default writer instance should be planned"
  }
}

# --- MySQL gets the right default port ----------------------------------------
run "mysql_default_port" {
  command = plan

  variables {
    cluster_identifier = "test-mysql"
    engine             = "aurora-mysql"
    engine_version     = "8.0"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = local.port == 3306
    error_message = "MySQL should default to port 3306"
  }
}

# --- Managed master password nulls out the static password -------------------
run "managed_master_password" {
  command = plan

  variables {
    cluster_identifier          = "test-pg"
    engine                      = "aurora-postgresql"
    engine_version              = "15.4"
    vpc_id                      = "vpc-12345678"
    subnet_ids                  = ["subnet-aaaa1111", "subnet-bbbb2222"]
    manage_master_user_password = true
  }

  assert {
    condition     = aws_rds_cluster.main.manage_master_user_password == true
    error_message = "manage_master_user_password should be forwarded to the cluster"
  }

  assert {
    condition     = aws_rds_cluster.main.master_password == null
    error_message = "master_password must be null when RDS manages the secret"
  }
}

# --- Bring-your-own subnet group skips creation ------------------------------
run "byo_subnet_group" {
  command = plan

  variables {
    cluster_identifier     = "test-pg"
    engine                 = "aurora-postgresql"
    engine_version         = "15.4"
    vpc_id                 = "vpc-12345678"
    create_db_subnet_group = false
    db_subnet_group_name   = "preexisting-subnet-group"
  }

  assert {
    condition     = length(aws_db_subnet_group.main) == 0
    error_message = "No subnet group should be created when reusing an existing one"
  }

  assert {
    condition     = local.db_subnet_group_name == "preexisting-subnet-group"
    error_message = "Cluster should attach to the provided subnet group"
  }
}

# --- Custom endpoints and role associations are planned ----------------------
run "custom_endpoints_and_roles" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    instances = {
      writer = { instance_class = "db.r6g.large", promotion_tier = 0 }
      reader = { instance_class = "db.r6g.large", promotion_tier = 1 }
    }
    cluster_endpoints = {
      analytics = { type = "READER", static_members = ["test-pg-reader"] }
    }
    iam_role_associations = {
      s3import = { role_arn = "arn:aws:iam::123456789012:role/aurora-s3", feature_name = "s3Import" }
    }
  }

  assert {
    condition     = length(aws_rds_cluster_endpoint.custom) == 1
    error_message = "One custom endpoint should be planned"
  }

  assert {
    condition     = aws_rds_cluster_endpoint.custom["analytics"].cluster_endpoint_identifier == "test-pg-analytics"
    error_message = "Custom endpoint identifier should be prefixed with the cluster identifier"
  }

  assert {
    condition     = length(aws_rds_cluster_role_association.this) == 1
    error_message = "One IAM role association should be planned"
  }
}

# --- BYO monitoring role: no role is created ---------------------------------
run "byo_monitoring_role" {
  command = plan

  variables {
    cluster_identifier  = "test-pg"
    engine              = "aurora-postgresql"
    engine_version      = "15.4"
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-aaaa1111", "subnet-bbbb2222"]
    monitoring_interval = 60
    monitoring_role_arn = "arn:aws:iam::123456789012:role/existing-monitoring"
  }

  assert {
    condition     = length(aws_iam_role.enhanced_monitoring) == 0
    error_message = "No monitoring role should be created when one is supplied"
  }

  assert {
    condition     = local.monitoring_role_arn == "arn:aws:iam::123456789012:role/existing-monitoring"
    error_message = "The supplied monitoring role ARN should be used"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

# --- Invalid cluster identifier ----------------------------------------------
run "invalid_cluster_identifier_fails" {
  command = plan

  variables {
    cluster_identifier = "1-bad-start"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  expect_failures = [var.cluster_identifier]
}

# --- Serverless mode requires a scaling configuration ------------------------
run "serverless_requires_scaling_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    engine_mode        = "serverless"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  expect_failures = [var.serverless_scaling_configuration]
}

# --- Backtrack window only valid for aurora-mysql ----------------------------
run "backtrack_postgres_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    backtrack_window   = 3600
  }

  expect_failures = [var.backtrack_window]
}

# --- Data API (HTTP endpoint) is allowed on a provisioned cluster ------------
run "http_endpoint_on_provisioned_ok" {
  command = plan

  variables {
    cluster_identifier   = "test-pg"
    engine               = "aurora-postgresql"
    engine_version       = "15.4"
    vpc_id               = "vpc-12345678"
    subnet_ids           = ["subnet-aaaa1111", "subnet-bbbb2222"]
    enable_http_endpoint = true
  }

  assert {
    condition     = aws_rds_cluster.main.enable_http_endpoint == true
    error_message = "Data API should be enableable on a provisioned cluster"
  }
}

# --- Parameter-group family is derived correctly per engine ------------------
run "parameter_group_family_postgres" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = local.cluster_parameter_group_family == "aurora-postgresql15"
    error_message = "PostgreSQL family should be aurora-postgresql<major>"
  }
}

run "parameter_group_family_mysql" {
  command = plan

  variables {
    cluster_identifier = "test-mysql"
    engine             = "aurora-mysql"
    engine_version     = "8.0"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = local.cluster_parameter_group_family == "aurora-mysql8.0"
    error_message = "MySQL family should be aurora-mysql<major>.<minor> (e.g. aurora-mysql8.0)"
  }

  assert {
    condition     = local.db_parameter_group_family == "aurora-mysql8.0"
    error_message = "MySQL DB parameter group family should also be aurora-mysql8.0"
  }
}

# --- Invalid storage type ----------------------------------------------------
run "invalid_storage_type_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    storage_type       = "io2"
  }

  expect_failures = [var.storage_type]
}

# --- Managed password conflicts with a static master password ----------------
run "managed_and_static_password_conflict_fails" {
  command = plan

  variables {
    cluster_identifier          = "test-pg"
    engine                      = "aurora-postgresql"
    engine_version              = "15.4"
    vpc_id                      = "vpc-12345678"
    subnet_ids                  = ["subnet-aaaa1111", "subnet-bbbb2222"]
    manage_master_user_password = true
    master_password             = "SuperSecret123"
  }

  expect_failures = [var.manage_master_user_password]
}

# --- Reusing a subnet group requires its name --------------------------------
run "byo_subnet_group_without_name_fails" {
  command = plan

  variables {
    cluster_identifier     = "test-pg"
    engine                 = "aurora-postgresql"
    engine_version         = "15.4"
    vpc_id                 = "vpc-12345678"
    create_db_subnet_group = false
  }

  expect_failures = [var.create_db_subnet_group]
}

# --- Activity stream requires a KMS key --------------------------------------
run "activity_stream_without_kms_fails" {
  command = plan

  variables {
    cluster_identifier     = "test-pg"
    engine                 = "aurora-postgresql"
    engine_version         = "15.4"
    vpc_id                 = "vpc-12345678"
    subnet_ids             = ["subnet-aaaa1111", "subnet-bbbb2222"]
    enable_activity_stream = true
  }

  expect_failures = [var.enable_activity_stream]
}

# --- Custom endpoint with an invalid type ------------------------------------
run "invalid_custom_endpoint_type_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    cluster_endpoints = {
      bad = { type = "WRITER" }
    }
  }

  expect_failures = [var.cluster_endpoints]
}

# --- Custom endpoint cannot set both member lists ----------------------------
run "custom_endpoint_both_member_lists_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    cluster_endpoints = {
      bad = { type = "READER", static_members = ["a"], excluded_members = ["b"] }
    }
  }

  expect_failures = [var.cluster_endpoints]
}

# --- A writer (promotion_tier 0) is required ---------------------------------
run "no_writer_instance_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    instances = {
      reader = { instance_class = "db.r6g.large", promotion_tier = 1 }
    }
  }

  expect_failures = [var.instances]
}

# --- Fewer than two subnets is rejected when creating a subnet group ---------
run "insufficient_subnets_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111"]
  }

  expect_failures = [var.subnet_ids]
}

# --- vpc_id is required when the module creates a security group --------------
run "missing_vpc_with_security_group_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  expect_failures = [var.vpc_id]
}

# ============================================================================
# FEATURE BEHAVIOUR (plan assertions)
# ============================================================================

# --- I/O-Optimized storage is accepted ---------------------------------------
run "io_optimized_storage_accepted" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    storage_type       = "aurora-iopt1"
  }

  assert {
    condition     = aws_rds_cluster.main.storage_type == "aurora-iopt1"
    error_message = "storage_type aurora-iopt1 should be forwarded to the cluster"
  }
}

# --- Serverless v2 runs on a provisioned cluster with a scaling block --------
run "serverless_v2_scaling_block" {
  command = plan

  variables {
    cluster_identifier = "test-sv2"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    serverless_scaling_configuration = {
      min_capacity = 0.5
      max_capacity = 16
    }
    instances = {
      writer = { instance_class = "db.serverless", promotion_tier = 0 }
    }
  }

  assert {
    condition     = aws_rds_cluster.main.engine_mode == "provisioned"
    error_message = "Serverless v2 should keep the provisioned engine mode"
  }

  assert {
    condition     = length(aws_rds_cluster.main.serverlessv2_scaling_configuration) == 1
    error_message = "A serverlessv2 scaling block should be emitted when a config is provided"
  }

  assert {
    condition     = aws_rds_cluster.main.serverlessv2_scaling_configuration[0].max_capacity == 16
    error_message = "Max capacity should match the supplied configuration"
  }
}

# --- Serverless v2 scale-to-zero honours seconds_until_auto_pause ------------
run "serverless_v2_scale_to_zero" {
  command = plan

  variables {
    cluster_identifier = "test-sv2-zero"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    serverless_scaling_configuration = {
      min_capacity             = 0
      max_capacity             = 8
      seconds_until_auto_pause = 900
    }
    instances = {
      writer = { instance_class = "db.serverless", promotion_tier = 0 }
    }
  }

  assert {
    condition     = aws_rds_cluster.main.serverlessv2_scaling_configuration[0].min_capacity == 0
    error_message = "min_capacity 0 (scale-to-zero) should be accepted"
  }

  assert {
    condition     = aws_rds_cluster.main.serverlessv2_scaling_configuration[0].seconds_until_auto_pause == 900
    error_message = "seconds_until_auto_pause should be honoured when min_capacity is 0"
  }
}

# --- A default final snapshot name is derived when not skipping --------------
run "final_snapshot_default_name" {
  command = plan

  variables {
    cluster_identifier  = "test-pg"
    engine              = "aurora-postgresql"
    engine_version      = "15.4"
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-aaaa1111", "subnet-bbbb2222"]
    skip_final_snapshot = false
  }

  assert {
    condition     = aws_rds_cluster.main.final_snapshot_identifier == "test-pg-final-snapshot"
    error_message = "Final snapshot name should default to '<cluster>-final-snapshot'"
  }
}

# --- Skipping the final snapshot nulls the snapshot name ----------------------
run "skip_final_snapshot_nulls_name" {
  command = plan

  variables {
    cluster_identifier  = "test-pg"
    engine              = "aurora-postgresql"
    engine_version      = "15.4"
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-aaaa1111", "subnet-bbbb2222"]
    skip_final_snapshot = true
  }

  assert {
    condition     = aws_rds_cluster.main.final_snapshot_identifier == null
    error_message = "No final snapshot name should be set when skip_final_snapshot is true"
  }
}

# --- Operational toggles are forwarded to the cluster ------------------------
run "operational_toggles_forwarded" {
  command = plan

  variables {
    cluster_identifier            = "test-pg"
    engine                        = "aurora-postgresql"
    engine_version                = "15.4"
    vpc_id                        = "vpc-12345678"
    subnet_ids                    = ["subnet-aaaa1111", "subnet-bbbb2222"]
    apply_immediately             = true
    allow_major_version_upgrade   = true
    enable_local_write_forwarding = true
    network_type                  = "DUAL"
    snapshot_identifier           = "arn:aws:rds:us-east-1:123456789012:cluster-snapshot:seed"
  }

  assert {
    condition     = aws_rds_cluster.main.apply_immediately == true
    error_message = "apply_immediately should be forwarded"
  }

  assert {
    condition     = aws_rds_cluster.main.network_type == "DUAL"
    error_message = "network_type should be forwarded"
  }

  assert {
    condition     = aws_rds_cluster.main.enable_local_write_forwarding == true
    error_message = "enable_local_write_forwarding should be forwarded"
  }

  assert {
    condition     = aws_rds_cluster.main.snapshot_identifier == "arn:aws:rds:us-east-1:123456789012:cluster-snapshot:seed"
    error_message = "snapshot_identifier should be forwarded for restore"
  }
}

# --- No security group means vpc_id can be omitted ---------------------------
run "no_security_group_without_vpc_ok" {
  command = plan

  variables {
    cluster_identifier     = "test-pg"
    engine                 = "aurora-postgresql"
    engine_version         = "15.4"
    subnet_ids             = ["subnet-aaaa1111", "subnet-bbbb2222"]
    create_security_group  = false
    vpc_security_group_ids = ["sg-existing01"]
  }

  assert {
    condition     = length(aws_security_group.aurora) == 0
    error_message = "No security group should be created when create_security_group is false"
  }
}

# --- Activity stream resource is planned when enabled ------------------------
run "activity_stream_enabled" {
  command = plan

  variables {
    cluster_identifier         = "test-pg"
    engine                     = "aurora-postgresql"
    engine_version             = "15.4"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-aaaa1111", "subnet-bbbb2222"]
    enable_activity_stream     = true
    activity_stream_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abcd"
    activity_stream_mode       = "sync"
  }

  assert {
    condition     = length(aws_rds_cluster_activity_stream.this) == 1
    error_message = "Activity stream should be planned when enabled"
  }

  assert {
    condition     = aws_rds_cluster_activity_stream.this[0].mode == "sync"
    error_message = "Activity stream mode should be forwarded"
  }
}

# ============================================================================
# ADDITIONAL VALIDATION FAILURES (edge cases)
# ============================================================================

# --- Serverless v2 min capacity below 0.5 ------------------------------------
run "serverless_min_capacity_too_low_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    serverless_scaling_configuration = {
      min_capacity = 0.1
      max_capacity = 4
    }
  }

  expect_failures = [var.serverless_scaling_configuration]
}

# --- Serverless v2 max capacity below min ------------------------------------
run "serverless_max_less_than_min_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    serverless_scaling_configuration = {
      min_capacity = 8
      max_capacity = 2
    }
  }

  expect_failures = [var.serverless_scaling_configuration]
}

# --- Invalid engine version format -------------------------------------------
run "invalid_engine_version_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "not-a-version"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  expect_failures = [var.engine_version]
}

# --- Weak master password ----------------------------------------------------
run "weak_master_password_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    master_password    = "weak"
  }

  expect_failures = [var.master_password]
}

# --- Invalid backup window format --------------------------------------------
run "invalid_backup_window_fails" {
  command = plan

  variables {
    cluster_identifier      = "test-pg"
    engine                  = "aurora-postgresql"
    engine_version          = "15.4"
    vpc_id                  = "vpc-12345678"
    subnet_ids              = ["subnet-aaaa1111", "subnet-bbbb2222"]
    preferred_backup_window = "2am-3am"
  }

  expect_failures = [var.preferred_backup_window]
}

# --- Invalid monitoring interval ---------------------------------------------
run "invalid_monitoring_interval_fails" {
  command = plan

  variables {
    cluster_identifier  = "test-pg"
    engine              = "aurora-postgresql"
    engine_version      = "15.4"
    vpc_id              = "vpc-12345678"
    subnet_ids          = ["subnet-aaaa1111", "subnet-bbbb2222"]
    monitoring_interval = 45
  }

  expect_failures = [var.monitoring_interval]
}

# --- Invalid network type ----------------------------------------------------
run "invalid_network_type_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    network_type       = "IPV6"
  }

  expect_failures = [var.network_type]
}

# --- Invalid activity stream mode --------------------------------------------
run "invalid_activity_stream_mode_fails" {
  command = plan

  variables {
    cluster_identifier   = "test-pg"
    engine               = "aurora-postgresql"
    engine_version       = "15.4"
    vpc_id               = "vpc-12345678"
    subnet_ids           = ["subnet-aaaa1111", "subnet-bbbb2222"]
    activity_stream_mode = "fast"
  }

  expect_failures = [var.activity_stream_mode]
}

# --- IOPS is only valid for aurora-postgresql --------------------------------
run "iops_on_mysql_fails" {
  command = plan

  variables {
    cluster_identifier = "test-mysql"
    engine             = "aurora-mysql"
    engine_version     = "8.0"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    iops               = 5000
  }

  expect_failures = [var.iops]
}

# --- Invalid database name ---------------------------------------------------
run "invalid_database_name_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    database_name      = "1-invalid-name"
  }

  expect_failures = [var.database_name]
}

# --- Port outside the allowed range ------------------------------------------
run "invalid_port_fails" {
  command = plan

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    port               = 80
  }

  expect_failures = [var.port]
}

# --- Backup retention outside 1..35 ------------------------------------------
run "invalid_backup_retention_fails" {
  command = plan

  variables {
    cluster_identifier      = "test-pg"
    engine                  = "aurora-postgresql"
    engine_version          = "15.4"
    vpc_id                  = "vpc-12345678"
    subnet_ids              = ["subnet-aaaa1111", "subnet-bbbb2222"]
    backup_retention_period = 40
  }

  expect_failures = [var.backup_retention_period]
}

# --- Invalid global cluster identifier ---------------------------------------
run "invalid_global_cluster_identifier_fails" {
  command = plan

  variables {
    cluster_identifier        = "test-pg"
    engine                    = "aurora-postgresql"
    engine_version            = "15.4"
    vpc_id                    = "vpc-12345678"
    subnet_ids                = ["subnet-aaaa1111", "subnet-bbbb2222"]
    enable_global_cluster     = true
    global_cluster_identifier = "1-bad-global"
  }

  expect_failures = [var.global_cluster_identifier]
}
