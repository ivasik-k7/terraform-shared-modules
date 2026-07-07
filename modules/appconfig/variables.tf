# ============================================================================
# GENERAL
# ============================================================================

variable "create" {
  description = "Master switch. When false the module creates nothing (rendered outputs still work)."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Name of the AppConfig application (and prefix for module-created IAM/SNS resources)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9._-]{1,64}$", var.name))
    error_message = "name must be 1-64 chars: letters, numbers, dot, underscore, hyphen."
  }
}

variable "description" {
  description = "Description of the application."
  type        = string
  default     = ""
  nullable    = false
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ============================================================================
# ENVIRONMENTS - deployment targets; alarms make rollback automatic
# ============================================================================

variable "environments" {
  description = <<-EOT
    Map of environments (key = environment name). Attach CloudWatch alarm ARNs
    and AppConfig rolls back a deployment automatically the moment one fires
    during rollout or bake. The module creates the monitor role AppConfig needs
    to read the alarms (or bring your own via monitor_role_arn).
  EOT
  type = map(object({
    description = optional(string, "")
    alarm_arns  = optional(list(string), [])
    tags        = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  # AppConfig allows at most 5 monitors per environment
  validation {
    condition     = alltrue([for k, e in var.environments : length(e.alarm_arns) <= 5])
    error_message = "environments[*].alarm_arns: AppConfig supports at most 5 monitors per environment."
  }
}

variable "monitor_role_arn" {
  description = "Bring-your-own IAM role AppConfig assumes to read alarm state (needs cloudwatch:DescribeAlarms). Empty = the module creates one when any environment has alarms."
  type        = string
  default     = ""
  nullable    = false
}

# ============================================================================
# PROFILES - the configurations themselves (typed feature flags or freeform)
# ============================================================================

variable "profiles" {
  description = <<-EOT
    Map of configuration profiles (key = profile name).

    type = "feature-flags": declare flags in plain HCL - the module renders the
    AWS.AppConfig.FeatureFlags JSON format (version/flags/values, attribute
    constraints, type-correct values) so you never hand-write it. Attribute
    values are passed as strings and cast by their declared type.

    type = "freeform": pass `content` (jsonencode/yamlencode it yourself) for a
    hosted configuration, or point location_uri at SSM/S3/Secrets Manager and
    supply retrieval_role_arn. An optional JSON-Schema or Lambda validator
    rejects bad content before it can ever be deployed.
  EOT
  type = map(object({
    description  = optional(string, "")
    type         = optional(string, "freeform") # freeform | feature-flags
    location_uri = optional(string, "hosted")

    # hosted content (freeform)
    content      = optional(string, "")
    content_type = optional(string, "application/json")

    # external sources (non-hosted freeform)
    retrieval_role_arn = optional(string, "")

    # validators (freeform only - feature flags are validated natively by AppConfig)
    json_schema          = optional(string, "")
    lambda_validator_arn = optional(string, "")

    # feature flags (type = "feature-flags")
    flags = optional(map(object({
      description = optional(string, "")
      enabled     = bool
      attributes = optional(map(object({
        type     = string               # string | number | boolean
        value    = optional(string, "") # stringly-typed; cast by `type` at render
        required = optional(bool, false)
        # optional constraints
        enum    = optional(list(string), [])
        pattern = optional(string, "")
        minimum = optional(number)
        maximum = optional(number)
      })), {})
      # env-specific VALUES (constraints stay global). any override makes the
      # profile env-specialized: one generated profile per environment declared
      # IN THIS STATE; deployments resolve to the right one automatically.
      # overrides for environments not declared here are ignored - that is what
      # lets one shared flags definition serve per-env tfvars workspaces (the
      # dev workspace renders dev values, prod renders prod, same code).
      per_environment = optional(map(object({
        enabled    = optional(bool)            # null = inherit the base value
        attributes = optional(map(string), {}) # attr name => value override
      })), {})
    })), {})

    kms_key_arn = optional(string, "")
    tags        = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, p in var.profiles : contains(["freeform", "feature-flags"], p.type)])
    error_message = "profiles[*].type must be \"freeform\" or \"feature-flags\"."
  }

  # feature-flag profiles: flags only, hosted only, no freeform leftovers
  validation {
    condition = alltrue([
      for k, p in var.profiles :
      p.type != "feature-flags" || (length(p.flags) > 0 && p.content == "" && p.location_uri == "hosted")
    ])
    error_message = "feature-flags profiles must define flags, leave content empty, and use the hosted store."
  }

  # freeform profiles must have content (hosted) or an external location - not both
  validation {
    condition = alltrue([
      for k, p in var.profiles :
      p.type != "freeform" || (p.location_uri == "hosted" ? true : p.content == "")
    ])
    error_message = "freeform profiles with an external location_uri must not set hosted content."
  }

  # external sources need a retrieval role
  validation {
    condition = alltrue([
      for k, p in var.profiles :
      p.location_uri == "hosted" || p.retrieval_role_arn != ""
    ])
    error_message = "profiles with an external location_uri need retrieval_role_arn (AppConfig reads the source with it)."
  }

  # validators are a freeform concept; flags have a native schema
  validation {
    condition = alltrue([
      for k, p in var.profiles :
      p.type != "feature-flags" || (p.json_schema == "" && p.lambda_validator_arn == "")
    ])
    error_message = "json_schema / lambda_validator_arn are for freeform profiles - feature flags are validated natively."
  }

  # attribute types and values must agree so the render can cast safely
  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : [
          for ak, a in f.attributes : contains(["string", "number", "boolean"], a.type)
        ]
      ]
    ]))
    error_message = "flag attribute type must be string, number, or boolean."
  }

  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : [
          for ak, a in f.attributes :
          a.value == "" ? true : (
            a.type == "number" ? can(tonumber(a.value)) :
            a.type == "boolean" ? contains(["true", "false"], lower(a.value)) : true
          )
        ]
      ]
    ]))
    error_message = "flag attribute values must be castable to their declared type (number => numeric string, boolean => \"true\"/\"false\")."
  }

  # required attributes must carry a value - AppConfig rejects the version otherwise
  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : [
          for ak, a in f.attributes : !a.required || a.value != ""
        ]
      ]
    ]))
    error_message = "required flag attributes must have a value."
  }

  # per_environment: overridden attributes must be declared, override values
  # must cast, "" (remove) is not a value. NB: env keys are deliberately NOT
  # validated against environments - foreign keys are ignored so shared flag
  # definitions work across per-env tfvars workspaces.
  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : [
          for ek, pe in f.per_environment : [
            for ak, v in pe.attributes : contains(keys(f.attributes), ak)
          ]
        ]
      ]
    ]))
    error_message = "per_environment attribute overrides must name attributes declared on the flag."
  }

  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : [
          for ek, pe in f.per_environment : [
            # unknown attribute keys are the previous validation's problem -
            # skip them here or the index crashes before it can report
            for ak, v in pe.attributes :
            !contains(keys(f.attributes), ak) ? true : (
              v != "" && (
                f.attributes[ak].type == "number" ? can(tonumber(v)) :
                f.attributes[ak].type == "boolean" ? contains(["true", "false"], lower(v)) : true
              )
            )
          ]
        ]
      ]
    ]))
    error_message = "per_environment override values must be non-empty and castable to the attribute's declared type."
  }

  # flag + attribute names: AppConfig naming rules
  validation {
    condition = alltrue(flatten([
      for k, p in var.profiles : [
        for fk, f in p.flags : can(regex("^[a-zA-Z][a-zA-Z0-9_-]{0,63}$", fk))
      ]
    ]))
    error_message = "flag keys must start with a letter and be 1-64 chars of letters, numbers, underscore, hyphen."
  }
}

