# =============================================================================
# Identity & tagging
# =============================================================================
# Migration factory rule: every resource lands with a Name, Environment,
# Project, Team, CostCenter and Owner tag. The module builds Name/Environment
# itself; the rest comes from var.tags so FinOps can chargeback cleanly.

variable "name" {
  description = "Short prefix used for every resource Name tag and id. Keep it under 60 chars; CloudFormation/IAM friendly."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 60
    error_message = "name must be 1-60 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*$", var.name))
    error_message = "name must be lowercase letters, digits, and hyphens (start with a letter or digit)."
  }
}

variable "environment" {
  description = "Environment slug (dev/staging/prod/...). Emitted as the Environment tag."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags merged onto every resource. Migration factory expects at least Project, Team, CostCenter, Owner."
  type        = map(string)
  default     = {}
}

variable "enforce_finops_tags" {
  description = "When true, the module fails plan if any of [Project, Team, CostCenter, Owner] is missing from var.tags. Recommended for shared landing zones."
  type        = bool
  default     = false
}

# =============================================================================
# VPC: create vs adopt
# =============================================================================
# Two mutually-exclusive modes. The check{} block in vpc.tf rejects both-or-
# neither at plan time so this stays self-documenting.

variable "vpc_id" {
  description = "Existing VPC id to adopt. When set, the module skips VPC + subnet creation and only attaches the things you ask for around it."
  type        = string
  default     = null
}

variable "create_vpc" {
  description = "Create a new VPC. Mutually exclusive with vpc_id. Required = true when vpc_id is null."
  type        = bool
  default     = false
}

variable "vpc_cidr_block" {
  description = "Primary IPv4 CIDR for the new VPC. /16 is the AWS default; smaller is fine, but /24 leaves no room for tiered subnets."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR."
  }
}

variable "secondary_cidr_blocks" {
  description = "Additional IPv4 CIDRs to attach to the VPC. Use when you ran out of space in the primary block (common after a few migration waves)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.secondary_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "All secondary_cidr_blocks must be valid CIDRs."
  }
}

variable "enable_ipv6" {
  description = "Ask AWS for an Amazon-provided /56 IPv6 block. Note: still need v6 routes + SGs for anything to actually work."
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "VPC tenancy. Leave at default unless you have a hard compliance reason for dedicated; dedicated is expensive and rarely needed."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "instance_tenancy must be 'default' or 'dedicated'."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS resolution inside the VPC. Required for VPC endpoints' private DNS to work; do NOT set false unless you really know why."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Assign DNS hostnames to instances with public IPs. Also required for endpoint private DNS."
  type        = bool
  default     = true
}

variable "enable_network_address_usage_metrics" {
  description = "Publish NetworkAddressUsage metrics to CloudWatch. Cheap, useful when migration waves start eating IP space faster than you expected."
  type        = bool
  default     = false
}

# =============================================================================
# Availability zones + subnet auto-carving
# =============================================================================

variable "availability_zones" {
  description = "AZs to spread subnets across. Empty = the module picks the first 3 available AZs in the region. Cap at 6; AWS has at most 6 AZs in any region today."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.availability_zones) >= 0 && length(var.availability_zones) <= 6
    error_message = "availability_zones must list 0-6 AZs."
  }
}

variable "az_count" {
  description = "How many AZs to use when availability_zones is empty. 3 is the safe default for HA."
  type        = number
  default     = 3

  validation {
    condition     = var.az_count >= 1 && var.az_count <= 6
    error_message = "az_count must be 1-6."
  }
}

variable "create_subnets" {
  description = "Build subnets when creating a VPC. Set false only if subnets are managed outside this module (rare)."
  type        = bool
  default     = true
}

variable "auto_carve_subnets" {
  description = <<-EOT
    Auto-allocate subnet CIDRs from the VPC CIDR using cidrsubnet().
    When true, you do NOT supply per-tier CIDR lists; the module slices the
    VPC block according to subnet_newbits and per-tier offsets. Great for
    migration factory: drop in a /16, get a sensible 5-tier layout for free.
    When false, you must populate the per-tier *_subnets lists.
  EOT
  type        = bool
  default     = false
}

