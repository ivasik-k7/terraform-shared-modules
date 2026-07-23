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
  description = "Web ACL name (also prefixes IP sets, regex sets, and metric names)."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9-_]{1,128}$", var.name))
    error_message = "name must be 1-128 chars: letters, numbers, hyphen, underscore."
  }
}

variable "description" {
  description = "Web ACL description."
  type        = string
  default     = "Managed by Terraform"
  nullable    = false
}

variable "scope" {
  description = "CLOUDFRONT (global; provider MUST be us-east-1) or REGIONAL (ALB/API Gateway/AppSync/Cognito in the provider's region)."
  type        = string
  default     = "CLOUDFRONT"
  nullable    = false

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be CLOUDFRONT or REGIONAL."
  }
}

variable "default_action" {
  description = "Action for requests no rule matches: allow (default; use rules to block bad traffic) or block (default-deny; allowlist good traffic)."
  type        = string
  default     = "allow"
  nullable    = false

  validation {
    condition     = contains(["allow", "block"], var.default_action)
    error_message = "default_action must be allow or block."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "count_mode" {
  description = "Global dry-run: force EVERY module-owned block action (IP block, geo, rate, custom, and managed overrides) to Count. The correct way to onboard WAF on live traffic - observe in the logs/metrics, then set false to enforce. NOTE: it cannot convert default_action = block to Count (WAF has no count default), so onboard default-deny ACLs with default_action = allow first."
  type        = bool
  default     = false
  nullable    = false
}

variable "captcha_immunity_seconds" {
  description = "ACL-wide CAPTCHA immunity: how long a solved CAPTCHA is trusted before re-challenge. Null = AWS default (300s)."
  type        = number
  default     = null
}

variable "challenge_immunity_seconds" {
  description = "ACL-wide Challenge immunity time. Null = AWS default (300s)."
  type        = number
  default     = null
}

# ============================================================================
# BASELINE PRESET - AWS best-practice protections in one flag
# ============================================================================

variable "enable_baseline" {
  description = "Prepend a curated AWS-managed baseline (Common, KnownBadInputs, IP reputation, and - unless disabled - a blanket rate limit). Experts turn this off and compose their own."
  type        = bool
  default     = true
  nullable    = false
}

variable "baseline_rate_limit" {
  description = "Requests per 5-minute window per client IP for the baseline blanket rate rule. 0 disables just the rate rule (other baseline groups stay)."
  type        = number
  default     = 2000
  nullable    = false

  validation {
    condition     = var.baseline_rate_limit == 0 || (var.baseline_rate_limit >= 10 && var.baseline_rate_limit <= 20000000)
    error_message = "baseline_rate_limit must be 0 (disabled) or between 10 and 20000000."
  }
}

variable "baseline_count_only" {
  description = "Run the baseline managed groups in Count mode (observe, don't block) - the safe way to onboard WAF on live traffic before enforcing."
  type        = bool
  default     = false
  nullable    = false
}

# ============================================================================
# MANAGED RULE GROUPS - AWS + AWS Marketplace vendor groups
# ============================================================================

variable "managed_rule_groups" {
  description = <<-EOT
    AWS/vendor managed rule groups, in evaluation order (priority auto-assigned).
    Pin `version` for change-controlled environments. `count_only` observes
    without blocking; `rule_action_overrides` flips individual sub-rules
    (name => allow|block|count|captcha|challenge) - the modern replacement for
    excluded_rules.
  EOT
  type = list(object({
    name                  = string # e.g. AWSManagedRulesCommonRuleSet
    vendor                = optional(string, "AWS")
    version               = optional(string)
    count_only            = optional(bool, false)
    rule_action_overrides = optional(map(string), {})
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue(flatten([
      for g in var.managed_rule_groups : [
        for act in values(g.rule_action_overrides) : contains(["allow", "block", "count", "captcha", "challenge"], act)
      ]
    ]))
    error_message = "managed_rule_groups[*].rule_action_overrides values must be allow|block|count|captcha|challenge."
  }
}

# ============================================================================
# RATE-BASED RULES
# ============================================================================

variable "rate_based_rules" {
  description = <<-EOT
    Rate limits. limit = requests per evaluation_window per aggregation key.
    aggregate_key: IP | FORWARDED_IP (behind proxies/CloudFront) | CONSTANT
    (a blanket cap). Optional scope_down narrows what counts (e.g. only /login).
  EOT
  type = list(object({
    name              = string
    limit             = number
    action            = optional(string, "block") # block|count|captcha|challenge
    aggregate_key     = optional(string, "IP")    # IP|FORWARDED_IP|CONSTANT
    evaluation_window = optional(number, 300)     # 60|120|300|600 seconds
    # optional scope-down: count only requests whose URI contains this substring
    # and/or originate from these countries (both -> AND).
    scope_down = optional(object({
      uri_path_contains = optional(string, "")
      country_codes     = optional(list(string), [])
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.rate_based_rules : r.limit >= 10 && r.limit <= 20000000])
    error_message = "rate_based_rules[*].limit must be between 10 and 20000000."
  }
  validation {
    condition     = alltrue([for r in var.rate_based_rules : contains(["IP", "FORWARDED_IP", "CONSTANT"], r.aggregate_key)])
    error_message = "rate_based_rules[*].aggregate_key must be IP, FORWARDED_IP, or CONSTANT."
  }
  validation {
    condition     = alltrue([for r in var.rate_based_rules : contains([60, 120, 300, 600], r.evaluation_window)])
    error_message = "rate_based_rules[*].evaluation_window must be 60, 120, 300, or 600 seconds."
  }
  validation {
    condition     = alltrue([for r in var.rate_based_rules : contains(["block", "count", "captcha", "challenge"], r.action)])
    error_message = "rate_based_rules[*].action must be block|count|captcha|challenge."
  }
}

# ============================================================================
# IP ALLOW / BLOCK - module creates the IP sets
# ============================================================================

variable "ip_allow_lists" {
  description = "Named allowlists (CIDR lists). Matching requests are ALLOWED and evaluation stops (short-circuits ALL later rules incl. managed groups - use narrowly). Keyed map; each list must be single-version (IPv4 or IPv6, not mixed)."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.ip_allow_lists :
      length([for c in v : c if strcontains(c, ":")]) == 0 || length([for c in v : c if strcontains(c, ":")]) == length(v)
    ])
    error_message = "Each ip_allow_lists entry must be all IPv4 or all IPv6 - WAF IP sets are single-version. Split mixed lists into separate keys."
  }
}

variable "ip_block_lists" {
  description = "Named blocklists (CIDR lists). Matching requests are BLOCKED. Keyed map; each list must be single-version (IPv4 or IPv6, not mixed)."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.ip_block_lists :
      length([for c in v : c if strcontains(c, ":")]) == 0 || length([for c in v : c if strcontains(c, ":")]) == length(v)
    ])
    error_message = "Each ip_block_lists entry must be all IPv4 or all IPv6 - WAF IP sets are single-version. Split mixed lists into separate keys."
  }
}

variable "ip_address_version_default" {
  description = "Fallback IP version when a list is empty (can't be inferred). IPV4 or IPV6."
  type        = string
  default     = "IPV4"
  nullable    = false

  validation {
    condition     = contains(["IPV4", "IPV6"], var.ip_address_version_default)
    error_message = "ip_address_version_default must be IPV4 or IPV6."
  }
}

variable "ip_reference_rules" {
  description = <<-EOT
    Rules against EXISTING (externally-managed) IP sets referenced by ARN - e.g.
    a central threat-intelligence feed or a shared proxy allowlist maintained by
    another team/stack. The module does NOT create these sets; it references them.
      action: block | count | allow
      negate = true -> matches when the source IP is NOT in the set (the classic
               "block anything not on the proxy allowlist" pattern).
    Evaluated right after the module-created IP block lists, before geo.
  EOT
  type = list(object({
    name   = string
    arn    = string
    action = optional(string, "block") # block|count|allow|captcha|challenge
    negate = optional(bool, false)
    # match the forwarded client IP (e.g. CloudFront's X-Forwarded-For) instead
    # of the TCP source IP. Essential when the set holds real viewer IPs.
    forwarded_ip = optional(object({
      header_name       = optional(string, "X-Forwarded-For")
      position          = optional(string, "ANY")   # FIRST|LAST|ANY
      fallback_behavior = optional(string, "MATCH") # MATCH|NO_MATCH
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.ip_reference_rules : contains(["block", "count", "allow", "captcha", "challenge"], r.action)])
    error_message = "ip_reference_rules[*].action must be block|count|allow|captcha|challenge."
  }
  validation {
    condition     = alltrue([for r in var.ip_reference_rules : can(regex("^arn:aws[a-z-]*:wafv2:", r.arn))])
    error_message = "ip_reference_rules[*].arn must be a wafv2 IP set ARN."
  }
  validation {
    condition     = length(distinct([for r in var.ip_reference_rules : r.name])) == length(var.ip_reference_rules)
    error_message = "ip_reference_rules[*].name must be unique."
  }
  validation {
    condition     = alltrue([for r in var.ip_reference_rules : r.forwarded_ip == null ? true : contains(["FIRST", "LAST", "ANY"], r.forwarded_ip.position)])
    error_message = "ip_reference_rules[*].forwarded_ip.position must be FIRST|LAST|ANY."
  }
  validation {
    condition     = alltrue([for r in var.ip_reference_rules : r.forwarded_ip == null ? true : contains(["MATCH", "NO_MATCH"], r.forwarded_ip.fallback_behavior)])
    error_message = "ip_reference_rules[*].forwarded_ip.fallback_behavior must be MATCH|NO_MATCH."
  }
}

# ============================================================================
# GEO MATCH
# ============================================================================

variable "geo_block_countries" {
  description = "ISO 3166-1 alpha-2 country codes to BLOCK outright (e.g. [\"CN\",\"RU\"]). Empty = no geo block."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.geo_block_countries : can(regex("^[A-Z]{2}$", c))])
    error_message = "geo_block_countries must be 2-letter uppercase ISO country codes."
  }
}

variable "geo_allow_countries" {
  description = "If set, block every country NOT listed (allowlist geo model). Mutually exclusive with a default-block ACL that already allowlists. Empty = disabled."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for c in var.geo_allow_countries : can(regex("^[A-Z]{2}$", c))])
    error_message = "geo_allow_countries must be 2-letter uppercase ISO country codes."
  }

  validation {
    condition     = length(var.geo_block_countries) == 0 || length(var.geo_allow_countries) == 0
    error_message = "Set geo_block_countries OR geo_allow_countries, not both (opposite models)."
  }
}

