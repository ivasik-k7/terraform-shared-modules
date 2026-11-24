# ---------------------------------------------------------------------------
# Module
# ---------------------------------------------------------------------------

variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of the CloudFormation stack names."
  type        = string
  default     = "keel"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on the stacks, which CloudFormation passes to the resources it creates. The module adds ManagedBy and Module last."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "acknowledged_checks" {
  description = "Advisory checks this caller has decided to live with, by name (README, \"Advisory checks\")."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.acknowledged_checks : contains(["dashboards_have_their_data"], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

variable "permissions_boundary_arn" {
  description = "Permissions boundary the dashboards template puts on the roles it creates. Empty: none."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.permissions_boundary_arn == "" ? true : can(regex("^arn:aws[a-z-]*:iam::([0-9]{12}|aws):policy/", var.permissions_boundary_arn))
    error_message = "permissions_boundary_arn must be empty or an IAM policy ARN."
  }
}

variable "role_path" {
  description = "IAM path for the roles both templates create, where a boundary or an SCP selects roles by path."
  type        = string
  default     = "/"
  nullable    = false

  validation {
    condition     = can(regex("^/([A-Za-z0-9+=,.@_-]+/)*$", var.role_path))
    error_message = "role_path must be an IAM path, such as / or /finops/."
  }
}

# ---------------------------------------------------------------------------
# Cost data
# ---------------------------------------------------------------------------

variable "data_exports" {
  description = <<-EOT
    The destination side of AWS's Cloud Intelligence Dashboards data pipeline (data-exports-aggregation.yaml): the
    bucket <resource_prefix>-<this account>-data-exports, the Glue database and tables, and the Athena workgroup the
    dashboards read. The source side runs in each management account (keel-billing, data_exports).
      source_account_ids     the management accounts whose exports land here
      version, resource_prefix   the same values as in keel-billing
      cur2, focus, coh, carbon   the tables to create, matching the source side's exports
      lake_formation         yes only if Lake Formation governs the Glue catalog in this account
  EOT
  type = object({
    source_account_ids    = list(string)
    version               = optional(string, "0.13.0")
    resource_prefix       = optional(string, "cid")
    cur2                  = optional(bool, true)
    focus                 = optional(bool, true)
    coh                   = optional(bool, true)
    carbon                = optional(bool, false)
    split_cost_allocation = optional(bool, true)
    cur2_granularity      = optional(string, "HOURLY")
    focus_granularity     = optional(string, "HOURLY")
    lake_formation        = optional(bool, false)
  })
  nullable = false

  validation {
    condition = alltrue([
      length(var.data_exports.source_account_ids) > 0,
      alltrue([for a in var.data_exports.source_account_ids : can(regex("^[0-9]{12}$", a))]),
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.data_exports.version)),
      can(regex("^[a-z0-9][a-z0-9-]{1,35}[a-z0-9]$", var.data_exports.resource_prefix)),
      contains(["HOURLY", "DAILY", "MONTHLY"], var.data_exports.cur2_granularity),
      contains(["HOURLY", "DAILY", "MONTHLY"], var.data_exports.focus_granularity),
    ])
    error_message = "data_exports: one or more 12-digit source_account_ids; version x.y.z; resource_prefix 3-37 lowercase letters, digits and hyphens, not ending in a hyphen (the template's pattern); granularities HOURLY, DAILY or MONTHLY."
  }
}

variable "data_kms_key_arns" {
  description = "Customer managed keys of the data bucket or the Glue catalog, if any: the dashboards template grants its roles decrypt on them."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for k in var.data_kms_key_arns : can(regex("^arn:aws[a-z-]*:kms:[a-z0-9-]+:[0-9]{12}:key/", k))])
    error_message = "data_kms_key_arns must be KMS key ARNs."
  }
}

# ---------------------------------------------------------------------------
# Dashboards
# ---------------------------------------------------------------------------

