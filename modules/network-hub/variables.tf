# Identity

variable "name" {
  description = "Name prefix used on every resource created by the module."
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 60
    error_message = "name must be between 1 and 60 characters."
  }
}

variable "environment" {
  description = "Deployment environment. Emitted as the Environment tag."
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags applied to every resource. Use this for cost-allocation keys (Project, Team, CostCenter, Owner, ...)."
  type        = map(string)
  default     = {}
}

# VPC: create or adopt

variable "vpc_id" {
  description = "ID of an existing VPC to adopt. When set, the module skips VPC/subnet creation and operates on the given VPC."
  type        = string
  default     = null
}

variable "create_vpc" {
  description = "Create a new VPC. Ignored when vpc_id is set."
  type        = bool
  default     = false
}

variable "vpc_cidr_block" {
  description = "Primary IPv4 CIDR for the new VPC. Required when create_vpc = true."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "vpc_cidr_block must be a valid CIDR."
  }
}

variable "secondary_cidr_blocks" {
  description = "Additional IPv4 CIDRs to associate with the VPC."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.secondary_cidr_blocks : can(cidrhost(c, 0))])
    error_message = "All secondary_cidr_blocks must be valid CIDRs."
  }
}

variable "enable_ipv6" {
  description = "Request an Amazon-provided /56 IPv6 block for the VPC."
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "VPC tenancy mode."
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "instance_tenancy must be 'default' or 'dedicated'."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS resolution inside the VPC."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Assign public DNS hostnames to instances with public IPs."
  type        = bool
  default     = true
}

variable "enable_network_address_usage_metrics" {
  description = "Publish NetworkAddressUsage CloudWatch metrics for the VPC."
  type        = bool
  default     = false
}

# Subnets

variable "availability_zones" {
  description = "AZs to distribute subnets across. One subnet per tier per AZ."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 6
    error_message = "availability_zones must list 1 to 6 AZs."
  }
}

variable "create_subnets" {
  description = "Create subnets in the new VPC. Set to false if subnets are managed outside the module."
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Auto-assign public IPv4 on instances launched in public subnets."
  type        = bool
  default     = true
}

# Per-tier subnet CIDRs. One entry per AZ; an empty list disables the tier.
# The tiers are:
#   public   - reachable from the internet (IGW route)
#   private  - workloads; outbound to internet via NAT
#   database - RDS/ElastiCache/etc, no default route out of the VPC
#   intra    - internal-only traffic (ENIs for control-plane, VPC endpoints, internal LBs)
#   transit  - dedicated small subnets (/28 is typical) that host the Transit
#              Gateway / Cloud WAN attachment ENIs. Keeping TGW attachments in
#              their own tier isolates on-prem routing from workload subnets and
#              simplifies route tables. Strongly recommended for hybrid setups.

variable "public_subnets" {
  description = "CIDR blocks for public subnets. Empty list disables the tier."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition     = alltrue([for c in var.public_subnets : can(cidrhost(c, 0))])
    error_message = "All public_subnets must be valid CIDRs."
  }
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets. Empty list disables the tier."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  validation {
    condition     = alltrue([for c in var.private_subnets : can(cidrhost(c, 0))])
    error_message = "All private_subnets must be valid CIDRs."
  }
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets. Empty list disables the tier."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  validation {
    condition     = alltrue([for c in var.database_subnets : can(cidrhost(c, 0))])
    error_message = "All database_subnets must be valid CIDRs."
  }
}

variable "intra_subnets" {
  description = "CIDR blocks for intra subnets. Empty list disables the tier."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.intra_subnets : can(cidrhost(c, 0))])
    error_message = "All intra_subnets must be valid CIDRs."
  }
}

variable "transit_subnets" {
  description = <<-EOT
    CIDR blocks for transit subnets (TGW / Cloud WAN attachment ENIs). Empty
    list disables the tier. A /28 per AZ is normally enough. When set, the
    module wires the Transit Gateway VPC attachment into these subnets rather
    than the private ones.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.transit_subnets : can(cidrhost(c, 0))])
    error_message = "All transit_subnets must be valid CIDRs."
  }
}

# Existing subnets (for existing VPC mode)

