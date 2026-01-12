# ============================================================================
# Module Identity
# ============================================================================

variable "name" {
  description = "Name prefix for all resources"
  type        = string

  validation {
    condition     = length(var.name) > 0 && length(var.name) <= 60
    error_message = "Name must be between 1 and 60 characters."
  }
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod", "test", "sandbox"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod, test, sandbox."
  }
}

variable "tags" {
  description = "A map of tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ============================================================================
# VPC Configuration (Existing or Create New)
# ============================================================================

variable "vpc_id" {
  description = "ID of an existing VPC to use. If not provided, a new VPC will be created."
  type        = string
  default     = null
}

variable "create_vpc" {
  description = "Whether to create a new VPC. If vpc_id is provided, this will be ignored."
  type        = bool
  default     = false
}

# ----------------------------------------------------------------------------
# New VPC Configuration (only used if creating a new VPC)
# ----------------------------------------------------------------------------

variable "vpc_cidr_block" {
  description = "CIDR block for the new VPC (required if creating new VPC)"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr_block, 0))
    error_message = "VPC CIDR block must be in valid CIDR notation."
  }
}

variable "secondary_cidr_blocks" {
  description = "List of secondary IPv4 CIDR blocks to associate with the VPC"
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.secondary_cidr_blocks : can(cidrhost(cidr, 0))
    ])
    error_message = "All secondary CIDR blocks must be in valid CIDR notation."
  }
}

variable "enable_ipv6" {
  description = "Whether to request an IPv6 CIDR block from Amazon"
  type        = bool
  default     = false
}

variable "instance_tenancy" {
  description = "Tenancy option for instances launched into the VPC"
  type        = string
  default     = "default"

  validation {
    condition     = contains(["default", "dedicated"], var.instance_tenancy)
    error_message = "Instance tenancy must be either 'default' or 'dedicated'."
  }
}

variable "enable_dns_support" {
  description = "Whether to enable DNS support in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Whether to enable DNS hostnames in the VPC"
  type        = bool
  default     = true
}

variable "enable_network_address_usage_metrics" {
  description = "Whether to enable network address usage metrics"
  type        = bool
  default     = false
}

# ============================================================================
# Subnet Configuration
# ============================================================================

variable "availability_zones" {
  description = "List of availability zones to use for subnets"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]

  validation {
    condition     = length(var.availability_zones) >= 1 && length(var.availability_zones) <= 6
    error_message = "Must specify 1 to 6 availability zones."
  }
}

# ----------------------------------------------------------------------------
# Subnet Creation Options (for new VPC)
# ----------------------------------------------------------------------------

variable "create_subnets" {
  description = "Whether to create subnets in the VPC"
  type        = bool
  default     = true
}

variable "public_subnets" {
  description = "CIDR blocks for public subnets. If list is empty, no public subnets will be created."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.public_subnets : can(cidrhost(cidr, 0))
    ])
    error_message = "All public subnet CIDRs must be in valid CIDR notation."
  }
}

variable "private_subnets" {
  description = "CIDR blocks for private subnets. If list is empty, no private subnets will be created."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.private_subnets : can(cidrhost(cidr, 0))
    ])
    error_message = "All private subnet CIDRs must be in valid CIDR notation."
  }
}

variable "database_subnets" {
  description = "CIDR blocks for database subnets. If list is empty, no database subnets will be created."
  type        = list(string)
  default     = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  validation {
    condition = alltrue([
      for cidr in var.database_subnets : can(cidrhost(cidr, 0))
    ])
    error_message = "All database subnet CIDRs must be in valid CIDR notation."
  }
}

variable "intra_subnets" {
  description = "CIDR blocks for intra subnets. If list is empty, no intra subnets will be created."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for cidr in var.intra_subnets : can(cidrhost(cidr, 0))
    ])
    error_message = "All intra subnet CIDRs must be in valid CIDR notation."
  }
}

variable "map_public_ip_on_launch" {
  description = "Whether to auto-assign public IP on EC2 launch in public subnets"
  type        = bool
  default     = true
}

# ----------------------------------------------------------------------------
# Existing Subnets (for existing VPC)
# ----------------------------------------------------------------------------

variable "public_subnet_ids" {
  description = "List of existing public subnet IDs to use with existing VPC"
  type        = list(string)
  default     = []
}

variable "private_subnet_ids" {
  description = "List of existing private subnet IDs to use with existing VPC"
  type        = list(string)
  default     = []
}

variable "database_subnet_ids" {
  description = "List of existing database subnet IDs to use with existing VPC"
  type        = list(string)
  default     = []
}

