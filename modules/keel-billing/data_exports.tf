# AWS's own Cloud Intelligence Dashboards data pipeline, source side: the
# exports are created here and delivered to the destination account's bucket.
# The template creates AWS::BCMDataExports::Export directly in us-east-1, and
# through a Lambda-backed custom resource elsewhere.
# https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-data-collection/tree/main/data-exports
resource "aws_cloudformation_stack" "data_exports_source" {
  count = local.create && var.data_exports.enabled ? 1 : 0

  name         = "${var.name}-cid-data-exports-source"
  template_url = "https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn/data-exports/${var.data_exports.version}/data-exports-aggregation.yaml"
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]
  tags         = local.tags

  parameters = {
    DestinationAccountId   = var.data_exports.destination_account_id
    SourceAccountIds       = local.account_id
    ResourcePrefix         = var.data_exports.resource_prefix
    ManageCUR2             = var.data_exports.cur2 ? "yes" : "no"
    ManageFOCUS            = var.data_exports.focus ? "yes" : "no"
    ManageCOH              = var.data_exports.coh ? "yes" : "no"
    ManageCarbon           = var.data_exports.carbon ? "yes" : "no"
    EnableSCAD             = var.data_exports.split_cost_allocation ? "yes" : "no"
    EnableIAMPrincipalData = var.data_exports.iam_principal ? "yes" : "no"
    CUR2TimeGranularity    = var.data_exports.cur2_granularity
    FOCUSTimeGranularity   = var.data_exports.focus_granularity
    RolePath               = var.data_exports.role_path
    LegacyLocalBucket      = "no"
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  # The Cost Optimization Hub export needs the hub enabled first.
  depends_on = [aws_costoptimizationhub_enrollment_status.this]
}