variable "public_subnet_ids" {
  description = "Existing public subnet IDs. Only used when adopting an existing VPC."
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "Existing private subnet IDs. Only used when adopting an existing VPC."
  type        = list(string)
  default     = []
}

variable "database_subnet_ids" {
  description = "Existing database subnet IDs. Only used when adopting an existing VPC."
  type        = list(string)
  default     = []
}

variable "intra_subnet_ids" {
  description = "Existing intra subnet IDs. Only used when adopting an existing VPC."
  type        = list(string)
  default     = []
}

variable "transit_subnet_ids" {
  description = "Existing transit subnet IDs. Only used when adopting an existing VPC."
  type        = list(string)
  default     = []
}

# Per-tier subnet tags

variable "public_subnet_tags" {
  description = "Extra tags for public subnets."
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Extra tags for private subnets."
  type        = map(string)
  default     = {}
}

variable "database_subnet_tags" {
  description = "Extra tags for database subnets."
  type        = map(string)
  default     = {}
}

variable "intra_subnet_tags" {
  description = "Extra tags for intra subnets."
  type        = map(string)
  default     = {}
}

variable "transit_subnet_tags" {
  description = "Extra tags for transit subnets."
  type        = map(string)
  default     = {}
}

# NAT gateways

variable "enable_nat_gateway" {
  description = "Create NAT gateways so private subnets can reach the internet."
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Use a single NAT gateway shared across all AZs. Cheaper, but no HA."
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "One NAT gateway per AZ (HA). Ignored when single_nat_gateway = true."
  type        = bool
  default     = true
}

variable "nat_gateway_subnet_ids" {
  description = "Override which subnets host the NAT gateways. Defaults to the public subnets."
  type        = list(string)
  default     = []
}

variable "nat_gateway_eip_ids" {
  description = "Pre-allocated EIPs to attach to NAT gateways. One per gateway."
  type        = list(string)
  default     = []
}

variable "nat_gateway_tags" {
  description = "Extra tags for NAT gateways and their EIPs."
  type        = map(string)
  default     = {}
}

variable "nat_gateway_destination_cidr_block" {
  description = "Destination CIDR for private route tables routed via the NAT gateway."
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.nat_gateway_destination_cidr_block, 0))
    error_message = "nat_gateway_destination_cidr_block must be a valid CIDR."
  }
}

# Internet gateway

variable "internet_gateway_id" {
  description = "Existing IGW ID to adopt. When set, the module will not create one."
  type        = string
  default     = null
}

variable "create_internet_gateway" {
  description = "Create an IGW for the VPC. Ignored when internet_gateway_id is set."
  type        = bool
  default     = true
}

variable "internet_gateway_tags" {
  description = "Extra tags for the internet gateway."
  type        = map(string)
  default     = {}
}

# Route tables

variable "create_public_route_table" {
  description = "Create a route table for public subnets."
  type        = bool
  default     = true
}

variable "create_private_route_tables" {
  description = "Create route tables for private subnets (one per AZ)."
  type        = bool
  default     = true
}

variable "create_database_route_table" {
  description = "Create a dedicated route table for database subnets. Database subnets do not get a default route out of the VPC."
  type        = bool
  default     = true
}

variable "create_intra_route_table" {
  description = "Create a dedicated route table for intra subnets. Like database, no default route."
  type        = bool
  default     = true
}

variable "create_transit_route_table" {
  description = "Create a dedicated route table for transit subnets. Host-only; no default route added by the module."
  type        = bool
  default     = true
}

variable "public_route_table_tags" {
  description = "Extra tags for public route tables."
  type        = map(string)
  default     = {}
}

