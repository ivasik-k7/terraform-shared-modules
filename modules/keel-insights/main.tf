locals {
  create = var.create

  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")
  region     = coalesce(one(data.aws_region.current[*].region), "eu-west-2")

  module_tags = { ManagedBy = "Terraform", Module = "keel-insights" }
  tags        = merge(var.tags, local.module_tags)

  acknowledged = toset(var.acknowledged_checks)

  # AWS's published CID templates, by version.
  # https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-framework/tree/main/terraform/cicd-deployment
  template_base = "https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn"
  templates = {
    data_exports = "${local.template_base}/data-exports/${var.data_exports.version}/data-exports-aggregation.yaml"
    dashboards   = "${local.template_base}/${var.dashboards.version}/cid-cfn.yml"
    plugin       = "${local.template_base}/${var.dashboards.version}/cid-plugin.yml"
  }
  capabilities = ["CAPABILITY_IAM", "CAPABILITY_NAMED_IAM"]
  yes_no       = { true = "yes", false = "no" }

  data_bucket = "${var.data_exports.resource_prefix}-${local.account_id}-data-exports"

  # Plugin stacks deploy one after another, in this order, as AWS's own
  # Terraform does: in parallel they conflict over shared Quick Sight assets.
  plugin_order = [
    "trends-dashboard", "datatransfer-cost-analysis-dashboard", "aws-marketplace",
    "amazon-connect-cost-insight-dashboard", "scad-containers-cost-allocation", "focus-dashboard", "cora",
  ]
  plugin_parameters = {
    "aws-marketplace" = { RequiresDataCollection = "no" }
  }
  wanted_plugins = [for p in local.plugin_order : p if contains(var.dashboards.plugins, p)]
}

resource "aws_cloudformation_stack" "data_exports_destination" {
  count = local.create ? 1 : 0

  name         = "${var.name}-cid-data-exports-destination"
  template_url = local.templates.data_exports
  capabilities = local.capabilities
  tags         = local.tags

  parameters = {
    DestinationAccountId = local.account_id
    SourceAccountIds     = join(",", var.data_exports.source_account_ids)
    ResourcePrefix       = var.data_exports.resource_prefix
    ManageCUR2           = local.yes_no[var.data_exports.cur2]
    ManageFOCUS          = local.yes_no[var.data_exports.focus]
    ManageCOH            = local.yes_no[var.data_exports.coh]
    ManageCarbon         = local.yes_no[var.data_exports.carbon]
    EnableSCAD           = local.yes_no[var.data_exports.split_cost_allocation]
    CUR2TimeGranularity  = var.data_exports.cur2_granularity
    FOCUSTimeGranularity = var.data_exports.focus_granularity
    LakeFormationEnabled = local.yes_no[var.data_exports.lake_formation]
    RolePath             = var.role_path
    LegacyLocalBucket    = "no"
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }
}

resource "aws_cloudformation_stack" "dashboards" {
  count = local.create ? 1 : 0

  name         = "${var.name}-cid-dashboards"
  template_url = local.templates.dashboards
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Foundational" })

  parameters = {
    PrerequisitesQuickSight            = local.yes_no[var.quicksight.subscription_ready]
    PrerequisitesQuickSightPermissions = local.yes_no[var.quicksight.subscription_ready]
    QuickSightUser                     = var.quicksight.user
    QuickSightDataSourceRoleName       = var.quicksight.data_source_role
    ShareDashboard                     = local.yes_no[var.quicksight.share_dashboards]
    CURVersion                         = "2.0"
    DeployCUDOSv5                      = local.yes_no[var.dashboards.cudos_v5]
    DeployKPIDashboard                 = local.yes_no[var.dashboards.kpi]
    DeployCostIntelligenceDashboard    = local.yes_no[var.dashboards.cost_intelligence]
    DeployCUDOSDashboard               = "no"
    LakeFormationEnabled               = local.yes_no[var.data_exports.lake_formation]
    PrimaryTagName                     = var.dashboards.primary_tag
    SecondaryTagName                   = var.dashboards.secondary_tag
    DataBucketsKmsKeysArns             = join(",", var.data_kms_key_arns)
    PermissionsBoundary                = var.permissions_boundary_arn
    RolePath                           = var.role_path
    DeploymentType                     = "Terraform"
  }

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  lifecycle {
    # cid-cfn.yml accepts only "yes" for both prerequisite parameters.
    # https://github.com/aws-solutions-library-samples/cloud-intelligence-dashboards-framework/blob/main/cfn-templates/cid-cfn.yml
    precondition {
      condition     = var.quicksight.subscription_ready
      error_message = "quicksight.subscription_ready is false. The dashboards template refuses to deploy until Quick Sight has an Enterprise subscription in this account and region, at least 10 GB of SPICE capacity, and access to S3 and Athena. Set them up, then set subscription_ready = true."
    }
  }

  depends_on = [aws_cloudformation_stack.data_exports_destination]
}