variable "subnet_newbits" {
  description = "Bits added to the VPC mask when auto-carving non-transit tiers. /16 + 4 = /20 per subnet (4096 IPs). Tune based on workload density."
  type        = number
  default     = 4

  validation {
    condition     = var.subnet_newbits >= 2 && var.subnet_newbits <= 12
    error_message = "subnet_newbits must be 2-12."
  }
}

variable "transit_subnet_newbits" {
  description = "Bits added to the VPC mask for the transit tier. AWS only needs a tiny block for TGW ENIs, so default to /28 from a /16 (12 newbits)."
  type        = number
  default     = 12
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign public IPv4 to instances launched in public subnets. Most modern designs prefer EIPs / NLB instead — leaving true for compatibility."
  type        = bool
  default     = true
}

# Per-tier explicit CIDR lists (used when auto_carve_subnets = false). Empty
# list disables that tier. The check{} block enforces "empty or one CIDR per AZ".

variable "public_subnets" {
  description = "Public subnet CIDRs (IGW-routed). Empty disables the tier."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.public_subnets : can(cidrhost(c, 0))])
    error_message = "All public_subnets must be valid CIDRs."
  }
}

variable "private_subnets" {
  description = "Private subnet CIDRs (NAT-routed). Empty disables the tier."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.private_subnets : can(cidrhost(c, 0))])
    error_message = "All private_subnets must be valid CIDRs."
  }
}

variable "database_subnets" {
  description = "Database subnet CIDRs (no default route). Used by aws_db_subnet_group on the consumer side."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.database_subnets : can(cidrhost(c, 0))])
    error_message = "All database_subnets must be valid CIDRs."
  }
}

variable "intra_subnets" {
  description = "Intra subnet CIDRs (internal-only: VPC endpoints, EKS control-plane ENIs, internal LBs). No default route."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.intra_subnets : can(cidrhost(c, 0))])
    error_message = "All intra_subnets must be valid CIDRs."
  }
}

variable "transit_subnets" {
  description = <<-EOT
    Dedicated tiny subnets (/28 typical) hosting Transit Gateway / Cloud WAN
    attachment ENIs. Strongly recommended for hybrid: keeps on-prem routing
    decisions out of workload route tables and lets you NACL the attachment
    independently.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.transit_subnets : can(cidrhost(c, 0))])
    error_message = "All transit_subnets must be valid CIDRs."
  }
}

# Existing-VPC mode: pass subnet ids in directly.

variable "public_subnet_ids" {
  description = "Existing public subnet ids when adopting a VPC."
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "Existing private subnet ids when adopting a VPC."
  type        = list(string)
  default     = []
}

variable "database_subnet_ids" {
  description = "Existing database subnet ids when adopting a VPC."
  type        = list(string)
  default     = []
}

variable "intra_subnet_ids" {
  description = "Existing intra subnet ids when adopting a VPC."
  type        = list(string)
  default     = []
}

variable "transit_subnet_ids" {
  description = "Existing transit subnet ids when adopting a VPC."
  type        = list(string)
  default     = []
}

# Per-tier extra tags

variable "public_subnet_tags" {
  description = "Extra tags merged onto public subnets. Useful for kubernetes.io/role/elb=1 etc."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags merged onto private subnets. Useful for kubernetes.io/role/internal-elb=1 etc."
  type        = map(string)
  default     = {}
}

variable "database_subnet_tags" {
  description = "Extra tags merged onto database subnets."
  type        = map(string)
  default     = {}
}

variable "intra_subnet_tags" {
  description = "Extra tags merged onto intra subnets."
  type        = map(string)
  default     = {}
}

variable "transit_subnet_tags" {
  description = "Extra tags merged onto transit subnets."
  type        = map(string)
  default     = {}
}

# =============================================================================
# NAT gateways
# =============================================================================
# Three layouts:
#   single_nat_gateway = true       -> 1 NAT (cheap, single AZ failure = full outage)
#   one_nat_gateway_per_az = true   -> 1 NAT per AZ (default; HA, no cross-AZ data)
#   neither                         -> 1 NAT per public subnet up to AZ count
#
# Cost gotcha: cross-AZ NAT data transfer is billed twice (out of source AZ,
# back into NAT's AZ). That's why we default to per-AZ.

