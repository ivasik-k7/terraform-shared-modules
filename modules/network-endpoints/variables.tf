# ─────────────────────────────────────────────────────────────────────────────
# Core targeting
# ─────────────────────────────────────────────────────────────────────────────

variable "vpc_id" {
  description = "The ID of the VPC in which endpoints will be provisioned."
  type        = string
}

variable "region" {
  description = "AWS region. Used to construct service names when a short alias is given (e.g. \"s3\" → \"com.amazonaws.us-east-1.s3\")."
  type        = string
  default     = ""

  validation {
    condition     = var.region == "" || can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.region))
    error_message = "region must be a valid AWS region string (e.g. us-east-1) or empty to inherit from the provider."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Endpoint definitions
# ─────────────────────────────────────────────────────────────────────────────

variable "endpoints" {
  description = <<-EOT
    Map of endpoint configurations keyed by a logical name of your choice.

    Each object supports:

    Required:
      service               - Short alias (e.g. "s3", "kms") OR a fully-qualified
                              service name (e.g. "com.amazonaws.us-east-1.s3").

    Optional:
      enabled               - Set to false to skip this endpoint without removing it
                              from the map (default: true).
      type                  - "Interface" | "Gateway" | "GatewayLoadBalancer".
                              Inferred automatically for known aliases; required for
                              fully-qualified names whose type cannot be inferred.
      private_dns_enabled   - Enable private DNS for Interface endpoints (default: true).
      auto_accept           - Auto-accept the endpoint connection (default: false).
      ip_address_type       - "ipv4" | "dualstack" | "ipv6" (Interface only, default: null).
      policy                - JSON IAM policy document to attach to the endpoint.
                              Defaults to full access if omitted.
      subnet_ids            - List of subnet IDs for Interface / GatewayLoadBalancer endpoints.
                              Falls back to var.default_subnet_ids when omitted.
      security_group_ids    - Additional security group IDs to attach (Interface only).
                              The module-managed default SG is always prepended when
                              var.create_default_security_group = true.
      route_table_ids       - Route table IDs for Gateway endpoints.
                              Falls back to var.default_route_table_ids when omitted.
      notification_arns     - List of SNS topic ARNs to notify on endpoint state changes.
      tags                  - Per-endpoint tags merged on top of var.tags.
      timeouts              - Object with optional "create", "update", "delete" durations.

    Example:
      endpoints = {
        s3 = {
          service = "s3"
        }
        kms = {
          service             = "kms"
          private_dns_enabled = true
          subnet_ids          = ["subnet-aaa", "subnet-bbb"]
          policy              = data.aws_iam_policy_document.kms_endpoint.json
        }
        custom_service = {
          service = "com.amazonaws.vpce.us-east-1.vpce-svc-0123456789abcdef0"
          type    = "Interface"
        }
      }
  EOT

  type = map(object({
    service             = string
    enabled             = optional(bool, true)
    type                = optional(string)
    private_dns_enabled = optional(bool, true)
    auto_accept         = optional(bool, false)
    ip_address_type     = optional(string)
    policy              = optional(string)
    subnet_ids          = optional(list(string))
    security_group_ids  = optional(list(string), [])
    route_table_ids     = optional(list(string))
    notification_arns   = optional(list(string), [])
    tags                = optional(map(string), {})
    timeouts = optional(object({
      create = optional(string, "10m")
      update = optional(string, "10m")
      delete = optional(string, "10m")
    }), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.endpoints : contains(
        ["Interface", "Gateway", "GatewayLoadBalancer"],
        coalesce(v.type, "Interface")
      )
    ])
    error_message = "Each endpoint 'type' must be one of: Interface, Gateway, GatewayLoadBalancer."
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Defaults applied to all endpoints unless overridden per-endpoint
# ─────────────────────────────────────────────────────────────────────────────

variable "default_subnet_ids" {
  description = "Fallback subnet IDs used by Interface and GatewayLoadBalancer endpoints when subnet_ids is not specified per endpoint."
  type        = list(string)
  default     = []
}

variable "default_route_table_ids" {
  description = "Fallback route table IDs used by Gateway endpoints when route_table_ids is not specified per endpoint."
  type        = list(string)
  default     = []
}

# ─────────────────────────────────────────────────────────────────────────────
# Default security group
# ─────────────────────────────────────────────────────────────────────────────

variable "create_default_security_group" {
  description = "When true, the module creates a security group and attaches it to every Interface endpoint automatically. Set to false if you prefer to manage security groups externally and pass them via security_group_ids."
  type        = bool
  default     = true
}

variable "default_security_group_name" {
  description = "Name to assign to the module-managed default security group."
  type        = string
  default     = ""
}

variable "default_security_group_description" {
  description = "Description for the module-managed default security group."
  type        = string
  default     = "Managed by terraform-aws-vpc-endpoints — default SG for all Interface VPC endpoints"
}

variable "default_security_group_ingress_rules" {
  description = <<-EOT
    Ingress rules applied to the default security group.

    Each rule object:
      from_port       - Starting port (required).
      to_port         - Ending port (required).
      protocol        - Protocol string or number (default: "tcp").
      cidr_blocks     - List of IPv4 CIDR blocks.
      ipv6_cidr_blocks- List of IPv6 CIDR blocks.
      security_groups - List of source security group IDs.
      self            - Allow traffic from within the SG itself.
      description     - Human-readable rule description.

    Default: allow HTTPS (443) from the entire VPC CIDR.
  EOT

  type = list(object({
    from_port        = number
    to_port          = number
    protocol         = optional(string, "tcp")
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
    description      = optional(string, "")
  }))

  default = []
}

variable "default_security_group_egress_rules" {
  description = "Egress rules applied to the default security group. Defaults to allow-all egress."
  type = list(object({
    from_port        = number
    to_port          = number
    protocol         = optional(string, "-1")
    cidr_blocks      = optional(list(string), ["0.0.0.0/0"])
    ipv6_cidr_blocks = optional(list(string), ["::/0"])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
    description      = optional(string, "Allow all egress")
  }))

  default = [
    {
      from_port        = 0
      to_port          = 0
      protocol         = "-1"
      cidr_blocks      = ["0.0.0.0/0"]
      ipv6_cidr_blocks = ["::/0"]
      description      = "Allow all egress"
    }
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Tagging
# ─────────────────────────────────────────────────────────────────────────────

variable "tags" {
  description = "Tags to apply to all resources. Per-endpoint tags are merged on top of these."
  type        = map(string)
  default     = {}
}

variable "security_group_tags" {
  description = "Additional tags applied only to the default security group."
  type        = map(string)
  default     = {}
}
