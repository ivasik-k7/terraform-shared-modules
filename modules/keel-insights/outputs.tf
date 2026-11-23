output "data_bucket" {
  description = "The bucket the management accounts' exports land in: <resource_prefix>-<this account>-data-exports."
  value       = local.create ? local.data_bucket : null
}

output "dashboard_urls" {
  description = "Quick Sight URLs of the foundational dashboards the template reports, by name (CUDOSv5DashboardURL, KPIDashboardURL, CostIntelligenceDashboardURL)."
  value = !local.create ? {} : {
    for k, v in aws_cloudformation_stack.dashboards[0].outputs : k => v if endswith(k, "DashboardURL")
  }
}

output "stacks" {
  description = "The CloudFormation stacks, by role: data_exports, dashboards, and one per plugin dashboard."
  value = !local.create ? {} : merge(
    { data_exports = aws_cloudformation_stack.data_exports_destination[0].name, dashboards = aws_cloudformation_stack.dashboards[0].name },
    { for s in local.plugin_stacks : s.parameters["DashboardId"] => s.name },
  )
}

output "source_requirements" {
  description = "What each management account's keel-billing must set in data_exports for its exports to land here."
  value = !local.create ? null : {
    enabled                = true
    destination_account_id = local.account_id
    version                = var.data_exports.version
    resource_prefix        = var.data_exports.resource_prefix
    cur2                   = var.data_exports.cur2
    focus                  = var.data_exports.focus
    coh                    = var.data_exports.coh
    carbon                 = var.data_exports.carbon
    split_cost_allocation  = var.data_exports.split_cost_allocation
    cur2_granularity       = var.data_exports.cur2_granularity
    focus_granularity      = var.data_exports.focus_granularity
  }
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs here. The templates create IAM roles, S3 buckets, Glue, Athena, Lambda and Quick Sight assets through CloudFormation, which acts with the deployer's permissions."
  value = !local.create ? null : {
    actions = [
      "cloudformation:CreateStack", "cloudformation:UpdateStack", "cloudformation:DeleteStack", "cloudformation:DescribeStacks", "cloudformation:GetTemplate",
      "iam:CreateRole", "iam:DeleteRole", "iam:PutRolePolicy", "iam:DeleteRolePolicy", "iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PassRole", "iam:GetRole", "iam:TagRole",
      "s3:CreateBucket", "s3:DeleteBucket", "s3:PutBucket*", "s3:GetBucket*", "s3:PutEncryptionConfiguration", "s3:PutLifecycleConfiguration", "s3:PutReplicationConfiguration",
      "glue:*Database*", "glue:*Table*", "glue:*Crawler*", "athena:*WorkGroup*",
      "lambda:CreateFunction", "lambda:DeleteFunction", "lambda:InvokeFunction", "lambda:GetFunction", "lambda:UpdateFunction*", "lambda:PublishLayerVersion",
      "quicksight:*",
    ]
    note = "AWS publishes a narrower least-privilege policy for the deployer as cfn-templates/cid-admin-policies.yaml in the CID framework repository."
  }
}

output "governance" {
  description = "The posture as data."
  value = !local.create ? null : {
    region                  = local.region
    data_bucket             = local.data_bucket
    source_account_ids      = sort(var.data_exports.source_account_ids)
    tables                  = { cur2 = var.data_exports.cur2, focus = var.data_exports.focus, coh = var.data_exports.coh, carbon = var.data_exports.carbon }
    dashboards              = concat(var.dashboards.cudos_v5 ? ["cudos-v5"] : [], var.dashboards.kpi ? ["kpi"] : [], var.dashboards.cost_intelligence ? ["cost-intelligence"] : [], local.wanted_plugins)
    template_versions       = { data_exports = var.data_exports.version, dashboards = var.dashboards.version }
    shared_with_all_users   = var.quicksight.share_dashboards
    dashboards_without_data = local.dashboards_without_data
    acknowledged_checks     = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "Read-only commands to run from CloudShell in this account after an apply."
  value = !local.create ? null : {
    exports_arriving = "aws s3 ls s3://${local.data_bucket}/ --recursive | tail -5"
    tables           = "aws glue get-tables --database-name ${replace(var.data_exports.resource_prefix, "-", "_")}_data_export --query 'TableList[].Name'"
    stacks           = "aws cloudformation describe-stacks --query \"Stacks[?starts_with(StackName, '${var.name}-cid')].[StackName,StackStatus]\" --output table"
    dashboards       = "aws quicksight list-dashboards --aws-account-id ${local.account_id} --query 'DashboardSummaryList[].[Name,LastPublishedTime]' --output table"
  }
}