# ============================================================================
# CUSTOM MATCH RULES - byte / regex / size, single-condition
# ============================================================================

variable "custom_rules" {
  description = <<-EOT
    Custom match rules (priority auto-assigned). Each inspects one field with one
    match type. field: uri_path|query_string|single_header|method|body|
    all_query_args. type: byte(=exact/contains/starts/ends)|regex|size|regex_set.
    For arbitrary nested AND/OR/NOT logic beyond this, compose managed groups +
    these; WAFv2's recursive statements aren't expressible in flat HCL.
  EOT
  type = list(object({
    name              = string
    action            = optional(string, "block")    # allow|block|count|captcha|challenge
    phase             = optional(string, "post")     # "pre" = before managed groups (rescue false positives); "post" = after
    field             = optional(string, "uri_path") # uri_path|query_string|method|body|all_query_args|single_header (ignored for type=label)
    header_name       = optional(string)             # required when field = single_header
    type              = string                       # contains|starts_with|ends_with|exactly|regex|regex_set|size|label
    value             = optional(string)             # byte/regex value, or the label string for type=label
    size_operator     = optional(string)             # size: GT|GE|LT|LE|EQ|NE
    size              = optional(number)             # size (bytes)
    regex_patterns    = optional(list(string), [])   # regex_set
    text_transform    = optional(string, "NONE")     # NONE|LOWERCASE|URL_DECODE|COMPRESS_WHITE_SPACE|HTML_ENTITY_DECODE
    oversize_handling = optional(string, "CONTINUE") # body only: CONTINUE|MATCH|NO_MATCH (MATCH for size-GT-cap checks)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["allow", "block", "count", "captcha", "challenge"], r.action)])
    error_message = "custom_rules[*].action must be allow|block|count|captcha|challenge."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["uri_path", "query_string", "method", "body", "all_query_args", "single_header"], r.field)])
    error_message = "custom_rules[*].field must be uri_path|query_string|method|body|all_query_args|single_header."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["contains", "starts_with", "ends_with", "exactly", "regex", "regex_set", "size", "label"], r.type)])
    error_message = "custom_rules[*].type must be contains|starts_with|ends_with|exactly|regex|regex_set|size|label."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : r.field != "single_header" || (r.header_name != null && r.header_name != "")])
    error_message = "custom_rules with field=single_header require header_name."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : r.type != "size" || (r.size != null && contains(["GT", "GE", "LT", "LE", "EQ", "NE"], coalesce(r.size_operator, "GT")))])
    error_message = "custom_rules with type=size require size and a valid size_operator (GT|GE|LT|LE|EQ|NE)."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : r.type != "regex_set" || length(r.regex_patterns) > 0])
    error_message = "custom_rules with type=regex_set require at least one regex_patterns entry."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["contains", "starts_with", "ends_with", "exactly", "regex"], r.type) ? (r.value != null && r.value != "") : true])
    error_message = "custom_rules with a byte/regex type require a non-empty value."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["pre", "post"], r.phase)])
    error_message = "custom_rules[*].phase must be \"pre\" (before managed groups) or \"post\" (after)."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : r.type != "label" || (r.value != null && r.value != "")])
    error_message = "custom_rules with type=label require value = the label string to match."
  }
  validation {
    condition     = alltrue([for r in var.custom_rules : contains(["CONTINUE", "MATCH", "NO_MATCH"], r.oversize_handling)])
    error_message = "custom_rules[*].oversize_handling must be CONTINUE|MATCH|NO_MATCH."
  }
}

