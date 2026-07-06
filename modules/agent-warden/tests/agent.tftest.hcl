# plan-level checks, no creds. policies are jsonencoded in locals so their
# content is knowable at plan and assertable offline.

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
}

# --- secure defaults ---------------------------------------------------------
run "defaults" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
  }

  assert {
    condition     = length(aws_iam_role.this) == 1 && length(aws_iam_policy.boundary) == 1
    error_message = "Role + boundary should be created"
  }

  assert {
    condition     = length(aws_iam_role_policy_attachment.read_only) == 1
    error_message = "ReadOnlyAccess baseline should be attached by default"
  }

  # trust: SSO pattern + attribution requirement
  assert {
    condition     = can(regex("AWSReservedSSO_Developer_", aws_iam_role.this[0].assume_role_policy)) && can(regex("aws:PrincipalArn", aws_iam_role.this[0].assume_role_policy))
    error_message = "Trust should allow the SSO permission-set role pattern"
  }

  assert {
    condition     = can(regex("sts:SourceIdentity", aws_iam_role.this[0].assume_role_policy))
    error_message = "SourceIdentity should be required by default (attribution)"
  }

  # boundary: the hard denies
  assert {
    condition = alltrue([
      can(regex("DenyDangerous", aws_iam_policy.boundary[0].policy)),
      can(regex("DenyDataExfiltration", aws_iam_policy.boundary[0].policy)),
      can(regex("DenyOutsideAllowedRegions", aws_iam_policy.boundary[0].policy)),
    ])
    error_message = "Boundary must deny dangerous, exfil, and cross-region"
  }

  assert {
    condition     = can(regex("secretsmanager:GetSecretValue", aws_iam_policy.boundary[0].policy)) && can(regex("iam:PassRole", aws_iam_policy.boundary[0].policy))
    error_message = "Boundary should deny secret reads and PassRole escalation"
  }

  # exfil bypasses must be closed (batch/history variants, password data, lambda env,
  # data APIs, credential-minting reads)
  assert {
    condition = alltrue([
      can(regex("secretsmanager:BatchGetSecretValue", aws_iam_policy.boundary[0].policy)),
      can(regex("ec2:GetPasswordData", aws_iam_policy.boundary[0].policy)),
      can(regex("lambda:GetFunctionConfiguration", aws_iam_policy.boundary[0].policy)),
      can(regex("rds-data:ExecuteStatement", aws_iam_policy.boundary[0].policy)),
      can(regex("redshift:GetClusterCredentials", aws_iam_policy.boundary[0].policy)),
      can(regex("rds-db:connect", aws_iam_policy.boundary[0].policy)),
      can(regex("sts:GetFederationToken", aws_iam_policy.boundary[0].policy)),
    ])
    error_message = "Boundary should close batch-secret / password / lambda-env / data-API / credential-minting bypasses"
  }

  # iam escalation AND destruction denied
  assert {
    condition     = can(regex("iam:DetachRolePolicy", aws_iam_policy.boundary[0].policy)) && can(regex("iam:SetDefaultPolicyVersion", aws_iam_policy.boundary[0].policy))
    error_message = "Boundary should deny iam detach / set-default-version"
  }
}

# --- attribution can be relaxed ---------------------------------------------
run "no_source_identity" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    require_source_identity  = false
  }

  assert {
    condition     = !can(regex("SourceIdentity", aws_iam_role.this[0].assume_role_policy))
    error_message = "SourceIdentity requirement should be absent when disabled"
  }
}

# --- exfil deny can be turned off (not recommended) --------------------------
run "exfil_off" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    deny_data_exfiltration   = false
  }

  assert {
    condition     = !can(regex("DenyDataExfiltration", aws_iam_policy.boundary[0].policy))
    error_message = "Exfil deny should be absent when disabled"
  }
}

# --- scoped data-read exception (team needs one secret) ----------------------
run "data_read_exception" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    data_read_exceptions     = ["arn:aws:secretsmanager:us-east-1:123456789012:secret:team/db-*"]
  }

  assert {
    condition     = can(regex("NotResource", aws_iam_policy.boundary[0].policy)) && can(regex("team/db", aws_iam_policy.boundary[0].policy))
    error_message = "Exfil deny should carve out the excepted ARN via NotResource"
  }
}

