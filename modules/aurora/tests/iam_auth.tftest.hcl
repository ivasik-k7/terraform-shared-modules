# IAM database authentication: the rds-db:connect contract per user, through
# the cluster or through RDS Proxy, the optional policies, the refusals and
# the checks. Plan runs first; the apply runs at the end check the ARNs and
# policy documents, which are known only once the resource IDs exist.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  # The module reads the region from endpoint: v6 deprecates name and v5 has
  # no region attribute.
  mock_data "aws_region" {
    defaults = { endpoint = "ec2.eu-west-2.amazonaws.com" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  mock_resource "aws_rds_cluster" {
    defaults = {
      id  = "test-cluster"
      arn = "arn:aws:rds:eu-west-2:111122223333:cluster:test-cluster"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:rds!cluster-abc"
        kms_key_id    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
        secret_status = "active"
      }]
      engine_lifecycle_support = "open-source-rds-extended-support-disabled"
      cluster_resource_id      = "cluster-ABCDEFGHIJKLMNOP"
      endpoint                 = "test-cluster.cluster-c0abcdef.eu-west-2.rds.amazonaws.com"
    }
  }
  mock_resource "aws_db_proxy" {
    defaults = {
      arn      = "arn:aws:rds:eu-west-2:111122223333:db-proxy:prx-0123456789abcdef0"
      endpoint = "test-cluster-proxy.proxy-c0abcdef.eu-west-2.rds.amazonaws.com"
    }
  }
  mock_resource "aws_rds_global_cluster" {
    defaults = {
      id  = "orders-global"
      arn = "arn:aws:rds::111122223333:global-cluster:orders-global"
    }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  # The proxy target validates target_group_name; AWS calls it "default".
  mock_resource "aws_db_proxy_default_target_group" {
    defaults = { name = "default" }
  }
  # What the user-creating function returns. The mock does not invoke
  # anything: the function's behaviour is proved by
  # tests/lambda/test_iam_database_users.py.
  mock_resource "aws_lambda_invocation" {
    defaults = { result = "{\"action\":\"create\",\"engine\":\"postgres\",\"users\":{\"app_rw\":\"created\"}}" }
  }
}

# A fully configured cluster that trips no advisory check: terraform test
# fails a run on any check it does not expect.
variables {
  name = "test-cluster"

  tags = {
    Environment = "test"
    CostCentre  = "cc-1234"
    Owner       = "data-platform"
  }
  required_tag_keys = ["CostCentre", "Owner"]

  engine         = "aurora-postgresql"
  engine_version = "16.4"
  instance_class = "db.r7g.large"
  instances = {
    "1" = {}
    "2" = {}
  }

  database_name = "app"
  kms_key_arn   = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"

  vpc_id     = "vpc-0123456789abcdef0"
  subnet_ids = ["subnet-0123456789abcdef0", "subnet-0123456789abcdef1", "subnet-0123456789abcdef2"]
  ingress_rules = {
    app    = { referenced_security_group_id = "sg-0123456789abcdef0", description = "orders service" }
    onprem = { cidr_ipv4 = "10.20.0.0/16", description = "data centre via DX" }
  }

  enabled_cloudwatch_logs_exports = ["postgresql"]
  sns_topic_arn                   = "arn:aws:sns:eu-west-2:111122223333:db-alerts"

  # Runs that deviate from the baseline for another reason acknowledge every
  # check, so an incidental warning is not mistaken for the thing under test.
  every_check = [
    "cluster_survives_an_az", "instances_are_spread_across_azs", "somebody_hears_a_failover",
    "deleting_the_cluster_is_protected", "deleting_the_cluster_leaves_a_snapshot", "backups_cover_a_week",
    "query_level_metrics_exist", "database_logs_leave_the_instance", "log_retention_is_bounded",
    "tls_is_enforced_where_the_module_can_see", "the_module_controls_who_connects",
    "ingress_stays_inside_private_address_space", "egress_stays_inside_private_address_space", "something_can_connect", "credentials_are_not_in_state",
    "engine_version_is_exact", "minor_upgrades_do_not_fight_the_pin", "extended_support_matches_the_setting",
    "extended_support_is_a_decision", "auto_pause_has_an_engine_that_supports_it", "the_proxy_has_clients",
    "the_proxy_can_reach_secrets_manager", "the_proxy_can_decrypt_its_secrets", "the_proxy_requires_tls",
    "master_secret_key_is_the_one_configured", "performance_insights_key_is_the_one_configured",
    "activity_stream_key_is_the_one_configured", "database_insights_advanced_on_a_global_member",
    "major_upgrade_applies_immediately", "reader_autoscaling_has_a_reader",
    "mysql_log_exports_have_their_switches", "parameter_group_family_matches_the_engine",
    "iam_auth_failures_are_logged", "iam_auth_has_memory_headroom", "master_user_keeps_its_password",
    "audit_logs_are_retained", "iam_users_exist_in_the_engine",
  ]
}


# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------

run "no_iam_users_means_no_policies" {
  command = plan

  assert {
    condition     = length(output.iam_database_auth.users) == 0 && length(aws_iam_policy.iam_database_auth) == 0
    error_message = "IAM database users are opt-in."
  }

  assert {
    condition     = output.iam_database_auth.data_api_policy_json == null
    error_message = "no Data API policy unless the Data API is on."
  }
}

run "create_false_leaves_the_contract_null" {
  command = plan

  variables {
    create             = false
    iam_database_users = { app_rw = {} }
  }

  assert {
    condition     = output.iam_database_auth == null
    error_message = "create = false produces no contract."
  }
}

# ---------------------------------------------------------------------------
# What the engine has to run, known at plan
# ---------------------------------------------------------------------------

run "a_postgres_cluster_user_is_granted_rds_iam" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    iam_database_users                  = { app_rw = {} }
    acknowledged_checks                 = ["iam_users_exist_in_the_engine"] # the DBA runs the SQL here
  }

  assert {
    condition     = output.iam_database_auth.users["app_rw"].engine_sql == "CREATE USER \"app_rw\"; GRANT rds_iam TO \"app_rw\";"
    error_message = "a PostgreSQL IAM user is created and granted rds_iam."
  }

  assert {
    condition     = output.governance.iam_database_users == { app_rw = "cluster" }
    error_message = "governance lists IAM users and how they connect."
  }

  assert {
    condition = alltrue([
      !output.iam_database_auth.users_created_by_module,
      !output.iam_database_auth.users["app_rw"].created_by_module,
      output.iam_database_auth.users["app_rw"].engine_status == null,
      length(aws_lambda_function.iam_database_users) == 0,
      length(aws_lambda_invocation.iam_database_users) == 0,
      length(aws_iam_role.iam_database_users) == 0,
    ])
    error_message = "without create_iam_database_users the module creates no function and says the user is the DBA's to create."
  }
}

run "a_mysql_cluster_user_uses_the_aws_plugin_and_tls" {
  command = plan

  variables {
    engine                              = "aurora-mysql"
    engine_version                      = "8.0.mysql_aurora.3.08.0"
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["error", "iam-db-auth-error"]
    iam_database_users                  = { app_rw = {} }
    acknowledged_checks                 = ["iam_users_exist_in_the_engine"]
  }

  assert {
    condition     = strcontains(output.iam_database_auth.users["app_rw"].engine_sql, "IDENTIFIED WITH AWSAuthenticationPlugin AS 'RDS'") && strcontains(output.iam_database_auth.users["app_rw"].engine_sql, "REQUIRE SSL")
    error_message = "an Aurora MySQL IAM user uses AWSAuthenticationPlugin and requires TLS."
  }
}