variable "intra_subnet_ids" {
  description = "List of existing intra subnet IDs to use with existing VPC"
  type        = list(string)
  default     = []
}

# ----------------------------------------------------------------------------
# Subnet Tags
# ----------------------------------------------------------------------------

variable "public_subnet_tags" {
  description = "Additional tags for public subnets"
  type        = map(string)
  default     = {}
}

variable "private_subnet_tags" {
  description = "Additional tags for private subnets"
  type        = map(string)
  default     = {}
}

variable "database_subnet_tags" {
  description = "Additional tags for database subnets"
  type        = map(string)
  default     = {}
}

variable "intra_subnet_tags" {
  description = "Additional tags for intra subnets"
  type        = map(string)
  default     = {}
}

# ============================================================================
# NAT Gateway Configuration
# ============================================================================

variable "enable_nat_gateway" {
  description = "Whether to create NAT gateways for private subnets"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "Whether to create a single shared NAT gateway across all AZs"
  type        = bool
  default     = false
}

variable "one_nat_gateway_per_az" {
  description = "Whether to create one NAT gateway per availability zone"
  type        = bool
  default     = true
}

variable "nat_gateway_subnet_ids" {
  description = "List of subnet IDs where NAT gateways should be created (for existing VPC)"
  type        = list(string)
  default     = []
}

variable "nat_gateway_eip_ids" {
  description = "List of existing Elastic IP IDs to attach to NAT gateways"
  type        = list(string)
  default     = []
}

variable "nat_gateway_tags" {
  description = "Additional tags for NAT gateways"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_destination_cidr_block" {
  description = "The destination CIDR block for NAT gateway routes (defaults to 0.0.0.0/0 for internet access)"
  type        = string
  default     = "0.0.0.0/0"

  validation {
    condition     = can(cidrhost(var.nat_gateway_destination_cidr_block, 0))
    error_message = "NAT gateway destination CIDR block must be in valid CIDR notation."
  }
}

# ============================================================================
# Internet Gateway Configuration
# ============================================================================

variable "internet_gateway_id" {
  description = "ID of existing Internet Gateway to use (for existing VPC)"
  type        = string
  default     = null
}

variable "create_internet_gateway" {
  description = "Whether to create an Internet Gateway"
  type        = bool
  default     = true
}

variable "internet_gateway_tags" {
  description = "Additional tags for internet gateway"
  type        = map(string)
  default     = {}
}

# ============================================================================
# Route Table Configuration
# ============================================================================

variable "public_route_table_ids" {
  description = "List of existing public route table IDs (for existing VPC)"
  type        = list(string)
  default     = []
}

variable "private_route_table_ids" {
  description = "List of existing private route table IDs (for existing VPC)"
  type        = list(string)
  default     = []
}

variable "create_public_route_table" {
  description = "Whether to create public route table"
  type        = bool
  default     = true
}

variable "create_private_route_tables" {
  description = "Whether to create private route tables"
  type        = bool
  default     = true
}

variable "public_route_table_tags" {
  description = "Additional tags for public route tables"
  type        = map(string)
  default     = {}
}

variable "private_route_table_tags" {
  description = "Additional tags for private route tables"
  type        = map(string)
  default     = {}
}

# ============================================================================
# VPC Endpoint Configuration
# ============================================================================

variable "vpc_endpoints" {
  description = "Map of VPC endpoint configurations"
  type = map(object({
    service_name        = string
    vpc_endpoint_type   = optional(string, "Interface")
    private_dns_enabled = optional(bool, true)
    security_group_ids  = optional(list(string), [])
    subnet_ids          = optional(list(string), [])
    route_table_ids     = optional(list(string), [])
    policy              = optional(string, null)
    tags                = optional(map(string), {})
  }))
  default = {}
}

variable "gateway_vpc_endpoints" {
  description = "Map of gateway VPC endpoint configurations"
  type = map(object({
    service_name    = string
    route_table_ids = list(string)
    policy          = optional(string, null)
    tags            = optional(map(string), {})
  }))
  default = {}
}

# ============================================================================
# Security Group Configuration
# ============================================================================

