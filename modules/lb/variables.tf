# ============================================================================
# CORE LOAD BALANCER
# ============================================================================

variable "create" {
  description = "Master switch. When false the module creates nothing."
  type        = bool
  default     = true
}

variable "name" {
  description = "Name of the load balancer (max 32 chars, alphanumeric and hyphens)"
  type        = string

  validation {
    condition     = length(var.name) <= 32 && can(regex("^[a-zA-Z0-9-]+$", var.name))
    error_message = "Load balancer name must be <= 32 characters and contain only letters, numbers, and hyphens."
  }
}

variable "load_balancer_type" {
  description = "Type of load balancer: 'application' (ALB) or 'network' (NLB). Gateway LBs are out of scope."
  type        = string
  default     = "application"

  validation {
    condition     = contains(["application", "network"], var.load_balancer_type)
    error_message = "load_balancer_type must be 'application' or 'network'."
  }
}

variable "internal" {
  description = "Whether the load balancer is internal (private). False creates an internet-facing LB."
  type        = bool
  default     = false
}

variable "vpc_id" {
  description = "VPC ID. Required when create_security_group is true or when target groups of type instance/ip are created without their own vpc_id."
  type        = string
  default     = null

  validation {
    condition     = !var.create_security_group || var.vpc_id != null
    error_message = "vpc_id is required when create_security_group is true."
  }
}

variable "subnets" {
  description = "List of subnet IDs to attach. Mutually exclusive with subnet_mappings."
  type        = list(string)
  default     = []
}

variable "subnet_mappings" {
  description = "List of subnet mappings (use instead of subnets for NLB static/elastic IPs)."
  type = list(object({
    subnet_id            = string
    allocation_id        = optional(string)
    private_ipv4_address = optional(string)
    ipv6_address         = optional(string)
  }))
  default = []
}

variable "ip_address_type" {
  description = "The type of IP addresses used by the subnets: 'ipv4', 'dualstack', or 'dualstack-without-public-ipv4'."
  type        = string
  default     = "ipv4"

  validation {
    condition     = contains(["ipv4", "dualstack", "dualstack-without-public-ipv4"], var.ip_address_type)
    error_message = "ip_address_type must be 'ipv4', 'dualstack', or 'dualstack-without-public-ipv4'."
  }
}

# --- ALB-only attributes (ignored for NLB) -----------------------------------

variable "idle_timeout" {
  description = "The time in seconds that the connection is allowed to be idle (application only)."
  type        = number
  default     = 60
}

variable "enable_http2" {
  description = "Whether HTTP/2 is enabled (application only)."
  type        = bool
  default     = true
}

variable "drop_invalid_header_fields" {
  description = "Whether invalid header fields are removed before reaching the target (application only)."
  type        = bool
  default     = true
}

variable "preserve_host_header" {
  description = "Whether the LB preserves the Host header and forwards it unmodified (application only)."
  type        = bool
  default     = false
}

variable "desync_mitigation_mode" {
  description = "How the LB handles requests that pose a security risk: 'monitor', 'defensive', or 'strictest' (application only)."
  type        = string
  default     = "defensive"
}

variable "client_keep_alive" {
  description = "Client keep-alive value in seconds (application only)."
  type        = number
  default     = null
}

variable "enable_xff_client_port" {
  description = "Whether the X-Forwarded-For header preserves the client port (application only)."
  type        = bool
  default     = null
}

variable "xff_header_processing_mode" {
  description = "How the X-Forwarded-For header is processed: 'append', 'preserve', or 'remove' (application only)."
  type        = string
  default     = null

  validation {
    condition     = var.xff_header_processing_mode == null || contains(["append", "preserve", "remove"], var.xff_header_processing_mode)
    error_message = "xff_header_processing_mode must be 'append', 'preserve', or 'remove'."
  }
}

variable "enable_waf_fail_open" {
  description = "Whether to allow a WAF-enabled LB to route requests when WAF is unavailable (application only)."
  type        = bool
  default     = null
}

variable "enable_tls_version_and_cipher_suite_headers" {
  description = "Whether the two TLS headers (version and cipher suite) are added to the client request (application only)."
  type        = bool
  default     = null
}

# --- NLB attributes ----------------------------------------------------------

variable "enable_cross_zone_load_balancing" {
  description = "Whether cross-zone load balancing is enabled (network; ALB is always on)."
  type        = bool
  default     = true
}

variable "enforce_security_group_inbound_rules_on_private_link_traffic" {
  description = "Whether inbound SG rules are enforced for PrivateLink traffic: 'on' or 'off' (network only)."
  type        = string
  default     = null

  validation {
    condition     = var.enforce_security_group_inbound_rules_on_private_link_traffic == null || contains(["on", "off"], var.enforce_security_group_inbound_rules_on_private_link_traffic)
    error_message = "enforce_security_group_inbound_rules_on_private_link_traffic must be 'on' or 'off'."
  }
}