# --- trust hardening: mfa + source ip + expiry ------------------------------
run "trust_hardening" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    require_mfa              = true
    allowed_source_ip_cidrs  = ["203.0.113.0/24"]
    access_expires_at        = "2026-12-31T23:59:59Z"
  }

  assert {
    condition = alltrue([
      can(regex("MultiFactorAuthPresent", aws_iam_role.this[0].assume_role_policy)),
      can(regex("aws:SourceIp", aws_iam_role.this[0].assume_role_policy)),
      can(regex("203.0.113.0/24", aws_iam_role.this[0].assume_role_policy)),
      can(regex("DateLessThan", aws_iam_role.this[0].assume_role_policy)),
      can(regex("2026-12-31", aws_iam_role.this[0].assume_role_policy)),
    ])
    error_message = "Trust should enforce MFA, source-IP lock, and expiry when set"
  }
}

# --- trust hardening is opt-in (absent by default) --------------------------
run "trust_hardening_absent_by_default" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
  }

  assert {
    condition = alltrue([
      !can(regex("MultiFactorAuthPresent", aws_iam_role.this[0].assume_role_policy)),
      !can(regex("aws:SourceIp", aws_iam_role.this[0].assume_role_policy)),
      !can(regex("DateLessThan", aws_iam_role.this[0].assume_role_policy)),
    ])
    error_message = "MFA / source-IP / expiry must be absent unless explicitly enabled"
  }
}

run "bad_expiry_fails" {
  command = plan
  variables {
    sso_permission_set_names = ["Developer"]
    access_expires_at        = "not-a-timestamp"
  }
  expect_failures = [var.access_expires_at]
}

# --- kill switch denies everything ------------------------------------------
run "kill_switch" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    kill_switch              = true
  }

  assert {
    condition     = can(regex("KillSwitch", aws_iam_policy.boundary[0].policy))
    error_message = "Kill switch should add a deny-all to the boundary"
  }
}

# --- team grants extend the baseline ----------------------------------------
run "team_grants" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    team_grants = [
      {
        sid       = "PlatformS3Write"
        actions   = ["s3:PutObject"]
        resources = ["arn:aws:s3:::platform-sandbox/*"]
      },
    ]
  }

  assert {
    condition     = length(aws_iam_role_policy.team_grants) == 1 && can(regex("PlatformS3Write", aws_iam_role_policy.team_grants[0].policy))
    error_message = "team_grants should produce an inline policy with the statement"
  }
}

# --- team grant conditions render operator-first (valid IAM shape) -----------
run "team_grant_conditions" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    team_grants = [
      {
        sid       = "RegionLockedWrite"
        actions   = ["s3:PutObject"]
        resources = ["arn:aws:s3:::sandbox/*"]
        conditions = [
          { test = "StringEquals", variable = "aws:RequestedRegion", values = ["us-east-1"] },
          { test = "StringEquals", variable = "aws:ResourceTag/Team", values = ["platform"] },
          { test = "Bool", variable = "aws:SecureTransport", values = ["true"] },
        ]
      },
    ]
  }

  # IAM requires { operator: { variable: values } }; same-operator conditions group.
  assert {
    condition = alltrue([
      strcontains(aws_iam_role_policy.team_grants[0].policy, "\"StringEquals\":{\"aws:RequestedRegion\":[\"us-east-1\"],\"aws:ResourceTag/Team\":[\"platform\"]}"),
      strcontains(aws_iam_role_policy.team_grants[0].policy, "\"Bool\":{\"aws:SecureTransport\":[\"true\"]}"),
    ])
    error_message = "Conditions must be operator-first ({test:{variable:values}}) and grouped per operator"
  }
}

# --- extra denied actions ----------------------------------------------------
run "extra_denied" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    extra_denied_actions     = ["bedrock:*"]
  }

  assert {
    condition     = can(regex("DenyExtra", aws_iam_policy.boundary[0].policy)) && can(regex("bedrock", aws_iam_policy.boundary[0].policy))
    error_message = "extra_denied_actions should be denied in the boundary"
  }
}

# --- create = false ----------------------------------------------------------
run "create_false" {
  command = plan

  variables {
    create                   = false
    sso_permission_set_names = ["Developer"]
  }

  assert {
    condition     = length(aws_iam_role.this) == 0 && length(aws_iam_policy.boundary) == 0
    error_message = "create=false should build nothing"
  }
}

