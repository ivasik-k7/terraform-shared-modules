# AWS's own Cloud Intelligence Dashboards data pipeline, source side: the
# exports are created here and delivered to the destination account's bucket.
# The template creates AWS::BCMDataExports::Export directly in us-east-1, and
# through a Lambda-backed custom resource elsewhere; it sets each export's
# S3Region to the stack's own Region, so the stack runs in the destination's.
# https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-data-collection/tree/main/data-exports
locals {
  data_exports_template = "data-exports/${var.data_exports.version}/data-exports-aggregation.yaml"

  # sha256 of the file reviewed for this module, fetched from AWS's bucket.
  data_exports_reviewed_sha256 = lookup({
    "data-exports/0.13.0/data-exports-aggregation.yaml" = "1eba08e62689ecc5feb81ce452e6216ad736897c6d66510be605e5da02855009"
  }, local.data_exports_template, null)
}

resource "aws_cloudformation_stack" "data_exports_source" {
  count = local.create && var.data_exports.enabled ? 1 : 0

  region       = var.data_exports.region
  name         = "${var.name}-cid-data-exports-source"
  template_url = "${var.data_exports.template_url_prefix}/${local.data_exports_template}"
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