# --- Common attributes -------------------------------------------------------

variable "enable_deletion_protection" {
  description = "Whether deletion protection is enabled."
  type        = bool
  default     = false
}

variable "access_logs" {
  description = "S3 access logging configuration (application/network)."
  type = object({
    bucket  = string
    prefix  = optional(string)
    enabled = optional(bool, true)
  })
  default = null
}

variable "connection_logs" {
  description = "S3 connection logging configuration (application only)."
  type = object({
    bucket  = string
    prefix  = optional(string)
    enabled = optional(bool, true)
  })
  default = null
}

variable "timeouts" {
  description = "Operation timeouts for the load balancer."
  type = object({
    create = optional(string, "10m")
    update = optional(string, "10m")
    delete = optional(string, "10m")
  })
  default = {}
}

# ============================================================================
# SECURITY GROUP
# ============================================================================

variable "create_security_group" {
  description = "Whether to create a security group for the load balancer (application, and optionally network)."
  type        = bool
  default     = true
}

variable "security_group_ids" {
  description = "Additional existing security group IDs to attach to the load balancer."
  type        = list(string)
  default     = []
}

variable "security_group_ingress_rules" {
  description = "Map of ingress rules for the created security group. Each rule sets one source (cidr_ipv4/cidr_ipv6/referenced_security_group_id/prefix_list_id)."
  type = map(object({
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "tcp")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
    prefix_list_id               = optional(string)
    description                  = optional(string)
  }))
  default = {}
}

variable "security_group_egress_rules" {
  description = "Map of egress rules for the created security group. Defaults to allow-all."
  type = map(object({
    from_port                    = optional(number)
    to_port                      = optional(number)
    ip_protocol                  = optional(string, "-1")
    cidr_ipv4                    = optional(string)
    cidr_ipv6                    = optional(string)
    referenced_security_group_id = optional(string)
    prefix_list_id               = optional(string)
    description                  = optional(string)
  }))
  default = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  }
}

# ============================================================================
# TARGET GROUPS
# ============================================================================

variable "target_groups" {
  description = <<-EOT
    Map of target groups to create. Key is a stable identifier used to reference
    the group from listeners and rules. target_type may be 'instance', 'ip',
    'lambda', or 'alb'. Optional `targets` create static attachments (useful
    outside ECS/Kubernetes-controller setups). Lambda targets automatically get
    an invoke permission unless create_lambda_permission is false.
  EOT
  type = map(object({
    name                          = optional(string)
    name_prefix                   = optional(string)
    port                          = optional(number)
    protocol                      = optional(string)
    protocol_version              = optional(string)
    target_type                   = optional(string, "instance")
    vpc_id                        = optional(string)
    deregistration_delay          = optional(number)
    slow_start                    = optional(number)
    load_balancing_algorithm_type = optional(string)
    preserve_client_ip            = optional(string)
    proxy_protocol_v2             = optional(bool)
    connection_termination        = optional(bool)
    ip_address_type               = optional(string)
    create_lambda_permission      = optional(bool, true)
    health_check = optional(object({
      enabled             = optional(bool)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
      interval            = optional(number)
      timeout             = optional(number)
      path                = optional(string)
      port                = optional(string)
      protocol            = optional(string)
      matcher             = optional(string)
    }))
    stickiness = optional(object({
      enabled         = optional(bool, true)
      type            = string
      cookie_duration = optional(number)
      cookie_name     = optional(string)
    }))
    target_failover = optional(object({
      on_deregistration = string
      on_unhealthy      = string
    }))
    target_health_state = optional(object({
      enable_unhealthy_connection_termination = optional(bool)
      unhealthy_draining_interval             = optional(number)
    }))
    target_group_health = optional(object({
      dns_failover = optional(object({
        minimum_healthy_targets_count      = optional(string)
        minimum_healthy_targets_percentage = optional(string)
      }))
      unhealthy_state_routing = optional(object({
        minimum_healthy_targets_count      = optional(number)
        minimum_healthy_targets_percentage = optional(string)
      }))
    }))
    targets = optional(map(object({
      target_id         = string
      port              = optional(number)
      availability_zone = optional(string)
    })), {})
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, tg in var.target_groups : contains(["instance", "ip", "lambda", "alb"], tg.target_type)])
    error_message = "target_groups[*].target_type must be one of 'instance', 'ip', 'lambda', or 'alb'."
  }

  validation {
    condition     = alltrue([for k, tg in var.target_groups : tg.target_type == "lambda" || tg.port != null])
    error_message = "target_groups[*].port is required unless target_type is 'lambda'."
  }

  validation {
    condition     = alltrue([for k, tg in var.target_groups : tg.target_type == "lambda" || tg.vpc_id != null || var.vpc_id != null])
    error_message = "target_groups of type instance/ip/alb need a vpc_id (set it on the target group or via the module-level vpc_id)."
  }

  validation {
    condition = alltrue([
      for k, tg in var.target_groups :
      tg.target_type == "lambda" || tg.protocol == null || (
        var.load_balancer_type == "application"
        ? contains(["HTTP", "HTTPS"], tg.protocol)
        : contains(["TCP", "UDP", "TCP_UDP", "TLS"], tg.protocol)
      )
    ])
    error_message = "target_groups protocol must be HTTP/HTTPS for application LBs and TCP/UDP/TCP_UDP/TLS for network LBs."
  }
}

