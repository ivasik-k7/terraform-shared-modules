# ╔══════════════════════════════════════════════════════════════════════════════════════╗
# ║                     CORPORATE NETWORK (172.16.0.0/12)                              ║
# ║                     via Transit Gateway (PROD) / SSM outbound only (DEV)           ║
# ╚══════════════════════════╦═════════════════════════════════════════════════════════╝
#                            ║ IN:  tcp/443
#                            ║ IN:  tcp/1024-65535 (ephemeral)
#                            ║ OUT: tcp/443
#                            ║ OUT: tcp/1024-65535 (ephemeral)
#                            ▼
# ╔══════════════════════════════════════════════════════════════════════════════════════╗
# ║  PRIVATE SUBNET  (10.0.0.0/19)                                                     ║
# ║  EKS Worker Nodes · EC2 Workloads · Bastion EC2 (dev, SSM only)                    ║
# ║                                                                                     ║
# ║  INBOUND ALLOW:                        OUTBOUND ALLOW:                             ║
# ║  ┌─────────────────────────────────┐   ┌─────────────────────────────────┐         ║
# ║  │ tcp/443        ← corporate      │   │ tcp/443        → vpc cidr       │         ║
# ║  │ tcp/443        ← intra subnet   │   │ tcp/443        → corporate      │         ║
# ║  │ tcp/443        ← private self   │   │ tcp/5432       → database subnet│         ║
# ║  │ tcp/10250      ← intra subnet   │   │ tcp/53         → vpc cidr       │         ║
# ║  │ tcp/53         ← vpc cidr       │   │ udp/53         → vpc cidr       │         ║
# ║  │ udp/53         ← vpc cidr       │   │ tcp/1024-65535 → vpc cidr       │         ║
# ║  │ tcp/1024-65535 ← vpc cidr       │   │ tcp/1024-65535 → corporate      │         ║
# ║  │ tcp/1024-65535 ← corporate      │   └─────────────────────────────────┘         ║
# ║  └─────────────────────────────────┘                                               ║
# ║                                                                                     ║
# ║  EXPLICIT DENY:                                                                     ║
# ║  ✗ 10.0.0.0/8 (інші VPC, чужі мережі)                                             ║
# ║  ✗ 192.168.0.0/16                                                                  ║
# ║  ✗ 0.0.0.0/0 (інтернет — newer)                                                  ║
# ╚══════════╦═══════════════════════════════════════╦════════════════════════════════╝
#            ║                                       ║
#            ║ IN:  tcp/10250 (kubelet)              ║ OUT: tcp/5432
#            ║ OUT: tcp/443                          ║ IN:  tcp/1024-65535 (ephemeral)
#            ║ OUT: tcp/10250                        ║
#            ▼                                       ▼
# ╔═══════════════════════════════════╗   ╔══════════════════════════════════════════╗
# ║  INTRA SUBNET  (10.0.32.0/19)    ║   ║  DATABASE SUBNET  (10.0.64.0/24)        ║
# ║  EKS Control Plane ENIs           ║   ║  RDS / Aurora                           ║
# ║  VPC Interface Endpoints          ║   ║                                          ║
# ║  SSM · ECR · Secrets Manager      ║   ║  INBOUND ALLOW:                         ║
# ║                                   ║   ║  ┌──────────────────────────────────┐   ║
# ║  INBOUND ALLOW:                   ║   ║  │ tcp/5432  ← private subnet only  │   ║
# ║  ┌───────────────────────────┐    ║   ║  │ tcp/1024-65535 ← private subnet  │   ║
# ║  │ tcp/443   ← vpc cidr     │    ║   ║  └──────────────────────────────────┘   ║
# ║  │ tcp/10250 ← private      │    ║   ║                                          ║
# ║  │ tcp/10259 ← intra self   │    ║   ║  OUTBOUND ALLOW:                        ║
# ║  │ tcp/10257 ← intra self   │    ║   ║  ┌──────────────────────────────────┐   ║
# ║  │ tcp/53    ← vpc cidr     │    ║   ║  │ tcp/1024-65535 → private subnet  │   ║
# ║  │ udp/53    ← vpc cidr     │    ║   ║  └──────────────────────────────────┘   ║
# ║  │ tcp/1024-65535 ← vpc     │    ║   ║                                          ║
# ║  └───────────────────────────┘    ║   ║  EXPLICIT DENY:                         ║
# ║                                   ║   ║  ✗ intra subnet                         ║
# ║  OUTBOUND ALLOW:                  ║   ║  ✗ corporate (no direct DB access)      ║
# ║  ┌───────────────────────────┐    ║   ║  ✗ 0.0.0.0/0 (DB ніколи не ініціює     ║
# ║  │ tcp/443        → vpc cidr│    ║   ║           outbound з'єднань)            ║
# ║  │ tcp/10250      → private  │    ║   ╚══════════════════════════════════════════╝
# ║  │ tcp/53         → vpc cidr│    ║
# ║  │ udp/53         → vpc cidr│    ║
# ║  │ tcp/1024-65535 → vpc cidr│    ║
# ║  └───────────────────────────┘    ║
# ║                                   ║
# ║  EXPLICIT DENY:                   ║
# ║  ✗ corporate (172.16.0.0/12)      ║
# ║  ✗ 0.0.0.0/0                      ║
# ╚═══════════════════════════════════╝

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# ЛЕГЕНДА ПОРТІВ
# ──────────────────────────────────────────────────────────────────
# tcp/443        HTTPS — SSM, ECR, Secrets Manager, внутрішні API
# tcp/5432       PostgreSQL (замінити на 3306/1433 якщо інший engine)
# tcp/10250      Kubelet API — control plane → worker nodes
# tcp/10257      kube-controller-manager — тільки intra internal
# tcp/10259      kube-scheduler — тільки intra internal
# tcp/53         CoreDNS TCP
# udp/53         CoreDNS UDP
# tcp/1024-65535 Ephemeral ports — обов'язковий для stateless NACLs

