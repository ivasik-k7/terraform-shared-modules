variable "create" {
  description = "Create the resources. false plans nothing and leaves every output null or empty."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Prefix of the organization policies' names."
  type        = string
  default     = "keel"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "tags" {
  description = "Tags on the policies. The module adds ManagedBy and Module last."
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
    condition     = alltrue([for c in var.acknowledged_checks : contains(["guardrails_are_attached", "someone_can_break_glass"], c)])
    error_message = "acknowledged_checks names a check that does not exist (README, \"Advisory checks\")."
  }
}

variable "targets" {
  description = "Where the policies attach: the organization root (r-...), OUs (ou-...) or accounts. Attach to a test OU first: an SCP applies to every principal in the accounts below it except the management account."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for t in var.targets : can(regex("^(r-[0-9a-z]{4,32}|ou-[0-9a-z]{4,32}-[a-z0-9]{8,32}|[0-9]{12})$", t))])
    error_message = "targets must be a root ID (r-...), OU IDs (ou-...) or 12-digit account IDs."
  }
}

variable "required_tags" {
  description = <<-EOT
    The mandatory tags, as an organization tag policy, keyed by tag key in the exact case it must have.
      values          allowed values (one * wildcard each); empty: any value
      report_for      resource types where the key is required, for compliance reports and for the AWS
                      provider's tag_policy_compliance check at plan (for example ec2:instance, s3:bucket,
                      rds:ALL_SUPPORTED)
      enforce_for     resource types where a non-compliant tagging operation is refused outright; enforcement
                      applies to tagging operations, not to creating an untagged resource (deny_untagged does that)
    Tag keys and values reach billing systems in us-east-1: never customer or personal data.
  EOT
  type = map(object({
    values      = optional(list(string), [])
    report_for  = optional(list(string), [])
    enforce_for = optional(list(string), [])
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([for k, t in var.required_tags : alltrue([
      can(regex("^[\\p{L}\\p{N}\\s_.:/=+@-]{1,128}$", k)), !startswith(lower(k), "aws:"),
      alltrue([for v in t.values : length(regexall("\\*", v)) <= 1]),
      alltrue([for r in concat(t.report_for, t.enforce_for) : can(regex("^[a-z0-9-]+:([A-Za-z0-9-]+|ALL_SUPPORTED)$", r))]),
    ])])
    error_message = "required_tags: keys are tag keys (not aws:); values have at most one * each; resource types are service:type or service:ALL_SUPPORTED."
  }
}

variable "deny_untagged" {
  description = <<-EOT
    A service control policy that refuses to create resources without the listed tag keys in the request.
      tags              tag keys that must be in the create request (usually a subset of required_tags)
      actions           create actions and the resources they make, action => resource ARN pattern; the
                        defaults are actions that accept aws:RequestTag conditions
      exempt_principals IAM principal ARN patterns the policy does not apply to (break-glass, the account
                        vending pipeline)
  EOT
  type = object({
    enabled = optional(bool, false)
    tags    = optional(list(string), [])
    actions = optional(map(string), {
      "ec2:RunInstances"                        = "arn:*:ec2:*:*:instance/*"
      "ec2:CreateVolume"                        = "arn:*:ec2:*:*:volume/*"
      "rds:CreateDBInstance"                    = "arn:*:rds:*:*:db:*"
      "rds:CreateDBCluster"                     = "arn:*:rds:*:*:cluster:*"
      "lambda:CreateFunction"                   = "arn:*:lambda:*:*:function:*"
      "dynamodb:CreateTable"                    = "arn:*:dynamodb:*:*:table/*"
      "ecs:CreateCluster"                       = "arn:*:ecs:*:*:cluster/*"
      "eks:CreateCluster"                       = "arn:*:eks:*:*:cluster/*"
      "elasticloadbalancing:CreateLoadBalancer" = "arn:*:elasticloadbalancing:*:*:loadbalancer/*"
      "sagemaker:CreateNotebookInstance"        = "arn:*:sagemaker:*:*:notebook-instance/*"
    })
    exempt_principals = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.deny_untagged.enabled ? length(var.deny_untagged.tags) > 0 : true,
      alltrue([for a, r in var.deny_untagged.actions : can(regex("^[a-z0-9-]+:[A-Za-z0-9*]+$", a)) ? startswith(r, "arn:") : false]),
      alltrue([for p in var.deny_untagged.exempt_principals : startswith(p, "arn:")]),
    ])
    error_message = "deny_untagged: enabled needs tags; actions are service:Action => resource ARN patterns; exempt_principals are ARN patterns."
  }
}

variable "bedrock_models" {
  description = <<-EOT
    A service control policy that refuses Bedrock model calls outside an approved list.
      allowed_models    foundation model IDs that may be called (for example anthropic.claude-sonnet-4-6)
      allowed_regions   where those models may run. A call through a cross-Region inference profile is
                        authorized against the model in every Region it may route to, so an in-Region-only
                        list refuses cross-Region profiles
      exempt_principals IAM principal ARN patterns the policy does not apply to
    Model approval stays with model risk; this enforces its decision.
  EOT
  type = object({
    enabled           = optional(bool, false)
    allowed_models    = optional(list(string), [])
    allowed_regions   = optional(list(string), [])
    exempt_principals = optional(list(string), [])
  })
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      var.bedrock_models.enabled ? (length(var.bedrock_models.allowed_models) > 0 ? length(var.bedrock_models.allowed_regions) > 0 : false) : true,
      alltrue([for m in var.bedrock_models.allowed_models : can(regex("^[a-z0-9-]+\\.[A-Za-z0-9.:_-]+$", m))]),
      alltrue([for r in var.bedrock_models.allowed_regions : can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]$", r))]),
      alltrue([for p in var.bedrock_models.exempt_principals : startswith(p, "arn:")]),
    ])
    error_message = "bedrock_models: enabled needs allowed_models (provider.model IDs) and allowed_regions (Region codes); exempt_principals are ARN patterns."
  }
}

variable "ai_services_opt_out" {
  description = <<-EOT
    An AI services opt-out policy: AWS AI services, FinOps Agent among them, do not store or use the organization's
    content to develop or improve their services. The AISERVICES_OPT_OUT_POLICY type must be enabled on the root.
      services   service keys to opt out; "default" covers every AI service, present and future
  EOT
  type = object({
    enabled  = optional(bool, false)
    services = optional(list(string), ["default"])
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.ai_services_opt_out.enabled ? (length(var.ai_services_opt_out.services) > 0 ? alltrue([for s in var.ai_services_opt_out.services : can(regex("^[a-z][a-z0-9-]*$", s))]) : false) : true
    error_message = "ai_services_opt_out.services must be one or more lowercase service keys, such as default."
  }
}