# ============================================================================
# LISTENERS
# ============================================================================

variable "listeners" {
  description = <<-EOT
    Map of listeners. Key is a stable identifier referenced by listener_rules.
    default_action.type is 'forward', 'redirect', or 'fixed-response'. Set
    authenticate_cognito or authenticate_oidc to require edge authentication
    before the main action. Certificate(s) switch the listener to HTTPS/TLS.
  EOT
  type = map(object({
    port                        = number
    protocol                    = optional(string)
    ssl_policy                  = optional(string)
    certificate_arn             = optional(string)
    additional_certificate_arns = optional(list(string), [])
    alpn_policy                 = optional(string)
    tcp_idle_timeout_seconds    = optional(number)
    mutual_authentication = optional(object({
      mode                             = string
      trust_store_arn                  = optional(string)
      ignore_client_certificate_expiry = optional(bool)
    }))
    default_action = object({
      type             = string
      target_group_key = optional(string)
      target_groups = optional(list(object({
        target_group_key = string
        weight           = optional(number)
      })))
      stickiness = optional(object({
        enabled  = optional(bool, true)
        duration = number
      }))
      redirect = optional(object({
        status_code = string
        host        = optional(string)
        path        = optional(string)
        port        = optional(string)
        protocol    = optional(string)
        query       = optional(string)
      }))
      fixed_response = optional(object({
        content_type = string
        message_body = optional(string)
        status_code  = optional(string)
      }))
      authenticate_cognito = optional(object({
        user_pool_arn                       = string
        user_pool_client_id                 = string
        user_pool_domain                    = string
        authentication_request_extra_params = optional(map(string))
        on_unauthenticated_request          = optional(string)
        scope                               = optional(string)
        session_cookie_name                 = optional(string)
        session_timeout                     = optional(number)
      }))
      authenticate_oidc = optional(object({
        authorization_endpoint              = string
        client_id                           = string
        client_secret                       = string
        issuer                              = string
        token_endpoint                      = string
        user_info_endpoint                  = string
        authentication_request_extra_params = optional(map(string))
        on_unauthenticated_request          = optional(string)
        scope                               = optional(string)
        session_cookie_name                 = optional(string)
        session_timeout                     = optional(number)
      }))
    })
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, l in var.listeners : contains(["forward", "redirect", "fixed-response"], l.default_action.type)])
    error_message = "listeners[*].default_action.type must be 'forward', 'redirect', or 'fixed-response'."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      l.default_action.type != "forward" || l.default_action.target_group_key != null || (l.default_action.target_groups != null && length(coalesce(l.default_action.target_groups, [])) > 0)
    ])
    error_message = "A 'forward' listener default_action requires target_group_key or a non-empty target_groups list."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      (l.default_action.target_group_key == null || contains(keys(var.target_groups), l.default_action.target_group_key)) &&
      (l.default_action.target_groups == null || alltrue([for t in l.default_action.target_groups : contains(keys(var.target_groups), t.target_group_key)]))
    ])
    error_message = "listeners default_action references a target_group_key that is not defined in target_groups."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      l.protocol == null || (
        var.load_balancer_type == "application"
        ? contains(["HTTP", "HTTPS"], l.protocol)
        : contains(["TCP", "UDP", "TCP_UDP", "TLS"], l.protocol)
      )
    ])
    error_message = "Listener protocol must be HTTP/HTTPS for application LBs and TCP/UDP/TCP_UDP/TLS for network LBs."
  }

  validation {
    condition = alltrue([
      for k, l in var.listeners :
      l.protocol == null || !contains(["HTTPS", "TLS"], l.protocol) || l.certificate_arn != null
    ])
    error_message = "HTTPS and TLS listeners require a certificate_arn."
  }
}

# ============================================================================
# LISTENER RULES
# ============================================================================