variable "quicksight" {
  description = <<-EOT
    Amazon Quick Sight in this account and region, which the dashboards run on. Both are prerequisites the module does
    not create: an Enterprise subscription (account-wide, billed per author and reader seat, COSTS.md) and a user.
      user                the Quick Sight user name that owns the dashboards
      subscription_ready  the Enterprise subscription exists with at least 10 GB of SPICE, and Quick Sight may read
                          S3 and Athena. The dashboards template refuses to deploy until this is true
      share_dashboards    every Quick Sight user in the account sees the dashboards
      data_source_role    IAM role name for the data source; the template creates it
  EOT
  type = object({
    user               = string
    subscription_ready = optional(bool, false)
    share_dashboards   = optional(bool, true)
    data_source_role   = optional(string, "CidQuickSightDataSourceRole")
  })
  nullable = false

  validation {
    condition     = var.quicksight.user != "" ? can(regex("^[A-Za-z0-9+=,.@_/-]{1,128}$", var.quicksight.data_source_role)) : false
    error_message = "quicksight: user is required; data_source_role must be an IAM role name."
  }
}

variable "templates" {
  description = <<-EOT
    Where the CID CloudFormation templates come from. They run with CAPABILITY_NAMED_IAM, and AWS's copies sit at
    versioned paths a later upload can overwrite, so a production estate mirrors the reviewed files into a bucket it
    controls (output.templates has each file's reviewed sha256).
      url_prefix                   replaces https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn;
                                   the same layout below it: data-exports/<version>/..., <version>/cid-cfn.yml
      lambda_layer_bucket_prefix   the dashboards template's Lambda layer comes from <prefix>-<region>, key
                                   cid-resource-lambda-layer/cid-<version>.zip, unless this is AWS's own bucket name
  EOT
  type = object({
    url_prefix                 = optional(string, "https://aws-managed-cost-intelligence-dashboards.s3.amazonaws.com/cfn")
    lambda_layer_bucket_prefix = optional(string, "aws-managed-cost-intelligence-dashboards")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      can(regex("^https://[^\\s]+[^/]$", var.templates.url_prefix)),
      can(regex("^[a-z0-9][a-z0-9.-]{1,46}$", var.templates.lambda_layer_bucket_prefix)),
    ])
    error_message = "templates: url_prefix an https URL without a trailing slash; lambda_layer_bucket_prefix an S3 bucket name prefix of 2-47 characters (the Region is appended)."
  }
}

variable "dashboards" {
  description = <<-EOT
    Which Cloud Intelligence Dashboards to deploy (cid-cfn.yml and cid-plugin.yml, the same version).
      version                       the CID template version
      cudos_v5, kpi, cost_intelligence  the foundational dashboards; one at least
      plugins                       further dashboards by ID: focus-dashboard, cora, trends-dashboard,
                                    datatransfer-cost-analysis-dashboard, scad-containers-cost-allocation,
                                    aws-marketplace, amazon-connect-cost-insight-dashboard
      primary_tag, secondary_tag    tag names the dashboards break cost down by (owner, environment)
  EOT
  type = object({
    version           = optional(string, "4.4.21")
    cudos_v5          = optional(bool, true)
    kpi               = optional(bool, true)
    cost_intelligence = optional(bool, true)
    plugins           = optional(list(string), ["focus-dashboard", "cora"])
    primary_tag       = optional(string, "owner")
    secondary_tag     = optional(string, "environment")
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.dashboards.version)),
      var.dashboards.cudos_v5 ? true : (var.dashboards.kpi ? true : var.dashboards.cost_intelligence),
      alltrue([for p in var.dashboards.plugins : contains(["trends-dashboard", "datatransfer-cost-analysis-dashboard", "aws-marketplace", "amazon-connect-cost-insight-dashboard", "scad-containers-cost-allocation", "focus-dashboard", "cora"], p)]),
    ])
    error_message = "dashboards: version x.y.z; at least one of cudos_v5, kpi, cost_intelligence; plugins from the list in the description."
  }
}