variable "security_groups" {
  description = "Map of security group configurations to create"
  type = map(object({
    name        = optional(string, null)
    description = string
    ingress_rules = optional(list(object({
      description      = optional(string, null)
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
      description      = optional(string, null)
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

variable "default_security_group_ingress" {
  description = "List of ingress rules to apply to default security group"
  type = list(object({
    description     = optional(string, null)
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  default = []
}

variable "default_security_group_egress" {
  description = "List of egress rules to apply to default security group"
  type = list(object({
    description     = optional(string, null)
    from_port       = number
    to_port         = number
    protocol        = string
    cidr_blocks     = optional(list(string), [])
    security_groups = optional(list(string), [])
    self            = optional(bool, false)
  }))
  default = []
}

# ============================================================================
# Flow Logs Configuration
# ============================================================================

variable "enable_flow_logs" {
  description = "Whether to enable VPC Flow Logs"
  type        = bool
  default     = false
}

variable "flow_log_destination_type" {
  description = "Type of flow log destination (cloud-watch-logs, s3)"
  type        = string
  default     = "cloud-watch-logs"

  validation {
    condition     = contains(["cloud-watch-logs", "s3"], var.flow_log_destination_type)
    error_message = "Flow log destination type must be either 'cloud-watch-logs' or 's3'."
  }
}

variable "flow_log_traffic_type" {
  description = "Type of traffic to log (ALL, ACCEPT, REJECT)"
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ALL", "ACCEPT", "REJECT"], var.flow_log_traffic_type)
    error_message = "Flow log traffic type must be one of: ALL, ACCEPT, REJECT."
  }
}

variable "flow_log_log_format" {
  description = "The fields to include in the flow log record"
  type        = string
  default     = null
}

variable "flow_log_max_aggregation_interval" {
  description = "Maximum interval during which a flow is captured and aggregated into a flow log record"
  type        = number
  default     = 600

  validation {
    condition     = var.flow_log_max_aggregation_interval == 60 || var.flow_log_max_aggregation_interval == 600
    error_message = "Flow log max aggregation interval must be either 60 or 600 seconds."
  }
}

variable "flow_log_destination_arn" {
  description = "ARN of the CloudWatch Logs log group or S3 bucket for flow logs"
  type        = string
  default     = null
}

variable "flow_log_iam_role_arn" {
  description = "ARN of IAM role for flow logs (required for CloudWatch Logs)"
  type        = string
  default     = null
}

# ============================================================================
# DNS Configuration
# ============================================================================

variable "enable_dns_resolver_endpoints" {
  description = "Whether to create inbound and outbound DNS resolver endpoints"
  type        = bool
  default     = false
}

variable "dns_resolver_subnet_ids" {
  description = "Subnet IDs for DNS resolver endpoints"
  type        = list(string)
  default     = []
}

variable "dns_resolver_security_group_ids" {
  description = "Security group IDs for DNS resolver endpoints"
  type        = list(string)
  default     = []
}

# ============================================================================
# Network ACL Configuration
# ============================================================================

variable "manage_default_network_acl" {
  description = "Whether to manage default network ACL rules"
  type        = bool
  default     = false
}

variable "default_network_acl_ingress" {
  description = "List of ingress rules to add to default network ACL"
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
  description = "List of egress rules to add to default network ACL"
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

# ============================================================================
# Route Management
# ============================================================================

variable "public_routes" {
  description = "List of additional routes to add to public route tables"
  type = list(object({
    route_table_id            = string
    destination_cidr_block    = optional(string, null)
    gateway_id                = optional(string, null)
    nat_gateway_id            = optional(string, null)
    vpc_endpoint_id           = optional(string, null)
    transit_gateway_id        = optional(string, null)
    vpc_peering_connection_id = optional(string, null)
  }))
  default = []
}

variable "private_routes" {
  description = "List of additional routes to add to private route tables"
  type = list(object({
    route_table_id            = string
    destination_cidr_block    = optional(string, null)
    gateway_id                = optional(string, null)
    nat_gateway_id            = optional(string, null)
    vpc_endpoint_id           = optional(string, null)
    transit_gateway_id        = optional(string, null)
    vpc_peering_connection_id = optional(string, null)
  }))
  default = []
}

# ============================================================================
# Peering Configuration
# ============================================================================

variable "vpc_peerings" {
  description = "Map of VPC peering connections to create"
  type = map(object({
    peer_vpc_id     = string
    peer_owner_id   = optional(string, null)
    peer_region     = optional(string, null)
    auto_accept     = optional(bool, true)
    route_table_ids = optional(list(string), [])
    tags            = optional(map(string), {})
  }))
  default = {}
}

# ============================================================================
# Transit Gateway Attachment
# ============================================================================

variable "transit_gateway_id" {
  description = "ID of Transit Gateway to attach VPC to"
  type        = string
  default     = null
}

variable "transit_gateway_routes" {
  description = "Routes to add through transit gateway"
  type = list(object({
    destination_cidr_block = string
    route_table_ids        = list(string)
  }))
  default = []
}