# ПРИНЦИП EPHEMERAL
# ──────────────────────────────────────────────────────────────────
#   Запит іде   → на конкретний порт (443, 5432, тощо)
#   Відповідь іде ← на випадковий ephemeral port (1024-65535)
#   NACL stateless → треба дозволити ОБИДВА напрямки явно
#   SG stateful   → ephemeral не потрібен, SG пам'ятає з'єднання


# ============================================================================
# NACL Rules — Bank-Grade Strict Configuration
#
# Assumptions:
#   var.vpc_cidr              = "10.0.0.0/16"   — full VPC range
#   var.private_subnet_cidr   = "10.0.0.0/19"   — app/EKS nodes
#   var.intra_subnet_cidr     = "10.0.32.0/19"  — EKS control plane ENIs,
#                                                  VPC endpoints, internal LBs
#   var.database_subnet_cidr  = "10.0.64.0/24"  — RDS / Aurora
#   var.corporate_cidr        = "172.16.0.0/12" — on-prem via TGW / DirectConnect
#
# Rule numbering:
#   100–499   explicit ALLOW rules (ascending specificity)
#   900        explicit DENY of RFC1918 space not belonging to this VPC
#   32766      implicit AWS DENY ALL (always present, cannot be removed)
#
# Ports:
#   443        HTTPS — SSM, VPC endpoints, ECR, S3, internal APIs
#   10250      Kubelet API (EKS node <-> control plane)
#   10259      kube-scheduler (intra only)
#   10257      kube-controller-manager (intra only)
#   53 TCP/UDP CoreDNS
#   5432       PostgreSQL (adjust for your engine)
#   1024-65535 Ephemeral ports (REQUIRED for stateless NACL responses)
# ============================================================================