# ============================================================================
# DEPLOYMENT STRATEGIES - how carefully config rolls out
# ============================================================================

variable "deployment_strategies" {
  description = <<-EOT
    Custom deployment strategies (key = strategy name). Deployments may also
    reference AWS presets by their literal id (AppConfig.AllAtOnce,
    AppConfig.Linear50PercentEvery30Seconds, AppConfig.Canary10Percent20Minutes)
    without declaring anything here.
  EOT
  type = map(object({
    description                 = optional(string, "")
    deployment_duration_minutes = number
    growth_factor               = optional(number, 20)
    growth_type                 = optional(string, "LINEAR") # LINEAR | EXPONENTIAL
    bake_time_minutes           = optional(number, 10)
    replicate_to                = optional(string, "NONE") # NONE | SSM_DOCUMENT
    tags                        = optional(map(string), {})
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : s.deployment_duration_minutes >= 0 && s.deployment_duration_minutes <= 1440])
    error_message = "deployment_duration_minutes must be 0-1440."
  }

  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : s.growth_factor >= 1 && s.growth_factor <= 100])
    error_message = "growth_factor must be 1-100."
  }

  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : contains(["LINEAR", "EXPONENTIAL"], s.growth_type)])
    error_message = "growth_type must be LINEAR or EXPONENTIAL."
  }

  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : s.bake_time_minutes >= 0 && s.bake_time_minutes <= 1440])
    error_message = "bake_time_minutes must be 0-1440."
  }

  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : contains(["NONE", "SSM_DOCUMENT"], s.replicate_to)])
    error_message = "replicate_to must be NONE or SSM_DOCUMENT."
  }

  # AppConfig.* is the preset namespace - don't shadow it
  validation {
    condition     = alltrue([for k, s in var.deployment_strategies : !startswith(k, "AppConfig.")])
    error_message = "deployment_strategies keys must not start with \"AppConfig.\" (reserved for AWS presets)."
  }
}

