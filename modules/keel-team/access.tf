locals {
  finops_access = local.account ? var.finops_access.trusted_account_id != "" : false
}

# ---------------------------------------------------------------------------
# FinOps read-only: cost, usage, commitments, recommendations and resource
# metadata; no object, table, secret or log content
# ---------------------------------------------------------------------------

resource "aws_iam_role" "finops_read" {
  count = local.finops_access ? 1 : 0

  name                 = var.finops_access.role_name
  description          = "The FinOps team reads ${var.team}'s cost, usage and resource metadata"
  max_session_duration = 3600
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { AWS = length(var.finops_access.trusted_role_arns) > 0 ? var.finops_access.trusted_role_arns : [
        "arn:${local.partition}:iam::${var.finops_access.trusted_account_id}:root"
      ] }
      Action = "sts:AssumeRole"
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "finops_read" {
  count = local.finops_access ? 1 : 0

  name = "finops-read"
  role = aws_iam_role.finops_read[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CostAndUsage"
        Effect = "Allow"
        Action = [
          "ce:Get*", "ce:Describe*", "ce:List*",
          "budgets:ViewBudget", "budgets:Describe*",
          "billing:Get*", "billing:List*", "cur:Describe*", "bcm-data-exports:Get*", "bcm-data-exports:List*",
          "savingsplans:Describe*", "freetier:Get*", "pricing:*",
          "cost-optimization-hub:Get*", "cost-optimization-hub:List*",
          "compute-optimizer:Get*", "compute-optimizer:Describe*",
          "servicequotas:Get*", "servicequotas:List*",
        ]
        Resource = "*"
      },
      {
        Sid    = "ResourceMetadata"
        Effect = "Allow"
        Action = [
          "tag:GetResources", "tag:GetTagKeys", "tag:GetTagValues",
          "ec2:Describe*", "autoscaling:Describe*", "elasticloadbalancing:Describe*",
          "rds:Describe*", "rds:ListTagsForResource", "ecs:Describe*", "ecs:List*", "eks:Describe*", "eks:List*",
          "lambda:ListFunctions", "lambda:GetFunctionConfiguration", "s3:ListAllMyBuckets", "s3:GetBucketTagging",
          "s3:GetLifecycleConfiguration", "s3:GetBucketLocation", "dynamodb:DescribeTable", "dynamodb:ListTables",
          "bedrock:ListInferenceProfiles", "bedrock:GetInferenceProfile", "bedrock:ListFoundationModels",
          "logs:DescribeLogGroups", "cloudwatch:GetMetricData", "cloudwatch:GetMetricStatistics", "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms", "support:DescribeTrustedAdvisor*",
        ]
        Resource = "*"
      },
    ]
  })
}