run "a_proxy_user_is_a_password_user_in_the_engine" {
  command = plan

  variables {
    iam_database_users = { app = { connect_via = "proxy" } }
    proxy = {
      enabled            = true
      iam_auth           = "REQUIRED"
      secret_arns        = ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:app-AbCdEf"]
      secret_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      ingress_rules      = { app = { referenced_security_group_id = "sg-0123456789abcdef0", description = "orders service" } }
      egress_rules       = { secrets = { referenced_security_group_id = "sg-0123456789abcdef5", port = 443, description = "Secrets Manager endpoint" } }
    }
  }

  assert {
    condition     = strcontains(output.iam_database_auth.users["app"].engine_sql, "Do not grant rds_iam")
    error_message = "through the proxy the engine user keeps its password; granting rds_iam would break the proxy's login."
  }

  assert {
    condition     = output.iam_database_auth.users["app"].port == 5432 && output.iam_database_auth.proxy_iam_auth == "REQUIRED"
    error_message = "a proxy user connects to the proxy's port with IAM required."
  }
}

# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

run "a_cluster_user_without_iam_auth_on_the_cluster_is_refused" {
  command = plan

  variables {
    acknowledged_checks = var.every_check
    iam_database_users  = { app_rw = {} }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "a_proxy_user_without_a_proxy_is_refused" {
  command = plan

  variables {
    acknowledged_checks = var.every_check
    iam_database_users  = { app = { connect_via = "proxy" } }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "a_proxy_user_without_proxy_iam_auth_is_refused" {
  command = plan

  variables {
    acknowledged_checks = var.every_check
    iam_database_users  = { app = { connect_via = "proxy" } }
    proxy = {
      enabled           = true
      use_master_secret = true
    }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "a_mysql_user_name_over_32_characters_is_refused" {
  command = plan

  variables {
    acknowledged_checks                 = var.every_check
    engine                              = "aurora-mysql"
    engine_version                      = "8.0.mysql_aurora.3.08.0"
    enabled_cloudwatch_logs_exports     = ["error"]
    iam_database_authentication_enabled = true
    iam_database_users                  = { reporting_service_account_for_bi1 = {} }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "a_user_name_that_widens_the_arn_is_rejected" {
  command = plan

  variables {
    iam_database_users = { "app*" = {} }
  }

  expect_failures = [var.iam_database_users]
}

run "an_unknown_connection_path_is_rejected" {
  command = plan

  variables {
    iam_database_users = { app = { connect_via = "vpn" } }
  }

  expect_failures = [var.iam_database_users]
}

# ---------------------------------------------------------------------------
# Advisory checks
# ---------------------------------------------------------------------------

run "iam_auth_without_its_failure_log_warns" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
  }

  expect_failures = [check.iam_auth_failures_are_logged]
}

run "iam_auth_on_a_burstable_instance_warns" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    instance_class                      = "db.t4g.medium"
  }

  expect_failures = [check.iam_auth_has_memory_headroom]
}

run "making_the_master_user_an_iam_user_warns" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    iam_database_users                  = { dbadmin = {} }
    acknowledged_checks                 = ["iam_users_exist_in_the_engine"]
  }

  expect_failures = [check.master_user_keeps_its_password]
}

# A user the IAM side knows and the engine does not fails every login, as if
# the token were wrong.
run "a_cluster_user_nobody_creates_warns" {
  command = plan

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    iam_database_users                  = { app_rw = {} }
  }

  expect_failures = [check.iam_users_exist_in_the_engine]
}

# Proxy users are password users the caller creates; the warning is not for them.
run "a_proxy_user_alone_does_not_warn_about_engine_users" {
  command = plan

  variables {
    iam_database_users = { app = { connect_via = "proxy" } }
    proxy = {
      enabled            = true
      iam_auth           = "REQUIRED"
      secret_arns        = ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:app-AbCdEf"]
      secret_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      ingress_rules      = { app = { referenced_security_group_id = "sg-0123456789abcdef0", description = "orders service" } }
      egress_rules       = { secrets = { referenced_security_group_id = "sg-0123456789abcdef5", port = 443, description = "Secrets Manager endpoint" } }
    }
  }

  assert {
    condition     = length(aws_lambda_invocation.iam_database_users) == 0
    error_message = "nothing to create for a proxy user."
  }
}

# ---------------------------------------------------------------------------
# Creating the engine users (create_iam_database_users)
# ---------------------------------------------------------------------------

# apply: the policy and the key contract name the master secret and the
# role ARN, which exist only once the cluster and the role do.
run "the_module_creates_the_engine_users_through_the_data_api" {
  command = apply

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    enable_data_api                     = true
    create_iam_database_users           = true
    iam_database_users = {
      app_rw = {}
      etl    = { on_remove = "drop" }
      app    = { connect_via = "proxy" }
    }
    proxy = {
      enabled            = true
      iam_auth           = "REQUIRED"
      secret_arns        = ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:app-AbCdEf"]
      secret_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      ingress_rules      = { app = { referenced_security_group_id = "sg-0123456789abcdef0", description = "orders service" } }
      egress_rules       = { secrets = { referenced_security_group_id = "sg-0123456789abcdef5", port = 443, description = "Secrets Manager endpoint" } }
    }
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.iam_database_users) == 1,
      aws_lambda_function.iam_database_users[0].function_name == "test-cluster-dbusers",
      aws_lambda_function.iam_database_users[0].runtime == "python3.12",
      length(aws_lambda_function.iam_database_users[0].vpc_config) == 0,
      aws_iam_role.iam_database_users[0].name == "test-cluster-eu-west-2-dbusers",
      aws_cloudwatch_log_group.iam_database_users[0].name == "/aws/lambda/test-cluster-dbusers",
    ])
    error_message = "one function outside any VPC, a region-qualified role, and a log group created before the first run."
  }

  assert {
    condition     = aws_lambda_invocation.iam_database_users[0].lifecycle_scope == "CRUD"
    error_message = "CRUD: the function is told about updates (with the previous input) and about the destroy, not only the create."
  }

  # The cluster users only, each with its on_remove; the proxy user is the
  # caller's password user.
  assert {
    condition = alltrue([
      jsondecode(aws_lambda_invocation.iam_database_users[0].input).users == { app_rw = { on_remove = "revoke" }, etl = { on_remove = "drop" } },
      jsondecode(aws_lambda_invocation.iam_database_users[0].input).engine == "postgres",
      jsondecode(aws_lambda_invocation.iam_database_users[0].input).database == "app",
      jsondecode(aws_lambda_invocation.iam_database_users[0].input).cluster_arn == "arn:aws:rds:eu-west-2:111122223333:cluster:test-cluster",
    ])
    error_message = "the function is told exactly the cluster users, the engine, the database and the cluster."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(aws_iam_role_policy.iam_database_users[0].policy).Statement :
      st.Sid == "ExecuteOnThisCluster" ? jsonencode(st.Action) == jsonencode(["rds-data:ExecuteStatement"]) && jsonencode(st.Resource) == jsonencode(["arn:aws:rds:eu-west-2:111122223333:cluster:test-cluster"]) : true
    ])
    error_message = "the function may execute statements on this cluster and nothing else."
  }

  assert {
    condition = anytrue([
      for st in jsondecode(aws_iam_role_policy.iam_database_users[0].policy).Statement :
      st.Sid != "DecryptAdminSecret" ? false : (
        try(st.Condition.StringEquals["kms:ViaService"], "") != "secretsmanager.eu-west-2.amazonaws.com" ? false :
        jsonencode(st.Resource) == jsonencode(["arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"])
      )
    ])
    error_message = "the master secret's customer key is decrypted through Secrets Manager only."
  }

  assert {
    condition = alltrue([
      output.iam_database_auth.users_created_by_module,
      output.iam_database_auth.users["app_rw"].created_by_module,
      output.iam_database_auth.users["etl"].created_by_module,
      !output.iam_database_auth.users["app"].created_by_module,
      output.governance.iam_database_users_created_by_module,
      output.iam_database_users_function_name == "test-cluster-dbusers",
    ])
    error_message = "the contract says which users the module creates: cluster users yes, the proxy user no."
  }

  assert {
    condition     = anytrue([for r in output.kms_key_policy_requirements : r.sid == "MasterSecretReaders" && length(r.principals.arns) == 1])
    error_message = "the key policy contract names the function's role as a reader of the master secret."
  }
}