resource "aws_cloudformation_stack" "plugin_1" {
  count = local.create && length(local.wanted_plugins) >= 1 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[0]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[0] })
  parameters   = merge({ DashboardId = local.wanted_plugins[0] }, lookup(local.plugin_parameters, local.wanted_plugins[0], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.dashboards]
}

resource "aws_cloudformation_stack" "plugin_2" {
  count = local.create && length(local.wanted_plugins) >= 2 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[1]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[1] })
  parameters   = merge({ DashboardId = local.wanted_plugins[1] }, lookup(local.plugin_parameters, local.wanted_plugins[1], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_1]
}

resource "aws_cloudformation_stack" "plugin_3" {
  count = local.create && length(local.wanted_plugins) >= 3 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[2]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[2] })
  parameters   = merge({ DashboardId = local.wanted_plugins[2] }, lookup(local.plugin_parameters, local.wanted_plugins[2], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_2]
}

resource "aws_cloudformation_stack" "plugin_4" {
  count = local.create && length(local.wanted_plugins) >= 4 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[3]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[3] })
  parameters   = merge({ DashboardId = local.wanted_plugins[3] }, lookup(local.plugin_parameters, local.wanted_plugins[3], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_3]
}

resource "aws_cloudformation_stack" "plugin_5" {
  count = local.create && length(local.wanted_plugins) >= 5 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[4]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[4] })
  parameters   = merge({ DashboardId = local.wanted_plugins[4] }, lookup(local.plugin_parameters, local.wanted_plugins[4], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_4]
}

resource "aws_cloudformation_stack" "plugin_6" {
  count = local.create && length(local.wanted_plugins) >= 6 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[5]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[5] })
  parameters   = merge({ DashboardId = local.wanted_plugins[5] }, lookup(local.plugin_parameters, local.wanted_plugins[5], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_5]
}

resource "aws_cloudformation_stack" "plugin_7" {
  count = local.create && length(local.wanted_plugins) >= 7 ? 1 : 0

  name         = "${var.name}-cid-${local.wanted_plugins[6]}"
  template_url = local.templates.plugin
  capabilities = local.capabilities
  tags         = merge(local.tags, { DashboardType = "Additional", DashboardId = local.wanted_plugins[6] })
  parameters   = merge({ DashboardId = local.wanted_plugins[6] }, lookup(local.plugin_parameters, local.wanted_plugins[6], {}))

  timeouts {
    create = "30m"
    update = "30m"
    delete = "30m"
  }

  depends_on = [aws_cloudformation_stack.plugin_6]
}

locals {
  plugin_stacks = concat(
    aws_cloudformation_stack.plugin_1, aws_cloudformation_stack.plugin_2, aws_cloudformation_stack.plugin_3,
    aws_cloudformation_stack.plugin_4, aws_cloudformation_stack.plugin_5, aws_cloudformation_stack.plugin_6,
    aws_cloudformation_stack.plugin_7,
  )
}
