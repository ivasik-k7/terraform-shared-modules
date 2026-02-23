locals {
  name = var.name_prefix != "" ? var.name_prefix : null

  # ── Preset rule templates ──────────────────────────────────────────────────
  # Each preset returns { ingress = [...], egress = [...] }
  # Rules that reference other SGs use source_security_group_key or
  # preset_config fields — resolved after SG creation.

  preset_rules = {
    for sg_key, sg in var.security_groups : sg_key => (
      sg.preset == null ? { ingress = [], egress = [] } :
      sg.preset == "eks_nodes" ? {
        ingress = [
          {
            description               = "[preset] Node-to-node all traffic (pod-to-pod, overlay network)"
            from_port                 = 0
            to_port                   = 0
            protocol                  = "-1"
            self                      = true
            cidr_ipv4                 = null
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
          {
            description               = "[preset] Kubelet API from EKS control plane"
            from_port                 = 10250
            to_port                   = 10250
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = null
            cidr_ipv6                 = null
            source_security_group_key = try(sg.preset_config.eks_control_plane_sg_key, null)
            source_security_group_id  = null
            prefix_list_id            = null
          },
          {
            description               = "[preset] CoreDNS TCP from VPC"
            from_port                 = 53
            to_port                   = 53
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = var.vpc_cidr
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
          {
            description               = "[preset] CoreDNS UDP from VPC"
            from_port                 = 53
            to_port                   = 53
            protocol                  = "udp"
            self                      = false
            cidr_ipv4                 = var.vpc_cidr
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
        ]
        egress = [
          {
            description                    = "[preset] All egress to VPC (VPC endpoints, internal services)"
            from_port                      = 443
            to_port                        = 443
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
          {
            description                    = "[preset] Kubelet API to worker nodes"
            from_port                      = 10250
            to_port                        = 10250
            protocol                       = "tcp"
            self                           = true
            cidr_ipv4                      = null
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
          {
            description                    = "[preset] CoreDNS TCP to VPC"
            from_port                      = 53
            to_port                        = 53
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
          {
            description                    = "[preset] CoreDNS UDP to VPC"
            from_port                      = 53
            to_port                        = 53
            protocol                       = "udp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
        ]
      } :

      sg.preset == "eks_control_plane" ? {
        ingress = [
          {
            description               = "[preset] Kubernetes API from worker nodes"
            from_port                 = 443
            to_port                   = 443
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = null
            cidr_ipv6                 = null
            source_security_group_key = try(sg.preset_config.eks_nodes_sg_key, null)
            source_security_group_id  = null
            prefix_list_id            = null
          },
          {
            description               = "[preset] Kubelet API inbound (webhook traffic)"
            from_port                 = 10250
            to_port                   = 10250
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = null
            cidr_ipv6                 = null
            source_security_group_key = try(sg.preset_config.eks_nodes_sg_key, null)
            source_security_group_id  = null
            prefix_list_id            = null
          },
        ]
        egress = [
          {
            description                    = "[preset] Kubelet API to worker nodes"
            from_port                      = 10250
            to_port                        = 10250
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = null
            cidr_ipv6                      = null
            destination_security_group_key = try(sg.preset_config.eks_nodes_sg_key, null)
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
          {
            description                    = "[preset] HTTPS to VPC (VPC endpoints)"
            from_port                      = 443
            to_port                        = 443
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
        ]
      } :

      sg.preset == "rds" ? {
        ingress = [
          {
            description               = "[preset] DB port from application tier"
            from_port                 = try(sg.preset_config.db_port, 5432)
            to_port                   = try(sg.preset_config.db_port, 5432)
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = null
            cidr_ipv6                 = null
            source_security_group_key = try(sg.preset_config.eks_nodes_sg_key, null)
            source_security_group_id  = null
            prefix_list_id            = null
          },
        ]
        egress = []
      } :

      sg.preset == "alb_internal" ? {
        ingress = [
          {
            description               = "[preset] HTTPS from VPC CIDR"
            from_port                 = 443
            to_port                   = 443
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = var.vpc_cidr
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
          {
            description               = "[preset] HTTP from VPC CIDR (redirect to HTTPS)"
            from_port                 = 80
            to_port                   = 80
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = var.vpc_cidr
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
        ]
        egress = [
          {
            description                    = "[preset] HTTPS to targets (EKS nodes)"
            from_port                      = 443
            to_port                        = 443
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
          {
            description                    = "[preset] Health check ephemeral ports to targets"
            from_port                      = 1024
            to_port                        = 65535
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
        ]
      } :

      sg.preset == "vpc_endpoints" ? {
        ingress = [
          {
            description               = "[preset] HTTPS from VPC (endpoint requests)"
            from_port                 = 443
            to_port                   = 443
            protocol                  = "tcp"
            self                      = false
            cidr_ipv4                 = var.vpc_cidr
            cidr_ipv6                 = null
            source_security_group_key = null
            source_security_group_id  = null
            prefix_list_id            = null
          },
        ]
        egress = []
      } :

      sg.preset == "bastion_ssm" ? {
        ingress = []
        egress = [
          {
            description                    = "[preset] HTTPS to VPC endpoints (SSM, SSMMessages, EC2Messages)"
            from_port                      = 443
            to_port                        = 443
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
        ]
      } :

      sg.preset == "lambda" ? {
        ingress = []
        egress = [
          {
            description                    = "[preset] HTTPS to VPC (VPC endpoints, internal APIs)"
            from_port                      = 443
            to_port                        = 443
            protocol                       = "tcp"
            self                           = false
            cidr_ipv4                      = var.vpc_cidr
            cidr_ipv6                      = null
            destination_security_group_key = null
            destination_security_group_id  = null
            prefix_list_id                 = null
          },
        ]
      } :

      { ingress = [], egress = [] }
    )
  }

  # ── Merge preset + custom rules per SG ────────────────────────────────────

  merged_ingress = {
    for sg_key, sg in var.security_groups : sg_key =>
    concat(local.preset_rules[sg_key].ingress, sg.ingress_rules)
  }

  merged_egress = {
    for sg_key, sg in var.security_groups : sg_key =>
    concat(local.preset_rules[sg_key].egress, sg.egress_rules)
  }

  # ── Flat maps for resource for_each ───────────────────────────────────────
  # Key format: "<sg_key>__<zero_padded_index>"
  # Zero-padding ensures stable ordering and avoids key collisions.

  flat_ingress = merge([
    for sg_key, rules in local.merged_ingress : {
      for idx, rule in rules :
      "${sg_key}__${format("%04d", idx)}" => merge(rule, { sg_key = sg_key })
    }
  ]...)

  flat_egress = merge([
    for sg_key, rules in local.merged_egress : {
      for idx, rule in rules :
      "${sg_key}__${format("%04d", idx)}" => merge(rule, { sg_key = sg_key })
    }
  ]...)

  # ── Rule subsets by source type (ingress) ─────────────────────────────────

  ingress_cidr_ipv4 = {
    for k, r in local.flat_ingress : k => r
    if r.cidr_ipv4 != null
  }

  ingress_cidr_ipv6 = {
    for k, r in local.flat_ingress : k => r
    if try(r.cidr_ipv6, null) != null
  }

  ingress_self = {
    for k, r in local.flat_ingress : k => r
    if try(r.self, false) == true
  }

  ingress_sg_key = {
    for k, r in local.flat_ingress : k => r
    if try(r.source_security_group_key, null) != null
  }

  ingress_sg_id = {
    for k, r in local.flat_ingress : k => r
    if try(r.source_security_group_id, null) != null
  }

  ingress_prefix_list = {
    for k, r in local.flat_ingress : k => r
    if try(r.prefix_list_id, null) != null
  }

  # ── Rule subsets by destination type (egress) ─────────────────────────────

  egress_cidr_ipv4 = {
    for k, r in local.flat_egress : k => r
    if r.cidr_ipv4 != null
  }

  egress_cidr_ipv6 = {
    for k, r in local.flat_egress : k => r
    if try(r.cidr_ipv6, null) != null
  }

  egress_self = {
    for k, r in local.flat_egress : k => r
    if try(r.self, false) == true
  }

  egress_sg_key = {
    for k, r in local.flat_egress : k => r
    if try(r.destination_security_group_key, null) != null
  }

  egress_sg_id = {
    for k, r in local.flat_egress : k => r
    if try(r.destination_security_group_id, null) != null
  }

  egress_prefix_list = {
    for k, r in local.flat_egress : k => r
    if try(r.prefix_list_id, null) != null
  }
}
