# Full-stack apply test using a mocked AWS provider, so the entire resource
# graph (cluster, instances, subnet group, parameter groups, security group,
# alarms, log groups, monitoring role, custom endpoints, role associations,
# activity stream) is created offline with no real AWS account. Run with:
# terraform test

mock_provider "aws" {
  mock_resource "aws_rds_cluster" {
    defaults = {
      # id must start with a letter — it feeds cluster_identifier on dependent
      # resources (instances, custom endpoints) that validate that rule. Pinning
      # it keeps the mocked apply deterministic.
      id       = "mock-cluster"
      arn      = "arn:aws:rds:us-east-1:123456789012:cluster:mock-cluster"
      endpoint = "mock-cluster.cluster-xyz.us-east-1.rds.amazonaws.com"
    }
  }
}

# --- Comprehensive provisioned cluster with most features enabled ------------
run "full_stack_apply" {
  command = apply

  variables {
    cluster_identifier = "test-pg"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222", "subnet-cccc3333"]

    master_username = "admin"
    master_password = "SuperSecret123"

    instances = {
      writer = { instance_class = "db.r6g.large", promotion_tier = 0 }
      reader = { instance_class = "db.r6g.large", promotion_tier = 1 }
    }

    allowed_cidr_blocks      = ["10.0.0.0/16"]
    allowed_ipv6_cidr_blocks = ["2600:1f18::/32"]
    allowed_security_groups  = ["sg-aaaa1111"]

    monitoring_interval             = 60
    performance_insights_enabled    = true
    enabled_cloudwatch_logs_exports = ["postgresql"]
    create_alarms                   = true

    cluster_endpoints = {
      analytics = { type = "READER", excluded_members = ["test-pg-writer"] }
    }

    iam_role_associations = {
      s3import = { role_arn = "arn:aws:iam::123456789012:role/aurora-s3", feature_name = "s3Import" }
    }

    tags = {
      Environment = "test"
      CostCenter  = "platform"
    }
  }

  assert {
    condition     = length(aws_rds_cluster_instance.instances) == 2
    error_message = "Expected a writer and a reader instance"
  }

  assert {
    condition     = length(aws_db_subnet_group.main) == 1
    error_message = "Expected one DB subnet group"
  }

  assert {
    condition     = length(aws_security_group.aurora) == 1
    error_message = "Expected one security group"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_cidr) == 1
    error_message = "Expected one IPv4 ingress rule"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.from_ipv6_cidr) == 1
    error_message = "Expected one IPv6 ingress rule"
  }

  assert {
    condition     = length(aws_iam_role.enhanced_monitoring) == 1
    error_message = "Enhanced monitoring role should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.database_replica_lag) == 1
    error_message = "Replica-lag alarm should exist for multi-instance clusters"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.aurora_logs) == 1
    error_message = "Expected one CloudWatch log group export"
  }

  assert {
    condition     = length(aws_rds_cluster_endpoint.custom) == 1
    error_message = "Expected one custom endpoint"
  }

  assert {
    condition     = length(aws_rds_cluster_role_association.this) == 1
    error_message = "Expected one IAM role association"
  }
}

# --- Minimal apply: only the essential resources are created -----------------
run "minimal_apply_creates_nothing_extra" {
  command = apply

  variables {
    cluster_identifier = "test-min"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    master_password    = "SuperSecret123"
    create_alarms      = false
  }

  assert {
    condition     = length(aws_iam_role.enhanced_monitoring) == 0
    error_message = "No monitoring role should be created by default"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.cpu_utilization) == 0
    error_message = "No alarms should be created when create_alarms is false"
  }

  assert {
    condition     = length(aws_rds_cluster_endpoint.custom) == 0
    error_message = "No custom endpoints by default"
  }

  assert {
    condition     = length(aws_rds_cluster_activity_stream.this) == 0
    error_message = "No activity stream by default"
  }
}

# --- Reuse an existing subnet group ------------------------------------------
run "reuse_existing_subnet_group_apply" {
  command = apply

  variables {
    cluster_identifier     = "test-byo"
    engine                 = "aurora-postgresql"
    engine_version         = "15.4"
    vpc_id                 = "vpc-12345678"
    master_password        = "SuperSecret123"
    create_db_subnet_group = false
    db_subnet_group_name   = "shared-db-subnets"
    create_alarms          = false
  }

  assert {
    condition     = length(aws_db_subnet_group.main) == 0
    error_message = "No subnet group should be created when reusing one"
  }

  assert {
    condition     = aws_rds_cluster.main.db_subnet_group_name == "shared-db-subnets"
    error_message = "Cluster should attach to the existing subnet group"
  }
}

# --- Serverless v2 cluster applies on a provisioned engine ------------------
run "serverless_v2_apply" {
  command = apply

  variables {
    cluster_identifier = "test-sv2"
    engine             = "aurora-postgresql"
    engine_version     = "15.4"
    vpc_id             = "vpc-12345678"
    subnet_ids         = ["subnet-aaaa1111", "subnet-bbbb2222"]
    master_password    = "SuperSecret123"
    create_alarms      = false

    serverless_scaling_configuration = {
      min_capacity = 0.5
      max_capacity = 8
    }

    instances = {
      writer = { instance_class = "db.serverless", promotion_tier = 0 }
    }
  }

  assert {
    condition     = aws_rds_cluster.main.engine_mode == "provisioned"
    error_message = "Serverless v2 should run on the provisioned engine mode"
  }

  assert {
    condition     = length(aws_rds_cluster.main.serverlessv2_scaling_configuration) == 1
    error_message = "A serverlessv2 scaling block should be created"
  }
}

# --- RDS-managed master password (Secrets Manager) --------------------------
run "managed_master_password_apply" {
  command = apply

  variables {
    cluster_identifier          = "test-managed"
    engine                      = "aurora-postgresql"
    engine_version              = "15.4"
    vpc_id                      = "vpc-12345678"
    subnet_ids                  = ["subnet-aaaa1111", "subnet-bbbb2222"]
    manage_master_user_password = true
    create_alarms               = false
  }

  assert {
    condition     = aws_rds_cluster.main.manage_master_user_password == true
    error_message = "RDS should manage the master password"
  }

  assert {
    condition     = aws_rds_cluster.main.master_password == null
    error_message = "No static master password should be set"
  }
}

# --- Database Activity Stream applies with a KMS key ------------------------
run "activity_stream_apply" {
  command = apply

  variables {
    cluster_identifier         = "test-das"
    engine                     = "aurora-postgresql"
    engine_version             = "15.4"
    vpc_id                     = "vpc-12345678"
    subnet_ids                 = ["subnet-aaaa1111", "subnet-bbbb2222"]
    master_password            = "SuperSecret123"
    create_alarms              = false
    enable_activity_stream     = true
    activity_stream_kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/abcd1234"
    activity_stream_mode       = "async"
  }

  assert {
    condition     = length(aws_rds_cluster_activity_stream.this) == 1
    error_message = "Activity stream resource should be created"
  }
}