variable "enable_nat_gateway" {
  description = "Provision NAT gateways so private subnets reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Collapse all private subnets onto one shared NAT. Cheapest, NO HA. Acceptable for dev/test, never for prod."
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "One NAT per AZ. Default; safe for prod. Ignored when single_nat_gateway = true."
  type        = bool
  default     = true
}

variable "nat_gateway_subnet_ids" {
  description = "Override which subnets host the NATs. Default = the public subnets the module created/adopted."
  type        = list(string)
  default     = []
}

variable "nat_gateway_eip_ids" {
  description = "Pre-allocated EIPs to bind to NAT gateways. Useful when on-prem firewalls already allowlist these IPs."
  type        = list(string)
  default     = []
}

variable "nat_gateway_tags" {
  description = "Extra tags merged onto NAT gateways and the EIPs the module allocates."
  type        = map(string)
  default     = {}
}

variable "nat_gateway_destination_cidr_block" {
  description = "Destination CIDR for the private RT default route via NAT. Almost always 0.0.0.0/0."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.nat_gateway_destination_cidr_block, 0))
    error_message = "nat_gateway_destination_cidr_block must be a valid CIDR."
  }
}

variable "skip_private_nat_default_route" {
  description = "Do NOT install the 0.0.0.0/0 -> NAT route on private RTs. Use when egress goes via TGW (centralised egress VPC) instead. The TGW route still wins because it is /12 vs /0, but if you want a clean RT, set this true."
  type        = bool
  default     = false
}

# =============================================================================
# Internet gateway
# =============================================================================

variable "internet_gateway_id" {
  description = "Existing IGW id to adopt. Skips IGW creation when set."
  type        = string
  default     = null
}

variable "create_internet_gateway" {
  description = "Create an IGW. Ignored when internet_gateway_id is set or when create_vpc = false."
  type        = bool
  default     = true
}

variable "internet_gateway_tags" {
  description = "Extra tags merged onto the IGW."
  type        = map(string)
  default     = {}
}

# =============================================================================
# Route tables
# =============================================================================

variable "create_public_route_table" {
  description = "Create a shared public route table (default route via IGW)."
  type        = bool
  default     = true
}

variable "create_private_route_tables" {
  description = "Create per-AZ private route tables. One per AZ keeps NAT traffic in-AZ."
  type        = bool
  default     = true
}

variable "create_database_route_table" {
  description = "Create a shared database route table. No default route (database subnets must not egress)."
  type        = bool
  default     = true
}

variable "create_intra_route_table" {
  description = "Create a shared intra route table. No default route."
  type        = bool
  default     = true
}

variable "create_transit_route_table" {
  description = "Create a shared transit route table. No default route. TGW propagation lives at the TGW route table, not here."
  type        = bool
  default     = true
}

variable "public_route_table_tags" {
  description = "Extra tags for the public route table."
  type        = map(string)
  default     = {}
}

variable "private_route_table_tags" {
  description = "Extra tags for private route tables (applied to all of them)."
  type        = map(string)
  default     = {}
}

variable "database_route_table_tags" {
  description = "Extra tags for the database route table."
  type        = map(string)
  default     = {}
}

variable "intra_route_table_tags" {
  description = "Extra tags for the intra route table."
  type        = map(string)
  default     = {}
}

variable "transit_route_table_tags" {
  description = "Extra tags for the transit route table."
  type        = map(string)
  default     = {}
}

variable "public_routes" {
  description = "Extra routes to install on public route tables. Each entry takes a route_table_id and one target field."
  type = list(object({
    route_table_id             = string
    destination_cidr_block     = optional(string)
    destination_prefix_list_id = optional(string)
    gateway_id                 = optional(string)
    nat_gateway_id             = optional(string)
    vpc_endpoint_id            = optional(string)
    transit_gateway_id         = optional(string)
    vpc_peering_connection_id  = optional(string)
    egress_only_gateway_id     = optional(string)
    carrier_gateway_id         = optional(string)
    network_interface_id       = optional(string)
    local_gateway_id           = optional(string)
  }))
  default = []
}

