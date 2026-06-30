locals {
  # Unified tagging: one effective tag set. common_tags is the deprecated alias
  # kept for backward compatibility; tags wins on key conflicts.
  merged_tags = merge(var.common_tags, var.tags)

  # Resolve the single repository_access object, merging the DEPRECATED flat
  # inputs on top so existing callers keep working.
  ra             = var.repository_access
  policy_enabled = var.create_repository_policy && local.ra.enabled
  account_access = local.ra.account_access

  # null when create = false (data sources are gated). Fallbacks keep the
  # account-root ARN template from interpolating null; the value is unused in
  # that case because no policy is rendered.
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")
  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")

  eff_push_principals = distinct(concat(local.ra.push_principals, var.allowed_principals))
  eff_pull_principals = distinct(concat(local.ra.pull_principals, var.allowed_pull_principals))
  eff_statements      = concat(local.ra.statements, var.repository_policy_statements)

  # SECURE BASELINE (repository_access.account_access): own account gets pull/push
  # + read, but NOT destructive or policy-rewriting actions (DeleteRepository /
  # BatchDeleteImage / Set|DeleteRepositoryPolicy). Lives here so callers can't
  # accidentally clobber it - they layer on top instead.
  default_repository_statements = local.account_access ? [
    {
      sid        = "AllowAccountPullPush"
      effect     = "Allow"
      principals = { type = "AWS", identifiers = [] }
      actions = [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:BatchCheckLayerAvailability",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:DescribeRepositories",
        "ecr:GetRepositoryPolicy",
        "ecr:ListImages",
      ]
      resources  = null
      conditions = []
    }
  ] : []

  # Normalize baseline + custom statements to ONE uniform shape so concat/flatten
  # never trips over mismatched element types (Resource always list(string);
  # Condition always list - empties are dropped when the JSON is rendered).
  # Iterating the two raw-typed sources separately (not a raw concat) keeps their
  # differing optional-attribute types from colliding.
  repository_statements = flatten([
    for src in [local.default_repository_statements, local.eff_statements] : [
      for stmt in src : {
        Sid    = stmt.sid
        Effect = stmt.effect
        Principal = stmt.principals == null ? null : (
          # F1: a "*" principal must render as {"AWS":["*"]} (public), never {"*":[...]}.
          stmt.principals.type == "*" || contains(stmt.principals.identifiers, "*") ? { AWS = ["*"] } : (
            stmt.principals.type == "AWS" && length(stmt.principals.identifiers) == 0 ? {
              AWS = ["arn:${local.partition}:iam::${local.account_id}:root"]
              } : {
              (stmt.principals.type) = stmt.principals.identifiers
            }
          )
        )
        Action    = stmt.actions
        Resource  = coalesce(stmt.resources, [])
        Condition = stmt.conditions
      }
    ]
  ])

  additional_access_statements = concat(
    [
      for principal in local.eff_push_principals : {
        Sid       = "AllowPullPushAccess${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect    = "Allow"
        Principal = { AWS = [principal] }
        Action    = concat(local.ecr_pull_actions, local.ecr_push_actions)
        Resource  = []
        Condition = []
      }
    ],
    [
      for principal in local.eff_pull_principals : {
        Sid       = "AllowPullAccess${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect    = "Allow"
        Principal = { AWS = [principal] }
        Action    = local.ecr_pull_actions
        Resource  = []
        Condition = []
      }
    ]
  )

  all_policy_statements = concat(
    local.repository_statements,
    local.additional_access_statements
  )

  log_group_name = var.cloudwatch_log_group_name != null ? var.cloudwatch_log_group_name : "/aws/ecr/${var.repository_name}"

  repository_arn = local.create ? aws_ecr_repository.this[0].arn : null

  # repo-scoped IDENTITY policies consumers attach to their OWN roles (ECS task /
  # execution role, CodeBuild, Lambda, etc.) for least-privilege ECR access.
  # ecr:GetAuthorizationToken is a registry-level action -> Resource must be "*".
  ecr_pull_actions = [
    "ecr:GetDownloadUrlForLayer",
    "ecr:BatchGetImage",
    "ecr:BatchCheckLayerAvailability",
  ]
  ecr_push_actions = [
    "ecr:PutImage",
    "ecr:InitiateLayerUpload",
    "ecr:UploadLayerPart",
    "ecr:CompleteLayerUpload",
  ]

  pull_policy_json = local.create ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrPull", Effect = "Allow", Action = local.ecr_pull_actions, Resource = local.repository_arn },
      { Sid = "EcrAuthToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
  }) : null

  push_policy_json = local.create ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "EcrPullPush", Effect = "Allow", Action = concat(local.ecr_pull_actions, local.ecr_push_actions), Resource = local.repository_arn },
      { Sid = "EcrAuthToken", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
    ]
  }) : null
}