run "the_engine_status_is_reported_once_applied" {
  command = apply

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    enable_data_api                     = true
    create_iam_database_users           = true
    iam_database_users                  = { app_rw = {} }
  }

  assert {
    condition     = output.iam_database_auth.users["app_rw"].engine_status == "created"
    error_message = "what the function reported for the user is in the contract."
  }
}

run "a_brought_admin_secret_replaces_the_master_secret" {
  command = apply

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    enable_data_api                     = true
    create_iam_database_users           = true
    iam_database_users                  = { app_rw = {} }
    iam_database_users_admin_secret = {
      arn         = "arn:aws:secretsmanager:eu-west-2:111122223333:secret:dba-createrole-AbCdEf"
      kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555"
    }
  }

  assert {
    condition     = jsondecode(aws_lambda_invocation.iam_database_users[0].input).secret_arn == "arn:aws:secretsmanager:eu-west-2:111122223333:secret:dba-createrole-AbCdEf"
    error_message = "the function logs in with the brought secret."
  }

  assert {
    condition = alltrue([
      for st in jsondecode(aws_iam_role_policy.iam_database_users[0].policy).Statement :
      st.Sid == "ReadAdminSecret" ? jsonencode(st.Resource) == jsonencode(["arn:aws:secretsmanager:eu-west-2:111122223333:secret:dba-createrole-AbCdEf"]) :
      st.Sid == "DecryptAdminSecret" ? jsonencode(st.Resource) == jsonencode(["arn:aws:kms:eu-west-2:111122223333:key/99999999-2222-3333-4444-555555555555"]) : true
    ])
    error_message = "the role reads the brought secret and decrypts with its key, not the master secret's."
  }

  assert {
    condition     = anytrue([for r in output.kms_key_policy_requirements : r.sid == "MasterSecretReaders" && length(r.principals.arns) == 0])
    error_message = "with a brought secret the function is not a reader of the master secret."
  }
}