variable "private_routes" {
  description = "Extra routes to install on private route tables."
  type = list(object({
    route_table_id             = string
    destination_cidr_block     = optional(string)
    destination_prefix_list_id = optional(string)
    gateway_id                 = optional(string)
    nat_gateway_id             = optional(string)
    vpc_endpoint_id            = optional(string)
    transit_gateway_id         = optional(string)
    vpc_peering_connection_id  = optional(string)
    egress_only_gateway_id     = optional(string)
    carrier_gateway_id         = optional(string)
    network_interface_id       = optional(string)
    local_gateway_id           = optional(string)
  }))
  default = []
}

# =============================================================================
# VPC endpoints (interface + gateway)
# =============================================================================
# Two big DX wins here vs raw aws_vpc_endpoint:
#   1. service_name accepts a SHORT name ("ssm") and the module prefixes it
#      with "com.amazonaws.<region>." automatically. Pass the full ARN-style
#      name if you want to override (e.g., S3 outpost endpoints).
#   2. interface_endpoint_services = ["ssm","ssmmessages",...] is a one-shot
#      shorthand for the common SSM/EKS/ECS endpoint sets.

variable "vpc_endpoints" {
  description = <<-EOT
    Interface VPC endpoints, keyed by short name (used in resource Name tag).

    service_name accepts either a short name ("ssm") or a full service name
    ("com.amazonaws.eu-west-1.ssm"). Short names get the regional prefix
    auto-applied, which means the same module call works in any region.

    subnet_ids defaults to the intra subnets when empty (recommended).
    security_group_ids defaults to the module-built endpoint SG when empty
    (allows 443 from the VPC CIDR).
  EOT
  type = map(object({
    service_name        = string
    private_dns_enabled = optional(bool, true)
    security_group_ids  = optional(list(string), [])
    subnet_ids          = optional(list(string), [])
    policy              = optional(string)
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "gateway_vpc_endpoints" {
  description = <<-EOT
    Gateway VPC endpoints (S3, DynamoDB only). Keyed by short name.

    service_name accepts either short ("s3") or full
    ("com.amazonaws.eu-west-1.s3").

    route_table_ids defaults to all private + intra route tables when empty
    (typical case: skip the NAT for S3 traffic VPC-wide).
  EOT
  type = map(object({
    service_name    = string
    route_table_ids = optional(list(string), [])
    policy          = optional(string)
    tags            = optional(map(string), {})
  }))
  default = {}
}

variable "interface_endpoint_services" {
  description = <<-EOT
    Shortcut for the common interface endpoint set. Each string in this list
    becomes an endpoint with sensible defaults (intra subnets, module SG,
    private DNS on). Examples:
      ["ssm","ssmmessages","ec2messages"]                      # SSM Session Manager
      ["ecr.api","ecr.dkr","logs"]                              # ECS / EKS pulls
      ["sts","secretsmanager","kms"]                            # IAM-heavy workloads
    Anything more bespoke goes through var.vpc_endpoints.
  EOT
  type        = list(string)
  default     = []
}

variable "gateway_endpoint_services" {
  description = "Shortcut for gateway endpoints. Pass [\"s3\",\"dynamodb\"] to get both with default route table wiring."
  type        = list(string)
  default     = []
}

variable "create_endpoint_security_group" {
  description = "Build a default SG for interface endpoints (allows 443 in from the VPC CIDR). Reused by every endpoint that doesn't pass its own SG."
  type        = bool
  default     = true
}

variable "endpoint_security_group_extra_cidrs" {
  description = "Additional CIDRs allowed inbound 443 on the default endpoint SG. Common: on-prem corporate range when reaching endpoints over TGW."
  type        = list(string)
  default     = []
}

# =============================================================================
# Security groups
# =============================================================================

variable "security_groups" {
  description = <<-EOT
    Custom security groups, keyed by short name. Inline rules are convenient
    for small SGs; for very large or frequently-changing rule sets, manage
    rules outside the module via aws_vpc_security_group_{ingress,egress}_rule
    to avoid destructive replacement on edits.
  EOT
  type = map(object({
    description = string
    ingress_rules = optional(list(object({
      description      = optional(string)
      from_port        = number
      to_port          = number
      protocol         = string
      cidr_blocks      = optional(list(string), [])
      ipv6_cidr_blocks = optional(list(string), [])
      prefix_list_ids  = optional(list(string), [])
      security_groups  = optional(list(string), [])
      self             = optional(bool, false)
    })), [])
    egress_rules = optional(list(object({
      description      = optional(string)
      from_port        = number
      to_port          = number
      protocol         = string
      cidr_blocks      = optional(list(string), [])
      ipv6_cidr_blocks = optional(list(string), [])
      prefix_list_ids  = optional(list(string), [])
      security_groups  = optional(list(string), [])
      self             = optional(bool, false)
    })), [])
    tags = optional(map(string), {})
  }))
  default = {}
}

variable "manage_default_security_group" {
  description = <<-EOT
    Adopt the VPC's default SG via aws_default_security_group and replace
    its rules with var.default_security_group_ingress / _egress.

    GOTCHA: this is destructive — Terraform overwrites every existing rule
    on the default SG, including ones added out-of-band. Empty lists strip
    the SG completely (AWS best practice).
  EOT
  type        = bool
  default     = false
}

variable "default_security_group_ingress" {
  description = "Ingress rules for the managed default SG."
  type = list(object({
    description      = optional(string)
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    prefix_list_ids  = optional(list(string), [])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
  }))
  default = []
}

variable "default_security_group_egress" {
  description = "Egress rules for the managed default SG."
  type = list(object({
    description      = optional(string)
    from_port        = number
    to_port          = number
    protocol         = string
    cidr_blocks      = optional(list(string), [])
    ipv6_cidr_blocks = optional(list(string), [])
    prefix_list_ids  = optional(list(string), [])
    security_groups  = optional(list(string), [])
    self             = optional(bool, false)
  }))
  default = []
}

# =============================================================================
# Inter-tier security group rules
# =============================================================================
# A migration-factory recurring pain: workload SG -> database SG opens for
# port 3306, intra SG -> private SG opens for some app port, etc. Caller
# normally re-implements the same pattern. This shortcut lets you express it
# declaratively against the SGs the module already created.

variable "inter_tier_rules" {
  description = <<-EOT
    Tier-to-tier allow rules wired between SGs created by this module.
    Each entry produces an ingress rule on the 'to' SG, scoped to the 'from'
    SG, on the given port range.

    from / to refer to keys in var.security_groups (e.g. "app", "db").
    Used to declare intent like "app talks to db on 5432" without writing
    the full SG rule object yourself.
  EOT
  type = list(object({
    from        = string
    to          = string
    from_port   = number
    to_port     = number
    protocol    = optional(string, "tcp")
    description = optional(string)
  }))
  default = []
}

# =============================================================================
# Flow logs
# =============================================================================
# Module never owns the destination — caller picks CW Logs / S3 / Firehose
# and supplies the IAM role for CW Logs. Keeping it that way avoids accidentally
# building log groups + roles inside a single-purpose VPC module.

variable "enable_flow_logs" {
  description = "Enable VPC flow logs."
  type        = bool
  default     = false
}

variable "flow_log_destination_type" {
  description = "Where flow logs land."
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], var.flow_log_destination_type)
    error_message = "flow_log_destination_type must be cloud-watch-logs, s3, or kinesis-data-firehose."
  }
}

variable "flow_log_traffic_type" {
  description = "Which traffic to log: ALL, ACCEPT, REJECT. ALL is verbose and pricey at scale."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ALL, ACCEPT, or REJECT."
  }
}