# ============================================================================
# CUSTOM RESPONSES - branded/typed block pages
# ============================================================================

variable "custom_response_bodies" {
  description = "Named response bodies referenced by block actions. key => {content_type, content}. content_type: TEXT_PLAIN|TEXT_HTML|APPLICATION_JSON."
  type = map(object({
    content_type = string
    content      = string
  }))
  default  = {}
  nullable = false

  validation {
    condition     = alltrue([for k, v in var.custom_response_bodies : contains(["TEXT_PLAIN", "TEXT_HTML", "APPLICATION_JSON"], v.content_type)])
    error_message = "custom_response_bodies[*].content_type must be TEXT_PLAIN|TEXT_HTML|APPLICATION_JSON."
  }
}

variable "block_response" {
  description = "Default response for BLOCK actions: HTTP status + optional custom_response_body_key (must exist in custom_response_bodies). Null = AWS default 403."
  type = object({
    status_code              = number
    custom_response_body_key = optional(string)
    response_headers         = optional(map(string), {})
  })
  default  = null
  nullable = true
}

# ============================================================================
# TOKEN DOMAINS (CAPTCHA/Challenge/Bot token sharing)
# ============================================================================

variable "token_domains" {
  description = "Domains that may share WAF tokens (CAPTCHA/Challenge/Bot Control). Include your apex + subdomains for SPA/multi-origin sites."
  type        = list(string)
  default     = []
  nullable    = false
}