run "creating_engine_users_without_the_data_api_is_refused" {
  command = plan

  variables {
    acknowledged_checks                 = var.every_check
    iam_database_authentication_enabled = true
    create_iam_database_users           = true
    iam_database_users                  = { app_rw = {} }
  }

  expect_failures = [aws_rds_cluster.this]
}

run "creating_engine_users_without_a_secret_is_refused" {
  command = plan

  variables {
    acknowledged_checks                 = var.every_check
    iam_database_authentication_enabled = true
    enable_data_api                     = true
    create_iam_database_users           = true
    iam_database_users                  = { app_rw = {} }
    manage_master_user_password         = false
    master_password                     = "correct-horse-battery-staple"
    allow_plaintext_credentials         = true
  }

  expect_failures = [aws_rds_cluster.this]
}

run "an_unknown_on_remove_is_rejected" {
  command = plan

  variables {
    iam_database_users = { app_rw = { on_remove = "nuke" } }
  }

  expect_failures = [var.iam_database_users]
}

run "a_malformed_admin_secret_arn_is_rejected" {
  command = plan

  variables {
    iam_database_users_admin_secret = { arn = "dba-createrole" }
  }

  expect_failures = [var.iam_database_users_admin_secret]
}

run "create_false_creates_no_engine_users_either" {
  command = plan

  variables {
    create                    = false
    enable_data_api           = true
    create_iam_database_users = true
    iam_database_users        = { app_rw = {} }
  }

  assert {
    condition     = length(aws_lambda_invocation.iam_database_users) == 0 && length(aws_lambda_function.iam_database_users) == 0 && output.iam_database_users_function_name == null
    error_message = "create = false plans no function and no invocation."
  }
}

