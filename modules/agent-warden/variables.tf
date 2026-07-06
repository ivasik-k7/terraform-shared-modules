# ============================================================================
# GENERAL
# ============================================================================

variable "create" {
  description = "Master switch. When false the module creates nothing."
  type        = bool
  default     = true
  nullable    = false
}

variable "name" {
  description = "Name of the AI agent role (and prefix for its policies)."
  type        = string
  default     = "ai-agent"
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9+=,.@_-]{1,64}$", var.name))
    error_message = "name must be a valid IAM role name (<=64 chars)."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
  nullable    = false
}

# ============================================================================
# TRUST - who (which SSO users) may assume the AI role
# ============================================================================

variable "sso_permission_set_names" {
  description = <<-EOT
    IAM Identity Center permission-set names whose users may assume the AI role,
    e.g. ["Developer", "PowerUser"]. Matched against the SSO-provisioned role ARN
    (arn:.../aws-reserved/sso.amazonaws.com/AWSReservedSSO_<name>_<hash>). Wildcards allowed.
  EOT
  type        = list(string)
  nullable    = false

  validation {
    condition     = length(var.sso_permission_set_names) > 0
    error_message = "Provide at least one SSO permission-set name to trust."
  }
}

variable "require_source_identity" {
  description = "Require sts:SourceIdentity on assume so every AI action in CloudTrail is attributable to a human. Strongly recommended on a shared account."
  type        = bool
  default     = true
  nullable    = false
}

variable "require_mfa" {
  description = "Require the originating SSO session to have used MFA (aws:MultiFactorAuthPresent). Assume is refused otherwise."
  type        = bool
  default     = false
  nullable    = false
}

variable "allowed_source_ip_cidrs" {
  description = "If set, the AI role may only be assumed from these source IP CIDRs (e.g. TFC runner or corp VPN egress). Empty = any IP."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "access_expires_at" {
  description = "Self-expiring identity: an RFC3339 timestamp (e.g. 2026-12-31T23:59:59Z) after which the role can no longer be assumed. Empty = no expiry."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.access_expires_at == "" || can(formatdate("YYYY-MM-DD", var.access_expires_at))
    error_message = "access_expires_at must be an RFC3339 timestamp (e.g. 2026-12-31T23:59:59Z) or empty."
  }
}

variable "max_session_duration" {
  description = "Max session duration (seconds) for the AI role. Keep short - the agent re-assumes; no long-lived keys."
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = var.max_session_duration >= 900 && var.max_session_duration <= 43200
    error_message = "max_session_duration must be between 900 and 43200 seconds."
  }
}

# ============================================================================
# GUARDRAILS (the hard ceiling - permission boundary)
# ============================================================================

variable "allowed_regions" {
  description = "Regions the AI may operate in. Actions outside these are denied (global services exempt)."
  type        = list(string)
  default     = ["us-east-1"]
  nullable    = false

  validation {
    condition     = length(var.allowed_regions) > 0
    error_message = "Provide at least one allowed region."
  }
}

variable "deny_data_exfiltration" {
  description = "Deny reads of secret/data values (secrets, SSM params, KMS decrypt, S3 objects, DynamoDB items, SQS/Kinesis, Athena results, log events, password data, lambda env). Lets the AI see infra shape but not exfiltrate data."
  type        = bool
  default     = true
  nullable    = false
}