# ============================================================================
# LOGGING
# ============================================================================

variable "enable_logging" {
  description = "Enable WAF logging to the destination ARN. Requires log_destination_arn."
  type        = bool
  default     = false
  nullable    = false
}

variable "log_destination_arn" {
  description = "Destination for WAF logs: a CloudWatch Logs group ARN (name must start with aws-waf-logs-), a Kinesis Firehose ARN, or an S3 bucket ARN. Created elsewhere and referenced here."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = !var.enable_logging || var.log_destination_arn != ""
    error_message = "log_destination_arn is required when enable_logging is true."
  }
}

variable "log_redacted_fields" {
  description = "Fields to redact from logs (PII/secrets). Each: {type=uri_path|query_string|method|single_header, header_name=...}."
  type = list(object({
    type        = string
    header_name = optional(string)
  }))
  default  = []
  nullable = false

  validation {
    condition     = alltrue([for f in var.log_redacted_fields : contains(["uri_path", "query_string", "method", "single_header"], f.type)])
    error_message = "log_redacted_fields[*].type must be uri_path|query_string|method|single_header."
  }

  validation {
    condition     = alltrue([for f in var.log_redacted_fields : f.type != "single_header" || (f.header_name != null && f.header_name != "")])
    error_message = "log_redacted_fields with type=single_header require header_name."
  }
}

variable "log_filter" {
  description = "Optional logging filter: default_behavior KEEP|DROP plus filters. Null = log everything. Use to log only blocked/counted requests and cut volume."
  type = object({
    default_behavior = string # KEEP | DROP
    filters = list(object({
      behavior    = string                        # KEEP | DROP
      requirement = optional(string, "MEETS_ANY") # MEETS_ANY | MEETS_ALL
      conditions = list(object({
        action_condition = optional(string) # ALLOW|BLOCK|COUNT|CAPTCHA|CHALLENGE|EXCLUDED_AS_COUNT
        label_name       = optional(string)
      }))
    }))
  })
  default  = null
  nullable = true
}

# ============================================================================
# ASSOCIATION (REGIONAL scope only)
# ============================================================================

variable "associate_resource_arns" {
  description = "REGIONAL scope only: ARNs of ALB/API Gateway stage/AppSync/Cognito to associate. CLOUDFRONT associates by setting web_acl_id on the distribution instead (use the web_acl_arn output)."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.associate_resource_arns) == 0 || var.scope == "REGIONAL"
    error_message = "associate_resource_arns is only valid when scope = REGIONAL (CloudFront references the ACL via web_acl_id on the distribution)."
  }
}