# --- runtime layer is entirely opt-in ---------------------------------------
run "runtime_off_by_default" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
  }

  assert {
    condition = alltrue([
      length(aws_sns_topic.alerts) == 0,
      length(aws_cloudwatch_event_rule.high_risk) == 0,
      length(aws_budgets_budget.ai) == 0,
      length(aws_lambda_function.killswitch) == 0,
      length(aws_lambda_function.digest) == 0,
      length(aws_iam_role.break_glass) == 0,
    ])
    error_message = "No runtime resources should exist unless their feature is enabled"
  }
}

# --- alerting builds the topic + high-risk rule ------------------------------
run "alerting" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_alerting          = true
    alert_emails             = ["secops@example.com"]
  }

  assert {
    condition = alltrue([
      length(aws_sns_topic.alerts) == 1,
      length(aws_cloudwatch_event_rule.high_risk) == 1,
      length(aws_cloudwatch_event_target.high_risk) == 1,
      length(aws_sns_topic_subscription.email) == 1,
    ])
    error_message = "Alerting should create the topic, rule, target, and email subscription"
  }
}

# --- bring-your-own topic suppresses topic creation --------------------------
run "byo_topic" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_alerting          = true
    alert_sns_topic_arn      = "arn:aws:sns:us-east-1:123456789012:existing"
  }

  assert {
    condition     = length(aws_sns_topic.alerts) == 0
    error_message = "A provided topic ARN should suppress module topic creation"
  }
}

# --- budget guardrail + auto killswitch --------------------------------------
run "budget_killswitch" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_budget_guardrail  = true
    monthly_budget_usd       = 500
    enable_budget_killswitch = true
  }

  assert {
    condition = alltrue([
      length(aws_budgets_budget.ai) == 1,
      length(aws_lambda_function.killswitch) == 1,
      length(aws_iam_role_policy.killswitch) == 1,
      length(aws_sns_topic_subscription.killswitch) == 1,
    ])
    error_message = "Budget guardrail + killswitch should build budget, Lambda, its scoped policy, and SNS wiring"
  }

  # the containment Lambda must hang off its OWN topic, not the shared alerts one
  assert {
    condition = alltrue([
      length(aws_sns_topic.killswitch) == 1,
      length(aws_sns_topic_policy.killswitch) == 1,
      length(aws_cloudwatch_log_group.killswitch) == 1,
    ])
    error_message = "Killswitch must use a dedicated topic (not the shared alerts topic) and a managed log group"
  }
}

run "killswitch_without_guardrail_fails" {
  command = plan
  variables {
    sso_permission_set_names = ["Developer"]
    enable_budget_killswitch = true
  }
  expect_failures = [var.enable_budget_killswitch]
}

run "budget_zero_fails" {
  command = plan
  variables {
    sso_permission_set_names = ["Developer"]
    enable_budget_guardrail  = true
    monthly_budget_usd       = 0
  }
  expect_failures = [var.monthly_budget_usd]
}

# --- daily digest ------------------------------------------------------------
run "daily_digest" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_daily_digest      = true
  }

  assert {
    condition = alltrue([
      length(aws_lambda_function.digest) == 1,
      length(aws_cloudwatch_event_rule.digest) == 1,
      length(aws_lambda_permission.digest_from_events) == 1,
      length(aws_sns_topic.alerts) == 1,
    ])
    error_message = "Daily digest should build the Lambda, schedule, permission, and a topic"
  }
}