variable "private_route_table_tags" {
  description = "Extra tags for private route tables."
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
  description = "Additional routes to install on public route tables."
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
  description = "Additional routes to install on private route tables."
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

# VPC endpoints

variable "vpc_endpoints" {
  description = "Interface VPC endpoints. Keyed by a short name used in the resource name."
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
  description = "Gateway VPC endpoints (S3, DynamoDB). Keyed by short name."
  type = map(object({
    service_name    = string
    route_table_ids = list(string)
    policy          = optional(string)
    tags            = optional(map(string), {})
  }))
  default = {}
}

# Security groups

variable "security_groups" {
  description = "Custom security groups to create, keyed by a short name."
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
  description = "Take ownership of the VPC's default security group via aws_default_security_group and apply the rules below. Recommended: empty lists strip every default rule, which is the AWS security best practice."
  type        = bool
  default     = false
}

variable "default_security_group_ingress" {
  description = "Ingress rules applied to the default SG when manage_default_security_group = true."
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
  description = "Egress rules applied to the default SG when manage_default_security_group = true."
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

# Flow logs

variable "enable_flow_logs" {
  description = "Enable VPC Flow Logs. Caller supplies the destination and (for CW Logs) the IAM role."
  type        = bool
  default     = false
}

variable "flow_log_destination_type" {
  description = "Flow log destination type."
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3", "kinesis-data-firehose"], var.flow_log_destination_type)
    error_message = "flow_log_destination_type must be cloud-watch-logs, s3, or kinesis-data-firehose."
  }
}

variable "flow_log_traffic_type" {
  description = "Which traffic to log."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_log_traffic_type)
    error_message = "flow_log_traffic_type must be ALL, ACCEPT, or REJECT."
  }
}

variable "flow_log_log_format" {
  description = "Custom flow log format string. Null means the AWS default."
  type        = string
  default     = null
}

variable "flow_log_max_aggregation_interval" {
  description = "Flow log aggregation interval (60 or 600 seconds)."
  type        = number
  default     = 600

  validation {
    condition     = contains([60, 600], var.flow_log_max_aggregation_interval)
    error_message = "flow_log_max_aggregation_interval must be 60 or 600."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the CloudWatch log group, S3 bucket, or Kinesis Firehose stream."
  type        = string
  default     = null
}

variable "flow_log_iam_role_arn" {
  description = "IAM role ARN used to publish logs. Required for the cloud-watch-logs destination."
  type        = string
  default     = null
}

# DNS resolver (Route 53 Resolver endpoints)

variable "enable_dns_resolver_endpoints" {
  description = "Create inbound + outbound Route 53 Resolver endpoints. Useful for hybrid DNS."
  type        = bool
  default     = false
}

variable "dns_resolver_subnet_ids" {
  description = "Subnet IDs hosting the resolver ENIs. At least two in different AZs."
  type        = list(string)
  default     = []
}

variable "dns_resolver_security_group_ids" {
  description = "Security groups on the resolver ENIs. When empty, the module creates a permissive SG for demo purposes. Replace in production."
  type        = list(string)
  default     = []
}

# Default NACL

variable "manage_default_network_acl" {
  description = "Take ownership of the default NACL via aws_default_network_acl and apply the rules below."
  type        = bool
  default     = false
}

variable "default_network_acl_ingress" {
  description = "Ingress rules applied to the default NACL when managed."
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
  description = "Egress rules applied to the default NACL when managed."
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

# VPC peering

variable "vpc_peerings" {
  description = "VPC peering connections to create."
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

# Transit Gateway

variable "transit_gateway_id" {
  description = "ID of a Transit Gateway to attach the VPC to. Null disables the attachment."
  type        = string
  default     = null
}

variable "transit_gateway_attachment_subnet_ids" {
  description = "Subnets for the TGW attachment ENIs. When null, the module uses transit_subnets (preferred) or falls back to private subnets."
  type        = list(string)
  default     = null
}

variable "transit_gateway_appliance_mode" {
  description = "Enable appliance-mode on the TGW attachment. Required when the VPC hosts a stateful inspection appliance (e.g. firewall) so forward + return flow land on the same AZ."
  type        = string
  default     = "disable"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_appliance_mode)
    error_message = "transit_gateway_appliance_mode must be 'enable' or 'disable'."
  }
}

variable "transit_gateway_dns_support" {
  description = "Enable DNS support on the TGW attachment."
  type        = string
  default     = "enable"

  validation {
    condition     = contains(["enable", "disable"], var.transit_gateway_dns_support)
    error_message = "transit_gateway_dns_support must be 'enable' or 'disable'."
  }
}

variable "transit_gateway_ipv6_support" {
  description = "Enable IPv6 on the TGW attachment."
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
    Routes pointing at the Transit Gateway, expanded across one or more route
    tables. Typical use: route on-prem CIDRs from the private and intra
    route tables toward the TGW.
  EOT
  type = list(object({
    destination_cidr_block = string
    route_table_ids        = list(string)
  }))
  default = []
}