variable "flow_log_log_format" {
  description = "Custom log format string. Null = AWS default. Add ${"$"}{vpc-id}, ${"$"}{tcp-flags} etc when shipping to a SIEM."
  type        = string
  default     = null
}

variable "flow_log_max_aggregation_interval" {
  description = "Aggregation interval. 60s = expensive but fast detection; 600s = default."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the CW log group, S3 bucket, or Firehose stream."
  type        = string
  default     = null
}

variable "flow_log_iam_role_arn" {
  description = "IAM role for publishing logs. Required for cloud-watch-logs; ignored for s3."
  type        = string
  default     = null
}

# =============================================================================
# DNS resolver (Route 53 inbound + outbound)
# =============================================================================

variable "enable_dns_resolver_endpoints" {
  description = "Create inbound + outbound Route 53 resolver endpoints (hybrid DNS). Two ENIs each, in different AZs."
  type        = bool
  default     = false
}

variable "dns_resolver_subnet_ids" {
  description = "Subnets for the resolver ENIs. At least 2, in different AZs. Empty = the module picks intra/private subnets automatically."
  type        = list(string)
  default     = []
}

variable "dns_resolver_security_group_ids" {
  description = "SGs on resolver ENIs. Empty = the module builds a permissive demo SG. Replace in prod."
  type        = list(string)
  default     = []
}