variable "default_deployment_strategy" {
  description = "Strategy used by deployments that don't name one. Safety first: the default is a canary with bake time, so all-at-once must be an explicit choice."
  type        = string
  default     = "AppConfig.Canary10Percent20Minutes"
  nullable    = false

  validation {
    condition     = startswith(var.default_deployment_strategy, "AppConfig.") || contains(keys(var.deployment_strategies), var.default_deployment_strategy)
    error_message = "default_deployment_strategy must be an AppConfig.* preset id or a deployment_strategies key."
  }
}

# ============================================================================
# DEPLOYMENTS - config ships like code, never like an edit
# ============================================================================

variable "deployments" {
  description = <<-EOT
    Deployments to manage declaratively. Each entry keeps an environment on a
    profile's hosted version: when the content changes, apply creates a NEW
    hosted version and re-deploys it through the strategy - progressive
    rollout, alarm-watched, auto-rolled-back. GitOps for runtime config.
    For non-hosted profiles set configuration_version explicitly.
  EOT
  type = list(object({
    environment           = string               # key into environments
    profile               = string               # key into profiles
    strategy              = optional(string, "") # key into deployment_strategies, an AppConfig.* preset, or "" = default
    configuration_version = optional(string, "") # override for non-hosted profiles
    description           = optional(string, "")
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for d in var.deployments : contains(keys(var.environments), d.environment)])
    error_message = "deployments[*].environment must be a key of environments."
  }

  validation {
    condition     = alltrue([for d in var.deployments : contains(keys(var.profiles), d.profile)])
    error_message = "deployments[*].profile must be a key of profiles."
  }

  validation {
    condition = alltrue([
      for d in var.deployments :
      d.strategy == "" || startswith(d.strategy, "AppConfig.") || contains(keys(var.deployment_strategies), d.strategy)
    ])
    error_message = "deployments[*].strategy must be \"\", an AppConfig.* preset id, or a deployment_strategies key."
  }

  # one live deployment per environment+profile pair
  validation {
    condition     = length(distinct([for d in var.deployments : "${d.environment}:${d.profile}"])) == length(var.deployments)
    error_message = "deployments must be unique per environment+profile pair."
  }

  # a deployment needs a version: hosted profiles produce one, external ones must say
  validation {
    condition = alltrue([
      for d in var.deployments :
      d.configuration_version != "" ||
      try(var.profiles[d.profile].type == "feature-flags" || (var.profiles[d.profile].location_uri == "hosted" && var.profiles[d.profile].content != ""), false)
    ])
    error_message = "deployments of non-hosted (or empty) profiles need an explicit configuration_version."
  }
}

# ============================================================================
# NOTIFICATIONS - deployment lifecycle events to SNS
# ============================================================================

variable "enable_notifications" {
  description = "Publish deployment lifecycle events (start / complete / rollback by default) to SNS via an AppConfig extension."
  type        = bool
  default     = false
  nullable    = false
}

variable "notification_points" {
  description = "Which lifecycle points notify."
  type        = list(string)
  default     = ["ON_DEPLOYMENT_START", "ON_DEPLOYMENT_COMPLETE", "ON_DEPLOYMENT_ROLLED_BACK"]
  nullable    = false

  validation {
    condition = alltrue([
      for p in var.notification_points :
      contains(["ON_DEPLOYMENT_START", "ON_DEPLOYMENT_STEP", "ON_DEPLOYMENT_BAKING", "ON_DEPLOYMENT_COMPLETE", "ON_DEPLOYMENT_ROLLED_BACK"], p)
    ])
    error_message = "notification_points must be ON_DEPLOYMENT_{START,STEP,BAKING,COMPLETE,ROLLED_BACK}."
  }

  validation {
    condition     = length(var.notification_points) > 0
    error_message = "notification_points must not be empty (disable notifications instead)."
  }
}

variable "alert_sns_topic_arn" {
  description = "Bring-your-own SNS topic for deployment events. Empty = the module creates one when notifications are enabled. BYO topics must allow appconfig.amazonaws.com to publish via the extension role."
  type        = string
  default     = ""
  nullable    = false
}

variable "alert_emails" {
  description = "Email addresses subscribed to the module-created topic (each must confirm). Ignored when alert_sns_topic_arn is set."
  type        = list(string)
  default     = []
  nullable    = false
}
