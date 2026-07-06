locals {
  create = var.create
  # fallbacks keep string templates from interpolating null when create = false;
  # the values are unused then (no resources).
  account   = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")
  partition = coalesce(one(data.aws_partition.current[*].partition), "aws")

  common_tags = merge(var.tags, {
    "ManagedBy" = "Terraform"
    "Module"    = "agent-warden"
    "Purpose"   = "ai-agent"
  })

  # ---- trust: SSO permission-set users, attributable via SourceIdentity ----
  sso_role_arns = [
    for name in var.sso_permission_set_names :
    "arn:${local.partition}:iam::${local.account}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_${name}_*"
  ]

  # trust conditions build up who / when / where / how-strong may assume.
  # each uses a distinct operator, so the merge never collides keys.
  trust_conditions = merge(
    { ArnLike = { "aws:PrincipalArn" = local.sso_role_arns } },
    # force attribution: the session MUST carry a SourceIdentity (the human)
    var.require_source_identity ? { Null = { "sts:SourceIdentity" = "false" } } : {},
    # require MFA to have been used in the originating SSO session
    var.require_mfa ? { Bool = { "aws:MultiFactorAuthPresent" = "true" } } : {},
    # lock assume to known egress (TFC runners / corp VPN)
    length(var.allowed_source_ip_cidrs) > 0 ? { IpAddress = { "aws:SourceIp" = var.allowed_source_ip_cidrs } } : {},
    # self-expiring identity: assume is refused after this instant
    var.access_expires_at != "" ? { DateLessThan = { "aws:CurrentTime" = var.access_expires_at } } : {},
  )

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowSSOAssume"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account}:root" }
        Action    = concat(["sts:AssumeRole", "sts:TagSession"], var.require_source_identity ? ["sts:SetSourceIdentity"] : [])
        Condition = local.trust_conditions
      }
    ]
  })

  # ---- guardrail action sets (the hard ceiling lives in the boundary) ----

  # global services report a region too; exempt them from the region deny.
  global_service_prefixes = [
    "iam:*", "sts:*", "organizations:*", "account:*", "cloudfront:*",
    "route53:*", "route53domains:*", "waf:*", "wafv2:*", "shield:*",
    "globalaccelerator:*", "support:*", "trustedadvisor:*", "budgets:*",
    "ce:*", "cur:*", "health:*", "artifact:*",
  ]

  # data/secret VALUE reads - deny so the AI sees infra shape, not data.
  exfiltration_actions = [
    # secrets / parameters (incl. the batch + history variants that bypass the singular deny)
    "secretsmanager:GetSecretValue", "secretsmanager:BatchGetSecretValue",
    "ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath", "ssm:GetParameterHistory",
    # crypto material
    "kms:Decrypt", "kms:GenerateDataKey", "kms:GenerateDataKeyWithoutPlaintext",
    # object / item data
    "s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTorrent",
    "dynamodb:GetItem", "dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:Scan", "dynamodb:PartiQLSelect",
    "sqs:ReceiveMessage",
    "kinesis:GetRecords", "kinesis:GetShardIterator",
    "athena:GetQueryResults",
    # log contents (frequently hold secrets)
    "logs:GetLogEvents", "logs:FilterLogEvents", "logs:GetQueryResults",
    # row-level reads through the Data APIs (bypass dynamodb/s3 denies entirely)
    "rds-data:ExecuteStatement", "rds-data:BatchExecuteStatement", "rds-data:ExecuteSql",
    "redshift-data:ExecuteStatement", "redshift-data:BatchExecuteStatement", "redshift-data:GetStatementResult",
    # step functions payloads carry application data
    "states:DescribeExecution", "states:GetExecutionHistory",
    # things that ARE credentials / leak secrets via "read" APIs
    "ec2:GetPasswordData",                                   # windows admin password
    "lambda:GetFunction", "lambda:GetFunctionConfiguration", # both return env vars (secrets)
    "ecr:GetAuthorizationToken", "ecr-public:GetAuthorizationToken",
    "codeartifact:GetAuthorizationToken",
    "redshift:GetClusterCredentials", "redshift:GetClusterCredentialsWithIAM", # mint DB creds
    "rds-db:connect",                                                          # IAM DB auth
    "lightsail:GetInstanceAccessDetails", "lightsail:GetRelationalDatabaseMasterUserPassword",
    "glue:GetConnection", "glue:GetConnections", # connections embed credentials
  ]

  # privilege escalation / security-control tampering / destruction - always denied.
  dangerous_actions = [
    # IAM write + passrole (escalation) and destruction
    "iam:CreateUser", "iam:CreateRole", "iam:CreatePolicy", "iam:CreatePolicyVersion",
    "iam:SetDefaultPolicyVersion",
    "iam:CreateAccessKey", "iam:CreateLoginProfile", "iam:UpdateLoginProfile",
    "iam:AttachRolePolicy", "iam:AttachUserPolicy", "iam:AttachGroupPolicy",
    "iam:DetachRolePolicy", "iam:DetachUserPolicy", "iam:DetachGroupPolicy",
    "iam:PutRolePolicy", "iam:PutUserPolicy", "iam:PutGroupPolicy",
    "iam:UpdateAssumeRolePolicy", "iam:PassRole",
    "iam:AddUserToGroup",
    "iam:PutRolePermissionsBoundary", "iam:PutUserPermissionsBoundary",
    "iam:DeleteRolePermissionsBoundary", "iam:DeleteUserPermissionsBoundary",
    "iam:UpdateRole", "iam:DeleteRole", "iam:DeleteRolePolicy", "iam:DeletePolicy", "iam:DeletePolicyVersion",
    # role-chaining / credential-minting escape
    "sts:AssumeRole", "sts:AssumeRoleWithSAML", "sts:AssumeRoleWithWebIdentity",
    "sts:GetFederationToken",
    # org / account / billing
    "organizations:*", "account:*", "aws-portal:*", "billing:*", "payments:*",
    # identity center ("sso" is the IAM prefix for the admin APIs too)
    "sso:*", "sso-directory:*", "identitystore:*",
    # audit / security-control tampering
    "cloudtrail:StopLogging", "cloudtrail:DeleteTrail", "cloudtrail:UpdateTrail", "cloudtrail:PutEventSelectors",
    "guardduty:DeleteDetector", "guardduty:UpdateDetector", "guardduty:DisassociateFromMasterAccount", "guardduty:StopMonitoringMembers", "guardduty:DeleteMembers",
    "config:DeleteConfigurationRecorder", "config:StopConfigurationRecorder", "config:DeleteDeliveryChannel", "config:DeleteConfigRule",
    "securityhub:DisableSecurityHub", "securityhub:BatchDisableStandards",
    # crypto / public-exposure / log tampering
    "kms:ScheduleKeyDeletion", "kms:DisableKey", "kms:PutKeyPolicy",
    "s3:PutBucketPolicy", "s3:DeleteBucketPolicy", "s3:PutBucketPublicAccessBlock", "s3:PutAccountPublicAccessBlock",
    "s3:PutBucketAcl", "s3:PutObjectAcl", "s3:PutObjectVersionAcl", "s3:PutAccessPointPolicy",
    "ec2:DeleteFlowLogs", "ec2:DisableEbsEncryptionByDefault",
  ]

  boundary_statements = concat(
    [
      { Sid = "Ceiling", Effect = "Allow", Action = "*", Resource = "*" },
      { Sid = "DenyDangerous", Effect = "Deny", Action = local.dangerous_actions, Resource = "*" },
      {
        Sid       = "DenyOutsideAllowedRegions"
        Effect    = "Deny"
        NotAction = local.global_service_prefixes
        Resource  = "*"
        Condition = { StringNotEquals = { "aws:RequestedRegion" = var.allowed_regions } }
      },
    ],
    # exfil deny applies everywhere; when exceptions are given it uses NotResource
    # so a team can be granted one specific secret/param without dropping the guard.
    var.deny_data_exfiltration && length(var.data_read_exceptions) == 0 ? [
      { Sid = "DenyDataExfiltration", Effect = "Deny", Action = local.exfiltration_actions, Resource = "*" }
    ] : [],
    var.deny_data_exfiltration && length(var.data_read_exceptions) > 0 ? [
      { Sid = "DenyDataExfiltration", Effect = "Deny", Action = local.exfiltration_actions, NotResource = var.data_read_exceptions }
    ] : [],
    # FinOps: creates must carry the cost tag or the budget guardrail can't see them.
    var.enforce_cost_tag_on_create ? [{
      Sid       = "DenyUntaggedCreate"
      Effect    = "Deny"
      Action    = var.cost_tag_enforced_actions
      Resource  = "*"
      Condition = { Null = { "aws:RequestTag/${var.budget_cost_tag.key}" = "true" } }
    }] : [],
    length(var.extra_denied_actions) > 0 ? [{ Sid = "DenyExtra", Effect = "Deny", Action = var.extra_denied_actions, Resource = "*" }] : [],
    var.kill_switch ? [{ Sid = "KillSwitch", Effect = "Deny", Action = "*", Resource = "*" }] : [],
  )

  boundary_policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.boundary_statements
  })

  # ---- notifications: one topic feeds alerting / budget / digest / break-glass ----
  notifications_wanted = local.create && (var.enable_alerting || var.enable_budget_guardrail || var.enable_daily_digest || var.enable_break_glass)
  create_topic         = local.notifications_wanted && var.alert_sns_topic_arn == ""
  topic_arn            = var.alert_sns_topic_arn != "" ? var.alert_sns_topic_arn : one(aws_sns_topic.alerts[*].arn)

  # the AI role ARN as it appears in CloudTrail's sessionContext (assumed-role).
  role_arn               = one(aws_iam_role.this[*].arn)
  emergency_policy_name  = "ZZZ-EMERGENCY-DENY-ALL"
  killswitch_topic_arn   = one(aws_sns_topic.killswitch[*].arn)
  budget_final_threshold = length(var.budget_alert_thresholds_percent) > 0 ? max(var.budget_alert_thresholds_percent...) : 100

  # break-glass trusts its own (usually smaller) group, falling back to the AI's.
  break_glass_sso_arns = [
    for name in(length(var.break_glass_sso_permission_set_names) > 0 ? var.break_glass_sso_permission_set_names : var.sso_permission_set_names) :
    "arn:${local.partition}:iam::${local.account}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_${name}_*"
  ]

  # ---- SCP: the org-level outer wall ----
  # The boundary is account-local; anyone with iam:* in the account could lift it.
  # This SCP (attach via your org-management stack) stops everyone except the
  # provisioner from touching the AI role or its boundary. The killswitch Lambda's
  # role is auto-exempted so containment keeps working.
  scp_exempt_principals = concat(
    var.provisioner_principal_arns,
    var.enable_budget_killswitch ? ["arn:${local.partition}:iam::*:role/${var.name}-killswitch-lambda"] : [],
  )

  scp_policy = length(var.provisioner_principal_arns) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ProtectAIRoles"
        Effect = "Deny"
        Action = [
          "iam:DeleteRole", "iam:UpdateRole", "iam:UpdateAssumeRolePolicy",
          "iam:PutRolePolicy", "iam:DeleteRolePolicy",
          "iam:AttachRolePolicy", "iam:DetachRolePolicy",
          "iam:PutRolePermissionsBoundary", "iam:DeleteRolePermissionsBoundary",
        ]
        Resource = [
          "arn:${local.partition}:iam::*:role/${var.name}",
          "arn:${local.partition}:iam::*:role/${var.name}-breakglass",
        ]
        Condition = { ArnNotLike = { "aws:PrincipalArn" = local.scp_exempt_principals } }
      },
      {
        Sid    = "ProtectAIBoundaryPolicy"
        Effect = "Deny"
        Action = [
          "iam:DeletePolicy", "iam:DeletePolicyVersion",
          "iam:CreatePolicyVersion", "iam:SetDefaultPolicyVersion",
        ]
        Resource  = ["arn:${local.partition}:iam::*:policy/${var.name}-boundary"]
        Condition = { ArnNotLike = { "aws:PrincipalArn" = var.provisioner_principal_arns } }
      },
    ]
  })

  # ---- team grants (extend the read-only baseline; still capped by boundary) ----
  team_grants_policy = length(var.team_grants) > 0 ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      for s in var.team_grants : merge(
        {
          Sid      = s.sid
          Effect   = "Allow"
          Action   = s.actions
          Resource = s.resources
        },
        length(s.conditions) > 0 ? {
          # IAM shape is operator-first: { test: { variable: values } }; group
          # conditions sharing an operator under one key.
          Condition = {
            for t in distinct([for c in s.conditions : c.test]) :
            t => { for c in s.conditions : c.variable => c.values if c.test == t }
          }
        } : {},
      )
    ]
  }) : null
}
