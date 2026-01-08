locals {
  merged_tags = merge(var.common_tags, var.tags)

  repository_statements = [
    for stmt in var.repository_policy_statements : {
      Sid    = stmt.sid
      Effect = stmt.effect
      Principal = stmt.principals == null ? null : (
        stmt.principals.type == "AWS" && length(stmt.principals.identifiers) == 0 ? {
          AWS = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
          } : {
          (stmt.principals.type) = stmt.principals.identifiers
        }
      )
      Action   = stmt.actions
      Resource = stmt.resources != null ? stmt.resources : null
      Condition = length(stmt.conditions) > 0 ? {
        for condition in stmt.conditions : condition.variable => {
          (condition.test) = condition.values
        }
      } : null
    }
  ]

  additional_access_statements = concat(
    [
      for principal in var.allowed_principals : {
        Sid    = "AllowPullPushAccess${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect = "Allow"
        Principal = {
          AWS = [principal]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource  = null
        Condition = null
      }
    ],
    [
      for principal in var.allowed_pull_principals : {
        Sid    = "AllowPullAccess${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect = "Allow"
        Principal = {
          AWS = [principal]
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource  = null
        Condition = null
      }
    ]
  )

  all_policy_statements = concat(
    local.repository_statements,
    local.additional_access_statements
  )

  log_group_name = var.cloudwatch_log_group_name != null ? var.cloudwatch_log_group_name : "/aws/ecr/${var.repository_name}"
}
