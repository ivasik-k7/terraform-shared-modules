variable "vpc_id" {
  description = "ID of the VPC in which all Security Groups will be created."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC. Used by presets that need to scope rules to the VPC."
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix applied to all Security Group names: <name_prefix>-<key>."
  type        = string
  default     = ""

  validation {
    condition     = !endswith(var.name_prefix, "-")
    error_message = "name_prefix must not end with a hyphen."
  }
}

variable "security_groups" {
  description = <<-EOT
    Map of Security Groups to create. The map key becomes the name suffix and the
    reference key for cross-SG rules.

    Rule source fields are mutually exclusive — set exactly one per rule:
      cidr_ipv4                 — IPv4 CIDR block
      cidr_ipv6                 — IPv6 CIDR block
      self                      — the SG itself (node-to-node, pod-to-pod)
      source_security_group_key — another SG defined in THIS module call (resolved automatically)
      source_security_group_id  — an external SG ID (from outside this module)
      prefix_list_id            — AWS managed prefix list (e.g. S3, CloudFront)

    Preset values add baseline rules for common workloads. Custom ingress_rules and
    egress_rules are MERGED ON TOP of preset rules — they never replace them.
    Available presets:
      "eks_nodes"         — EKS worker node baseline (node-to-node, kubelet, CoreDNS, ephemeral egress)
      "eks_control_plane" — EKS control plane ENI baseline (443 from nodes, 10250 to nodes)
      "rds"               — RDS/Aurora (DB port inbound from app SG, no outbound initiated)
      "alb_internal"      — Internal ALB (443/80 from VPC CIDR, health check ephemeral)
      "vpc_endpoints"     — VPC Interface Endpoints (443 from VPC CIDR only)
      "bastion_ssm"       — Bastion via SSM (outbound 443 only, no inbound SSH)
      "lambda"            — Lambda in VPC (outbound 443 + DB port to VPC, no inbound)

    See README for full preset rule details and usage examples.
  EOT

  type = map(object({
    description = string

    preset = optional(string, null)

    # Preset-specific parameters (only used when preset is set)
    preset_config = optional(object({
      # For "rds" preset — the DB engine port
      db_port = optional(number, 5432)
      # For "eks_nodes" and "eks_control_plane" — resolved automatically
      # when both are defined in the same module call via their keys
      eks_nodes_sg_key         = optional(string, null)
      eks_control_plane_sg_key = optional(string, null)
    }), null)

    ingress_rules = optional(list(object({
      description = string
      from_port   = number
      to_port     = number
      protocol    = string

      cidr_ipv4                 = optional(string, null)
      cidr_ipv6                 = optional(string, null)
      self                      = optional(bool, false)
      source_security_group_key = optional(string, null)
      source_security_group_id  = optional(string, null)
      prefix_list_id            = optional(string, null)
    })), [])

    egress_rules = optional(list(object({
      description = string
      from_port   = number
      to_port     = number
      protocol    = string

      cidr_ipv4                 = optional(string, null)
      cidr_ipv6                 = optional(string, null)
      self                      = optional(bool, false)
      destination_security_group_key = optional(string, null)
      destination_security_group_id  = optional(string, null)
      prefix_list_id            = optional(string, null)
    })), [])

    tags = optional(map(string), {})
  }))

  default = {}

  validation {
    condition = alltrue([
      for sg_key, sg in var.security_groups :
      alltrue([
        for rule in sg.ingress_rules :
        length(compact([
          rule.cidr_ipv4,
          rule.cidr_ipv6,
          rule.self ? "set" : null,
          rule.source_security_group_key,
          rule.source_security_group_id,
          rule.prefix_list_id,
        ])) == 1
      ])
    ])
    error_message = "Each ingress rule must specify exactly one source: cidr_ipv4, cidr_ipv6, self, source_security_group_key, source_security_group_id, or prefix_list_id."
  }

  validation {
    condition = alltrue([
      for sg_key, sg in var.security_groups :
      alltrue([
        for rule in sg.egress_rules :
        length(compact([
          rule.cidr_ipv4,
          rule.cidr_ipv6,
          rule.self ? "set" : null,
          rule.destination_security_group_key,
          rule.destination_security_group_id,
          rule.prefix_list_id,
        ])) == 1
      ])
    ])
    error_message = "Each egress rule must specify exactly one destination: cidr_ipv4, cidr_ipv6, self, destination_security_group_key, destination_security_group_id, or prefix_list_id."
  }

  validation {
    condition = alltrue([
      for sg_key, sg in var.security_groups :
      sg.preset == null ? true : contains(
        ["eks_nodes", "eks_control_plane", "rds", "alb_internal", "vpc_endpoints", "bastion_ssm", "lambda"],
        sg.preset
      )
    ])
    error_message = "preset must be one of: eks_nodes, eks_control_plane, rds, alb_internal, vpc_endpoints, bastion_ssm, lambda."
  }
}

variable "default_tags" {
  description = "Tags merged into all Security Groups. Per-SG tags take precedence on key conflicts."
  type        = map(string)
  default     = {}
}

variable "revoke_rules_on_delete" {
  description = "Set to true to revoke all SG rules before deleting the SG. Useful when SGs have circular references."
  type        = bool
  default     = true
}