variable "data_read_exceptions" {
  description = "Resource ARNs the exfiltration deny does NOT apply to (e.g. one secret a team genuinely needs). The deny stays in force everywhere else; pair with a team_grant that allows the specific action. Empty = deny everywhere."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "kill_switch" {
  description = "Flip to true to instantly deny ALL actions by the AI role (incident response). Apply via your TFC workflow."
  type        = bool
  default     = false
  nullable    = false
}

# ============================================================================
# PERMISSIONS - baseline read-only; extend per team; optional write sandbox
# ============================================================================

variable "attach_read_only" {
  description = "Attach AWS-managed ReadOnlyAccess as the baseline (still capped by the boundary + exfil deny)."
  type        = bool
  default     = true
  nullable    = false
}

variable "team_grants" {
  description = <<-EOT
    Extra allow statements for specific teams, layered on the read-only baseline.
    ALWAYS capped by the permission boundary (dangerous/exfil/cross-region stay denied).
    This is how you widen access after adding a team to the terraform code.
  EOT
  type = list(object({
    sid       = string
    actions   = list(string)
    resources = optional(list(string), ["*"])
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default  = []
  nullable = false

  validation {
    condition     = length(distinct([for s in var.team_grants : s.sid])) == length(var.team_grants)
    error_message = "team_grants[*].sid must be unique."
  }
}

variable "extra_denied_actions" {
  description = "Additional actions to hard-deny in the boundary (e.g. a service you never want the AI to touch)."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "enforce_cost_tag_on_create" {
  description = "Deny listed create actions unless the request tags the resource with budget_cost_tag.key - makes the budget guardrail measure real spend (untagged creates are invisible to it)."
  type        = bool
  default     = false
  nullable    = false
}

variable "cost_tag_enforced_actions" {
  description = "Create actions the tag-on-create deny applies to. Only add actions whose service documents the aws:RequestTag condition key - services without it would be blocked outright."
  type        = list(string)
  default = [
    "ec2:RunInstances", "ec2:CreateVolume", "ec2:CreateSnapshot",
    "rds:CreateDBInstance", "rds:CreateDBCluster",
    "ecs:RunTask", "ecs:CreateService",
    "eks:CreateCluster",
    "elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup",
  ]
  nullable = false
}

variable "exclusive_inline_policies" {
  description = <<-EOT
    Manage the AI role's inline policies exclusively: anything attached outside
    Terraform (drift, or the killswitch's emergency deny-all) is flagged and removed
    on the next apply. Trade-off: with this on, a routine apply after a budget breach
    LIFTS the emergency containment - gate applies during incidents.
  EOT
  type        = bool
  default     = false
  nullable    = false
}

variable "provisioner_principal_arns" {
  description = "Principal ARNs allowed to manage the AI role/boundary (e.g. your TFC workspace role). Feeds the scp_policy_json output - the org-level outer wall that stops anyone else from lifting the guardrails. Empty = no SCP rendered."
  type        = list(string)
  default     = []
  nullable    = false
}

# ============================================================================
# NOTIFICATIONS - shared SNS topic for alerts / budget / digest
# ============================================================================

variable "alert_sns_topic_arn" {
  description = "Bring-your-own SNS topic for all notifications. Empty = the module creates one when any notification feature is enabled."
  type        = string
  default     = ""
  nullable    = false
}

variable "alert_emails" {
  description = "Email addresses subscribed to the module-created SNS topic. Each must confirm the subscription. Ignored when alert_sns_topic_arn is set."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "alerts_kms_key_id" {
  description = "Customer-managed KMS key id/alias to encrypt the module-created SNS topics. MUST grant events.amazonaws.com and budgets.amazonaws.com kms:GenerateDataKey*/Decrypt, or cross-service publish fails. Empty = no SSE (the AWS-managed alias/aws/sns key would block those services)."
  type        = string
  default     = ""
  nullable    = false
}

variable "lambda_log_retention_days" {
  description = "Retention for the killswitch/digest Lambda log groups. Managed so logs don't accrue forever."
  type        = number
  default     = 30
  nullable    = false
}

# ============================================================================
# ACTIVE ATTRIBUTION - real-time alerting + daily digest
# ============================================================================

variable "enable_alerting" {
  description = "Real-time alert (via EventBridge + SNS) whenever the AI role performs a high-risk action or the break-glass role is assumed. Turns recordable attribution into watched attribution."
  type        = bool
  default     = false
  nullable    = false
}

variable "high_risk_event_names" {
  description = "CloudTrail event names that trigger a real-time alert when performed by the AI role."
  type        = list(string)
  default = [
    "CreateBucket", "DeleteBucket", "PutBucketPolicy",
    "RunInstances", "TerminateInstances",
    "CreateAccessKey", "CreateUser", "CreateRole", "AttachRolePolicy", "PutRolePolicy",
    "AuthorizeSecurityGroupIngress", "ModifyDBInstance", "DeleteDBInstance",
    "PutParameter", "PutSecretValue", "CreateSecret",
  ]
  nullable = false
}

variable "enable_daily_digest" {
  description = "A scheduled Lambda that summarises the AI role's activity over the last 24h (who, what, how often) and publishes it to SNS."
  type        = bool
  default     = false
  nullable    = false
}

variable "digest_schedule" {
  description = "EventBridge schedule expression for the daily digest (UTC)."
  type        = string
  default     = "cron(0 13 * * ? *)"
  nullable    = false
}

variable "digest_event_data_store_arn" {
  description = "BYO CloudTrail Lake event data store ARN for the digest. When set, the digest runs a server-side SQL query (scales to busy shared accounts); empty = LookupEvents fallback (throttled at ~2 req/s, may truncate on busy accounts)."
  type        = string
  default     = ""
  nullable    = false
}

# ============================================================================
# FINOPS GUARDRAIL - budget + optional auto kill-switch
# ============================================================================

variable "enable_budget_guardrail" {
  description = "Track spend attributable to the AI (by cost-allocation tag) against a monthly budget and alert on thresholds."
  type        = bool
  default     = false
  nullable    = false
}

variable "monthly_budget_usd" {
  description = "Monthly USD budget for AI-attributed spend. Required (> 0) when enable_budget_guardrail is true."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.monthly_budget_usd >= 0
    error_message = "monthly_budget_usd must be >= 0."
  }

  # a $0 budget breaches immediately - with the killswitch that means instant deny-all on apply.
  validation {
    condition     = !var.enable_budget_guardrail || var.monthly_budget_usd > 0
    error_message = "Set monthly_budget_usd > 0 when enable_budget_guardrail is true."
  }
}

variable "budget_cost_tag" {
  description = "Cost-allocation tag {key,value} used to attribute spend to the AI. Must be an activated cost-allocation tag in Billing."
  type = object({
    key   = string
    value = string
  })
  default = {
    key   = "Purpose"
    value = "ai-agent"
  }
  nullable = false
}

variable "budget_alert_thresholds_percent" {
  description = "Percent-of-budget thresholds (ACTUAL spend) that trigger an alert (e.g. [80, 100])."
  type        = list(number)
  default     = [80, 100]
  nullable    = false
}

variable "budget_forecasted_threshold_percent" {
  description = "FORECASTED-spend threshold that alerts before the money is gone (Budgets cost data lags ~8-24h; the forecast fires earlier). 0 = disabled. Alerts only - never triggers the killswitch."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.budget_forecasted_threshold_percent >= 0
    error_message = "budget_forecasted_threshold_percent must be >= 0 (0 disables it)."
  }
}

variable "enable_budget_killswitch" {
  description = "When true, a breach of the final budget threshold invokes a Lambda that attaches an emergency deny-all policy to the AI role - auto-containment. Codify it afterward by setting kill_switch = true. Requires enable_budget_guardrail."
  type        = bool
  default     = false
  nullable    = false

  validation {
    condition     = !var.enable_budget_killswitch || var.enable_budget_guardrail
    error_message = "enable_budget_killswitch requires enable_budget_guardrail = true (the budget is what triggers it)."
  }
}

# ============================================================================
# BREAK-GLASS - time-boxed elevated role for emergencies
# ============================================================================

variable "enable_break_glass" {
  description = "Create a separate, elevated, MFA-gated, short-lived break-glass role for emergencies. Every assumption is alerted (when enable_alerting is on)."
  type        = bool
  default     = false
  nullable    = false
}

variable "break_glass_sso_permission_set_names" {
  description = "SSO permission-set names allowed to assume the break-glass role. Empty = reuse sso_permission_set_names. Set this to a smaller, senior group - break-glass is elevated."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "break_glass_policy_arns" {
  description = "Managed policy ARNs attached to the break-glass role."
  type        = list(string)
  default     = ["arn:aws:iam::aws:policy/PowerUserAccess"]
  nullable    = false
}

variable "break_glass_max_session_duration" {
  description = "Max session duration (seconds) for the break-glass role. Keep short."
  type        = number
  default     = 3600
  nullable    = false

  validation {
    condition     = var.break_glass_max_session_duration >= 900 && var.break_glass_max_session_duration <= 43200
    error_message = "break_glass_max_session_duration must be between 900 and 43200 seconds."
  }
}