# =============================================================================
# Default NACL
# =============================================================================

variable "manage_default_network_acl" {
  description = <<-EOT
    Adopt the default NACL via aws_default_network_acl and apply your rules.
    GOTCHA: this REPLACES the wide-open default rules. If you set both lists
    empty, every subnet associated with this NACL becomes unreachable until
    you populate the rules.
  EOT
  type        = bool
  default     = false
}

variable "default_network_acl_ingress" {
  description = "Ingress rules for the managed default NACL."
  type = list(object({
    rule_no    = number
    action     = string
    protocol   = string
    from_port  = number
    to_port    = number
    cidr_block = string
  }))
  default = []
}

variable "default_network_acl_egress" {
  description = "Egress rules for the managed default NACL."
  type = list(object({
    rule_no    = number
    action     = string
    protocol   = string
    from_port  = number
    to_port    = number
    cidr_block = string
  }))
  default = []
}

# =============================================================================
# VPC peering
# =============================================================================

variable "vpc_peerings" {
  description = <<-EOT
    Peering connections, keyed by short name. auto_accept works only for
    same-account same-region peerings. Cross-account/region peerings:
    create the requester here, manage the accepter in the peer account.
    peer_vpc_cidr is required if you want the module to add return routes;
    list the route tables that should learn the peer CIDR in route_table_ids.
  EOT
  type = map(object({
    peer_vpc_id     = string
    peer_owner_id   = optional(string)
    peer_region     = optional(string)
    peer_vpc_cidr   = optional(string)
    auto_accept     = optional(bool, true)
    route_table_ids = optional(list(string), [])
    tags            = optional(map(string), {})
  }))
  default = {}
}

# =============================================================================
# Transit Gateway
# =============================================================================

variable "transit_gateway_id" {
  description = "TGW id to attach the VPC to. Null disables the attachment entirely."
  type        = string
  default     = null
}

variable "transit_gateway_attachment_subnet_ids" {
  description = "Override subnets for the TGW attachment ENIs. Null = transit subnets (preferred), then private as fallback."
  type        = list(string)
  default     = null
}

variable "transit_gateway_appliance_mode" {
  description = "Enable when the VPC fronts a stateful inspection appliance (firewall). Pins forward + return flows to the same AZ."
  type        = string
  default     = "disable"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_appliance_mode)
    error_message = "transit_gateway_appliance_mode must be 'enable' or 'disable'."
  }
}

variable "transit_gateway_dns_support" {
  description = "Enable DNS resolution across the TGW attachment."
  type        = string
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_dns_support)
    error_message = "transit_gateway_dns_support must be 'enable' or 'disable'."
  }
}

variable "transit_gateway_ipv6_support" {
  description = "Enable IPv6 across the TGW attachment."
  type        = string
  default     = "disable"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_ipv6_support)
    error_message = "transit_gateway_ipv6_support must be 'enable' or 'disable'."
  }
}

variable "transit_gateway_attachment_tags" {
  description = "Extra tags for the TGW attachment."
  type        = map(string)
  default     = {}
}

variable "transit_gateway_routes" {
  description = <<-EOT
    Routes pointing at the TGW. Each entry expands into one aws_route per
    route table in route_table_ids. Typical use: ship the on-prem CIDR
    (e.g. 172.16.0.0/12) to private + intra route tables.

    Note: VPC route tables don't have a "blackhole" concept — that lives at
    the TGW route table itself. Don't add a route here if you want this VPC
    to drop traffic for that CIDR.
  EOT
  type = list(object({
    destination_cidr_block = string
    route_table_ids        = list(string)
  }))
  default = []
}