variable "listener_rules" {
  description = <<-EOT
    Map of listener rules. Each rule references a listener_key, has a priority,
    one or more actions, and one or more conditions. Each condition object sets
    exactly one matcher. Actions may include authenticate_cognito/authenticate_oidc.
  EOT
  type = map(object({
    listener_key = string
    priority     = number
    actions = list(object({
      type             = string
      target_group_key = optional(string)
      target_groups = optional(list(object({
        target_group_key = string
        weight           = optional(number)
      })))
      redirect = optional(object({
        status_code = string
        host        = optional(string)
        path        = optional(string)
        port        = optional(string)
        protocol    = optional(string)
        query       = optional(string)
      }))
      fixed_response = optional(object({
        content_type = string
        message_body = optional(string)
        status_code  = optional(string)
      }))
      authenticate_cognito = optional(object({
        user_pool_arn                       = string
        user_pool_client_id                 = string
        user_pool_domain                    = string
        authentication_request_extra_params = optional(map(string))
        on_unauthenticated_request          = optional(string)
        scope                               = optional(string)
        session_cookie_name                 = optional(string)
        session_timeout                     = optional(number)
      }))
      authenticate_oidc = optional(object({
        authorization_endpoint              = string
        client_id                           = string
        client_secret                       = string
        issuer                              = string
        token_endpoint                      = string
        user_info_endpoint                  = string
        authentication_request_extra_params = optional(map(string))
        on_unauthenticated_request          = optional(string)
        scope                               = optional(string)
        session_cookie_name                 = optional(string)
        session_timeout                     = optional(number)
      }))
    }))
    conditions = list(object({
      path_patterns = optional(list(string))
      host_headers  = optional(list(string))
      http_header = optional(object({
        name   = string
        values = list(string)
      }))
      query_strings = optional(list(object({
        key   = optional(string)
        value = string
      })))
      source_ips           = optional(list(string))
      http_request_methods = optional(list(string))
    }))
    tags = optional(map(string), {})
  }))
  default = {}

  validation {
    condition     = alltrue([for k, r in var.listener_rules : r.priority >= 1 && r.priority <= 50000])
    error_message = "listener_rules[*].priority must be between 1 and 50000."
  }

  validation {
    condition     = alltrue([for k, r in var.listener_rules : length(r.conditions) > 0 && length(r.actions) > 0])
    error_message = "Each listener rule must have at least one condition and one action."
  }

  validation {
    condition     = alltrue([for k, r in var.listener_rules : contains(keys(var.listeners), r.listener_key)])
    error_message = "listener_rules[*].listener_key must reference an existing listener."
  }

  validation {
    condition = alltrue([
      for k, r in var.listener_rules : alltrue([
        for a in r.actions :
        (a.target_group_key == null || contains(keys(var.target_groups), a.target_group_key)) &&
        (a.target_groups == null || alltrue([for t in a.target_groups : contains(keys(var.target_groups), t.target_group_key)]))
      ])
    ])
    error_message = "listener_rules actions reference a target_group_key that is not defined in target_groups."
  }
}

# ============================================================================
# WAF / ROUTE 53 / ALARMS
# ============================================================================

variable "web_acl_arn" {
  description = "ARN of a WAFv2 web ACL to associate with the load balancer (application only)."
  type        = string
  default     = null
}

variable "route53_records" {
  description = "Map of Route 53 alias records pointing at the load balancer."
  type = map(object({
    zone_id                = string
    name                   = string
    type                   = optional(string, "A")
    evaluate_target_health = optional(bool, true)
  }))
  default = {}
}

variable "create_cloudwatch_alarms" {
  description = "Create CloudWatch alarms for the load balancer and its target groups."
  type        = bool
  default     = false
}

variable "alarm_5xx_threshold" {
  description = "Alarm when HTTPCode_ELB_5XX_Count exceeds this over a period (application only)."
  type        = number
  default     = 10
}

variable "alarm_target_response_time_threshold" {
  description = "Alarm when TargetResponseTime (seconds) exceeds this (application only)."
  type        = number
  default     = 2
}

variable "alarm_unhealthy_host_threshold" {
  description = "Alarm when a target group's UnHealthyHostCount is at or above this value."
  type        = number
  default     = 1
}

variable "alarm_evaluation_periods" {
  description = "Number of evaluation periods for the CloudWatch alarms."
  type        = number
  default     = 3
}

variable "alarm_period" {
  description = "Period in seconds for each CloudWatch alarm statistic."
  type        = number
  default     = 60
}

variable "alarm_actions" {
  description = "List of ARNs (e.g. SNS topics) notified when an alarm enters ALARM."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "List of ARNs notified when an alarm returns to OK."
  type        = list(string)
  default     = []
}

# ============================================================================
# TAGS
# ============================================================================

variable "tags" {
  description = "A map of tags to apply to all resources."
  type        = map(string)
  default     = {}
}