locals {
  # ── PRIVATE SUBNET NACL ───────────────────────────────────────────────────
  # Hosts: EKS worker nodes, EC2 application workloads, bastion (dev/SSM)
  # Entry: TGW (prod) | SSM outbound-only (dev — no inbound rule needed)
  # ─────────────────────────────────────────────────────────────────────────

  private_nacl_inbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.corporate_cidr
      description = "HTTPS from corporate network via TGW"
    },
    {
      rule_number = 110
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.intra_subnet_cidr
      description = "HTTPS from intra subnet (VPC endpoints, internal ALB health checks)"
    },
    {
      rule_number = 120
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.private_subnet_cidr
      description = "HTTPS intra-private (pod-to-pod, node-to-node)"
    },
    {
      rule_number = 130
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 10250
      to_port     = 10250
      cidr_block  = var.intra_subnet_cidr
      description = "Kubelet API — EKS control plane ENIs to worker nodes"
    },
    {
      rule_number = 140
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS TCP from VPC"
    },
    {
      rule_number = 150
      rule_action = "allow"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS UDP from VPC"
    },
    {
      rule_number = 160
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.vpc_cidr
      description = "Ephemeral ports — return traffic for outbound connections within VPC"
    },
    {
      rule_number = 170
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.corporate_cidr
      description = "Ephemeral ports — return traffic for outbound connections to corporate"
    },

    # ── Explicit deny of RFC1918 ranges not belonging to this VPC ────────
    # Forces auditors to see intentional decisions, not just implicit denies
    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "10.0.0.0/8"
      description = "DENY all other 10.0.0.0/8 space not matching VPC CIDR"
    },
    {
      rule_number = 910
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "192.168.0.0/16"
      description = "DENY 192.168.0.0/16 — no expected source"
    },
    {
      rule_number = 920
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — explicit catch-all (belt and suspenders over implicit deny)"
    },
  ]

  private_nacl_outbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.vpc_cidr
      description = "HTTPS to VPC — SSM endpoints, ECR, S3 gateway endpoint, internal APIs"
    },
    {
      rule_number = 110
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.corporate_cidr
      description = "HTTPS to corporate network via TGW"
    },
    {
      rule_number = 120
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = var.db_port
      to_port     = var.db_port
      cidr_block  = var.database_subnet_cidr
      description = "Database port to database subnet"
    },
    {
      rule_number = 130
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS TCP to VPC"
    },
    {
      rule_number = 140
      rule_action = "allow"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS UDP to VPC"
    },
    {
      rule_number = 150
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.vpc_cidr
      description = "Ephemeral ports — return traffic for inbound connections from VPC"
    },
    {
      rule_number = 160
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.corporate_cidr
      description = "Ephemeral ports — return traffic for inbound connections from corporate"
    },

    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — explicit catch-all"
    },
  ]

  # ── INTRA SUBNET NACL ─────────────────────────────────────────────────────
  # Hosts: EKS control plane ENIs, VPC Interface Endpoints (SSM, ECR, etc),
  #        internal ALBs, PrivateLink endpoints
  # No workloads, no direct corporate traffic — internal plumbing only
  # ─────────────────────────────────────────────────────────────────────────

  intra_nacl_inbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.vpc_cidr
      description = "HTTPS from VPC — SSM, ECR, S3, Secrets Manager endpoint requests"
    },
    {
      rule_number = 110
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 10250
      to_port     = 10250
      cidr_block  = var.private_subnet_cidr
      description = "Kubelet API — inbound from worker nodes to control plane ENIs"
    },
    {
      rule_number = 120
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 10259
      to_port     = 10259
      cidr_block  = var.intra_subnet_cidr
      description = "kube-scheduler — control plane internal"
    },
    {
      rule_number = 130
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 10257
      to_port     = 10257
      cidr_block  = var.intra_subnet_cidr
      description = "kube-controller-manager — control plane internal"
    },
    {
      rule_number = 140
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS TCP"
    },
    {
      rule_number = 150
      rule_action = "allow"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS UDP"
    },
    {
      rule_number = 160
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.vpc_cidr
      description = "Ephemeral ports — return traffic for outbound VPC endpoint responses"
    },

    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = var.corporate_cidr
      description = "DENY corporate CIDR — corporate never talks directly to intra subnet"
    },
    {
      rule_number = 910
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — explicit catch-all"
    },
  ]

  intra_nacl_outbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      cidr_block  = var.vpc_cidr
      description = "HTTPS to VPC — VPC endpoint responses back to callers"
    },
    {
      rule_number = 110
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 10250
      to_port     = 10250
      cidr_block  = var.private_subnet_cidr
      description = "Kubelet API — control plane ENIs to worker nodes"
    },
    {
      rule_number = 120
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS TCP"
    },
    {
      rule_number = 130
      rule_action = "allow"
      protocol    = "udp"
      from_port   = 53
      to_port     = 53
      cidr_block  = var.vpc_cidr
      description = "CoreDNS UDP"
    },
    {
      rule_number = 140
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.vpc_cidr
      description = "Ephemeral ports — return traffic for inbound requests"
    },

    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — explicit catch-all"
    },
  ]

  # ── DATABASE SUBNET NACL ──────────────────────────────────────────────────
  # Hosts: RDS / Aurora instances only
  # Accepts connections ONLY from private subnet (app tier)
  # No corporate access, no intra access, no DNS, no SSM
  # ─────────────────────────────────────────────────────────────────────────

  database_nacl_inbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = var.db_port
      to_port     = var.db_port
      cidr_block  = var.private_subnet_cidr
      description = "DB port from private (app) subnet only"
    },
    {
      rule_number = 110
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.private_subnet_cidr
      description = "Ephemeral ports — return traffic from RDS to private subnet"
    },

    # Every other source is explicitly denied — including intra, corporate, and all RFC1918
    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = var.intra_subnet_cidr
      description = "DENY intra subnet — DB unreachable from VPC endpoints / control plane"
    },
    {
      rule_number = 910
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = var.corporate_cidr
      description = "DENY corporate — no direct DB access from on-prem"
    },
    {
      rule_number = 920
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — explicit catch-all"
    },
  ]

  database_nacl_outbound = [
    {
      rule_number = 100
      rule_action = "allow"
      protocol    = "tcp"
      from_port   = 1024
      to_port     = 65535
      cidr_block  = var.private_subnet_cidr
      description = "Ephemeral ports — DB responses to private subnet"
    },

    {
      rule_number = 900
      rule_action = "deny"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      cidr_block  = "0.0.0.0/0"
      description = "DENY all — DB never initiates outbound connections"
    },
  ]
}