# --- break-glass role --------------------------------------------------------
run "break_glass" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_break_glass       = true
    enable_alerting          = true
  }

  assert {
    condition = alltrue([
      length(aws_iam_role.break_glass) == 1,
      length(aws_iam_role_policy_attachment.break_glass) == 1,
      length(aws_cloudwatch_event_rule.break_glass_assumed) == 1,
    ])
    error_message = "Break-glass should build the role, its policy attachment, and an assume alert"
  }

  # break-glass trust is non-negotiable: MFA + SourceIdentity always
  assert {
    condition     = can(regex("MultiFactorAuthPresent", aws_iam_role.break_glass[0].assume_role_policy)) && can(regex("SourceIdentity", aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "Break-glass trust must always require MFA and SourceIdentity"
  }
}

# --- break-glass can trust a narrower senior group --------------------------
run "break_glass_separate_principals" {
  command = plan

  variables {
    sso_permission_set_names             = ["Developer"]
    enable_break_glass                   = true
    break_glass_sso_permission_set_names = ["IncidentCommander"]
  }

  assert {
    condition     = can(regex("AWSReservedSSO_IncidentCommander_", aws_iam_role.break_glass[0].assume_role_policy)) && !can(regex("AWSReservedSSO_Developer_", aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "Break-glass should trust its own principal set when provided, not the AI's"
  }
}

# --- FinOps: tag-on-create enforcement ---------------------------------------
run "tag_on_create" {
  command = plan

  variables {
    sso_permission_set_names   = ["Developer"]
    enforce_cost_tag_on_create = true
  }

  assert {
    condition     = can(regex("DenyUntaggedCreate", aws_iam_policy.boundary[0].policy)) && can(regex("aws:RequestTag/Purpose", aws_iam_policy.boundary[0].policy))
    error_message = "Boundary should deny listed creates missing the cost tag"
  }

  assert {
    condition     = can(regex("ec2:RunInstances", aws_iam_policy.boundary[0].policy))
    error_message = "Default enforced-action list should cover ec2:RunInstances"
  }
}

# --- operability: DLQ + alarm on the containment path ------------------------
run "killswitch_never_silent" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
    enable_budget_guardrail  = true
    monthly_budget_usd       = 500
    enable_budget_killswitch = true
  }

  assert {
    condition = alltrue([
      length(aws_sqs_queue.killswitch_dlq) == 1,
      length(aws_cloudwatch_metric_alarm.killswitch_errors) == 1,
    ])
    error_message = "Killswitch must have a DLQ and an error alarm - containment failures can't be silent"
  }
}

# --- drift control: exclusive inline policies ---------------------------------
run "exclusive_inline" {
  command = plan

  variables {
    sso_permission_set_names  = ["Developer"]
    exclusive_inline_policies = true
    team_grants = [
      { sid = "T", actions = ["s3:ListBucket"] },
    ]
  }

  assert {
    condition     = length(aws_iam_role_policies_exclusive.this) == 1
    error_message = "exclusive_inline_policies should manage the role's inline policy set"
  }
}

# --- SCP renders only with provisioner principals -----------------------------
run "scp_output" {
  command = plan

  variables {
    sso_permission_set_names   = ["Developer"]
    provisioner_principal_arns = ["arn:aws:iam::111122223333:role/tfc"]
  }

  assert {
    condition     = output.scp_policy_json != null && can(regex("ProtectAIRoles", output.scp_policy_json)) && can(regex("ArnNotLike", output.scp_policy_json))
    error_message = "SCP should deny guardrail-tampering for everyone except the provisioner"
  }
}

run "scp_null_without_provisioner" {
  command = plan

  variables {
    sso_permission_set_names = ["Developer"]
  }

  assert {
    condition     = output.scp_policy_json == null
    error_message = "SCP output must be null until provisioner_principal_arns is set"
  }
}

# --- scalability: Lake digest path --------------------------------------------
run "digest_lake" {
  command = plan

  variables {
    sso_permission_set_names    = ["Developer"]
    enable_daily_digest         = true
    digest_event_data_store_arn = "arn:aws:cloudtrail:us-east-1:123456789012:eventdatastore/abc-123"
  }

  assert {
    condition     = aws_lambda_function.digest[0].environment[0].variables["EVENT_DATA_STORE_ARN"] == "arn:aws:cloudtrail:us-east-1:123456789012:eventdatastore/abc-123"
    error_message = "Digest Lambda should receive the Lake event data store ARN"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "no_sso_names_fails" {
  command = plan
  variables {
    sso_permission_set_names = []
  }
  expect_failures = [var.sso_permission_set_names]
}

run "bad_session_duration_fails" {
  command = plan
  variables {
    sso_permission_set_names = ["Developer"]
    max_session_duration     = 100
  }
  expect_failures = [var.max_session_duration]
}

run "dup_team_sid_fails" {
  command = plan
  variables {
    sso_permission_set_names = ["Developer"]
    team_grants = [
      { sid = "dup", actions = ["s3:GetObject"] },
      { sid = "dup", actions = ["s3:ListBucket"] },
    ]
  }
  expect_failures = [var.team_grants]
}
