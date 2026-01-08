locals {
  merged_tags = merge(var.common_tags, var.tags)

  lifecycle_rules_final = var.lifecycle_rules != [] ? var.lifecycle_rules : (
    var.untagged_image_retention_days != null || var.max_image_count != null ? [
      {
        rule_priority = 1
        description   = "Expire untagged images older than X days"
        tag_status    = "untagged"
        count_type    = "sinceImagePushed"
        count_unit    = "days"
        count_number  = var.untagged_image_retention_days != null ? var.untagged_image_retention_days : 7
        action_type   = "expire"
      },
      {
        rule_priority = 2
        description   = "Keep last X tagged images"
        tag_status    = "any"
        count_type    = "imageCountMoreThan"
        count_number  = var.max_image_count != null ? var.max_image_count : 100
        action_type   = "expire"
      }
    ] : var.lifecycle_rules
  )

  repository_statements = [
    for stmt in var.repository_policy_statements : {
      Sid    = stmt.sid
      Effect = stmt.effect
      Principal = stmt.principals == null ? null : (
        stmt.principals.type == "AWS" && length(stmt.principals.identifiers) == 0 ? {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
          } : {
          (stmt.principals.type) = stmt.principals.identifiers
        }
      )
      Action   = stmt.actions
      Resource = stmt.resources != null ? stmt.resources : ["${aws_ecr_repository.this.arn}"]
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
        Sid    = "AllowPullPushAccess-${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect = "Allow"
        Principal = {
          AWS = principal
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
        Resource = ["${aws_ecr_repository.this.arn}"]
      }
    ],
    [
      for principal in var.allowed_pull_principals : {
        Sid    = "AllowPullAccess-${replace(principal, "/[^a-zA-Z0-9]/", "")}"
        Effect = "Allow"
        Principal = {
          AWS = principal
        }
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = ["${aws_ecr_repository.this.arn}"]
      }
    ]
  )

  all_policy_statements = concat(
    local.repository_statements,
    local.additional_access_statements
  )

  log_group_name = var.cloudwatch_log_group_name != null ? var.cloudwatch_log_group_name : "/aws/ecr/${var.repository_name}"
}