# ── Variables assumed to be provided by the VPC module ────────────────────────

variable "vpc_cidr" { type = string }
variable "private_subnet_cidr" { type = string }
variable "intra_subnet_cidr" { type = string }
variable "database_subnet_cidr" { type = string }
variable "corporate_cidr" { type = string }
variable "db_port" {
  type    = number
  default = 5432 # PostgreSQL — change to 3306 (MySQL), 1433 (MSSQL), etc
}

# ── NACL Resources ─────────────────────────────────────────────────────────────

resource "aws_network_acl" "private" {
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-private-nacl" })
}

resource "aws_network_acl_rule" "private_inbound" {
  for_each = { for r in local.private_nacl_inbound : r.rule_number => r }

  network_acl_id = aws_network_acl.private.id
  egress         = false
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}

resource "aws_network_acl_rule" "private_outbound" {
  for_each = { for r in local.private_nacl_outbound : r.rule_number => r }

  network_acl_id = aws_network_acl.private.id
  egress         = true
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}

resource "aws_network_acl" "intra" {
  vpc_id     = var.vpc_id
  subnet_ids = var.intra_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-intra-nacl" })
}

resource "aws_network_acl_rule" "intra_inbound" {
  for_each = { for r in local.intra_nacl_inbound : r.rule_number => r }

  network_acl_id = aws_network_acl.intra.id
  egress         = false
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}

resource "aws_network_acl_rule" "intra_outbound" {
  for_each = { for r in local.intra_nacl_outbound : r.rule_number => r }

  network_acl_id = aws_network_acl.intra.id
  egress         = true
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}

resource "aws_network_acl" "database" {
  vpc_id     = var.vpc_id
  subnet_ids = var.database_subnet_ids
  tags       = merge(var.tags, { Name = "${var.name_prefix}-database-nacl" })
}

resource "aws_network_acl_rule" "database_inbound" {
  for_each = { for r in local.database_nacl_inbound : r.rule_number => r }

  network_acl_id = aws_network_acl.database.id
  egress         = false
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}

resource "aws_network_acl_rule" "database_outbound" {
  for_each = { for r in local.database_nacl_outbound : r.rule_number => r }

  network_acl_id = aws_network_acl.database.id
  egress         = true
  rule_number    = each.value.rule_number
  rule_action    = each.value.rule_action
  protocol       = each.value.protocol
  from_port      = each.value.protocol == "-1" ? null : each.value.from_port
  to_port        = each.value.protocol == "-1" ? null : each.value.to_port
  cidr_block     = each.value.cidr_block
}