# ---------------------------------------------------------------------------
# The contract once the resource IDs exist
# ---------------------------------------------------------------------------

run "the_contract_names_each_user_exactly" {
  command = apply

  variables {
    iam_database_authentication_enabled = true
    enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
    create_iam_database_auth_policies   = true
    enable_data_api                     = true
    acknowledged_checks                 = ["iam_users_exist_in_the_engine"]
    iam_database_users = {
      app_rw = {}
      app    = { connect_via = "proxy" }
    }
    proxy = {
      enabled            = true
      iam_auth           = "REQUIRED"
      secret_arns        = ["arn:aws:secretsmanager:eu-west-2:111122223333:secret:app-AbCdEf"]
      secret_kms_key_arn = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
      ingress_rules      = { app = { referenced_security_group_id = "sg-0123456789abcdef0", description = "orders service" } }
      egress_rules       = { secrets = { referenced_security_group_id = "sg-0123456789abcdef5", port = 443, description = "Secrets Manager endpoint" } }
    }
  }

  assert {
    condition     = output.iam_database_auth.users["app_rw"].resource_arn == "arn:aws:rds-db:eu-west-2:111122223333:dbuser:cluster-ABCDEFGHIJKLMNOP/app_rw"
    error_message = "a cluster user's ARN is dbuser:<cluster resource id>/<user>."
  }

  assert {
    condition     = output.iam_database_auth.users["app"].resource_arn == "arn:aws:rds-db:eu-west-2:111122223333:dbuser:prx-0123456789abcdef0/app"
    error_message = "a proxy user's ARN is dbuser:<proxy resource id>/<user>, taken from the proxy ARN."
  }

  assert {
    condition = alltrue([
      for u in ["app_rw", "app"] :
      jsondecode(output.iam_database_auth.users[u].policy_json).Statement[0].Action == "rds-db:connect"
      && jsondecode(output.iam_database_auth.users[u].policy_json).Statement[0].Resource == output.iam_database_auth.users[u].resource_arn
    ])
    error_message = "each policy allows rds-db:connect on exactly that user's ARN."
  }

  assert {
    condition = alltrue([
      length(aws_iam_policy.iam_database_auth) == 2,
      aws_iam_policy.iam_database_auth["app_rw"].name == "test-cluster-eu-west-2-dbuser-app_rw",
      output.iam_database_auth.users["app_rw"].policy_arn != null,
    ])
    error_message = "one module-created policy per user, named <name>-<region>-dbuser-<user>."
  }

  assert {
    condition = alltrue([
      output.iam_database_auth.users["app_rw"].host == "test-cluster.cluster-c0abcdef.eu-west-2.rds.amazonaws.com",
      output.iam_database_auth.users["app"].host == "test-cluster-proxy.proxy-c0abcdef.eu-west-2.rds.amazonaws.com",
      strcontains(output.iam_database_auth.users["app_rw"].token_command, "--hostname test-cluster.cluster-c0abcdef.eu-west-2.rds.amazonaws.com --port 5432 --region eu-west-2 --username app_rw"),
    ])
    error_message = "tokens are generated for the endpoint the user connects to."
  }

  assert {
    condition = alltrue([
      length(jsondecode(output.iam_database_auth.data_api_policy_json).Statement[0].Action) == 5,
      jsondecode(output.iam_database_auth.data_api_policy_json).Statement[0].Resource == "arn:aws:rds:eu-west-2:111122223333:cluster:test-cluster",
      jsondecode(output.iam_database_auth.data_api_policy_json).Statement[1].Action == "secretsmanager:GetSecretValue",
    ])
    error_message = "the Data API policy grants the five rds-data actions on this cluster and reads the master secret."
  }
}
