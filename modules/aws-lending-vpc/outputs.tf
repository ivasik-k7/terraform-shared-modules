# =============================================================================
# VPC
# =============================================================================
output "vpc_id" {
  description = "VPC id (created or adopted)."
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "Primary VPC CIDR."
  value       = local.vpc_cidr_block
}

output "vpc_arn" {
  description = "VPC ARN."
  value = local.using_existing_vpc ? data.aws_vpc.existing[0].arn : (
    local.should_create_vpc ? aws_vpc.this[0].arn : null
  )
}

output "vpc_default_security_group_id" {
  description = "Default SG id for the VPC. Populated when the module created the VPC, or when manage_default_security_group is on."
  value = local.should_create_vpc ? aws_vpc.this[0].default_security_group_id : (
    var.manage_default_security_group ? aws_default_security_group.this[0].id : null
  )
}

# =============================================================================
# Subnets — flat lists per tier
# =============================================================================
output "public_subnet_ids" {
  description = "Public subnet ids."
  value       = local.public_subnet_ids_effective
}

output "private_subnet_ids" {
  description = "Private subnet ids."
  value       = local.private_subnet_ids_effective
}

output "database_subnet_ids" {
  description = "Database subnet ids."
  value       = local.database_subnet_ids_effective
}

output "intra_subnet_ids" {
  description = "Intra subnet ids."
  value       = local.intra_subnet_ids_effective
}

output "transit_subnet_ids" {
  description = "Transit subnet ids (TGW/Cloud WAN attachment hosts)."
  value       = local.transit_subnet_ids_effective
}

output "public_subnet_cidrs" {
  description = "Public subnet CIDRs."
  value = local.using_existing_vpc ? data.aws_subnet.existing_public[*].cidr_block : (
    local.should_create_vpc ? aws_subnet.public[*].cidr_block : []
  )
}

output "private_subnet_cidrs" {
  description = "Private subnet CIDRs."
  value = local.using_existing_vpc ? data.aws_subnet.existing_private[*].cidr_block : (
    local.should_create_vpc ? aws_subnet.private[*].cidr_block : []
  )
}

output "database_subnet_cidrs" {
  description = "Database subnet CIDRs."
  value = local.using_existing_vpc ? data.aws_subnet.existing_database[*].cidr_block : (
    local.should_create_vpc ? aws_subnet.database[*].cidr_block : []
  )
}

output "intra_subnet_cidrs" {
  description = "Intra subnet CIDRs."
  value = local.using_existing_vpc ? data.aws_subnet.existing_intra[*].cidr_block : (
    local.should_create_vpc ? aws_subnet.intra[*].cidr_block : []
  )
}

output "transit_subnet_cidrs" {
  description = "Transit subnet CIDRs."
  value = local.using_existing_vpc ? data.aws_subnet.existing_transit[*].cidr_block : (
    local.should_create_vpc ? aws_subnet.transit[*].cidr_block : []
  )
}

# =============================================================================
# Subnets — keyed by AZ (DX win for downstream modules)
# =============================================================================
# Lets consumers do:
#   subnet_id = module.vpc.subnets_by_az["eu-west-1a"].private
# instead of slicing flat lists by index. Resilient to AZ reorders.
output "subnets_by_az" {
  description = "Per-AZ map of tier -> subnet id. Tier values are null when the tier is disabled."
  value       = local.subnets_by_az
}

# =============================================================================
# Gateways
# =============================================================================
output "internet_gateway_id" {
  description = "Internet Gateway id."
  value       = local.internet_gateway_id
}

output "nat_gateway_ids" {
  description = "NAT gateway ids."
  value       = aws_nat_gateway.this[*].id
}

output "nat_eip_ids" {
  description = "NAT gateway EIP allocation ids (only EIPs the module allocated; pre-supplied EIPs are not echoed here)."
  value       = aws_eip.nat[*].id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways. Useful for on-prem firewall allowlists."
  value       = aws_nat_gateway.this[*].public_ip
}

# =============================================================================
# Route tables
# =============================================================================
output "public_route_table_ids" {
  description = "Public route table ids."
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "Private route table ids (one per AZ)."
  value       = aws_route_table.private[*].id
}

output "database_route_table_id" {
  description = "Database route table id. Null when the tier is disabled."
  value       = length(aws_route_table.database) > 0 ? aws_route_table.database[0].id : null
}

output "intra_route_table_id" {
  description = "Intra route table id. Null when the tier is disabled."
  value       = length(aws_route_table.intra) > 0 ? aws_route_table.intra[0].id : null
}

output "transit_route_table_id" {
  description = "Transit route table id. Null when the tier is disabled."
  value       = length(aws_route_table.transit) > 0 ? aws_route_table.transit[0].id : null
}

# =============================================================================
# Endpoints, SGs, resolver
# =============================================================================
output "security_group_ids" {
  description = "Custom SG ids keyed by short name."
  value       = { for k, v in aws_security_group.custom : k => v.id }
}

output "endpoint_security_group_id" {
  description = "Default SG id used by interface endpoints when the caller didn't pass one. Null when not in use."
  value       = local.default_endpoint_security_group_id
}

output "vpc_endpoint_ids" {
  description = "Interface VPC endpoint ids keyed by short name (preset + explicit, merged)."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "vpc_endpoint_dns_entries" {
  description = "Interface endpoint private DNS entries. Useful for app config when private DNS is disabled."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.dns_entry }
}

output "gateway_vpc_endpoint_ids" {
  description = "Gateway VPC endpoint ids keyed by short name."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "flow_log_id" {
  description = "Flow log id. Null when disabled."
  value       = var.enable_flow_logs ? aws_flow_log.this[0].id : null
}

output "dns_resolver_endpoint_ids" {
  description = "Inbound and outbound Route 53 Resolver endpoint ids."
  value = {
    inbound  = length(aws_route53_resolver_endpoint.inbound) > 0 ? aws_route53_resolver_endpoint.inbound[0].id : null
    outbound = length(aws_route53_resolver_endpoint.outbound) > 0 ? aws_route53_resolver_endpoint.outbound[0].id : null
  }
}

# =============================================================================
# Peering and TGW
# =============================================================================
output "vpc_peering_connection_ids" {
  description = "VPC peering connection ids keyed by short name."
  value       = { for k, v in aws_vpc_peering_connection.this : k => v.id }
}

output "transit_gateway_attachment_id" {
  description = "TGW VPC attachment id. Null when not attached."
  value       = var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : null
}

output "transit_gateway_attachment_subnet_ids" {
  description = "Subnets the TGW attachment ENIs landed in."
  value       = var.transit_gateway_id != null ? local.transit_gateway_attachment_subnets : []
}

# =============================================================================
# Misc + summary
# =============================================================================
output "availability_zones" {
  description = "AZs the module distributed subnets across."
  value       = local.azs
}

# Single object suitable for "wire into downstream module" patterns. Keeps
# call-sites short:
#   module "ecs_cluster" {
#     network = module.vpc.network
#   }
output "network" {
  description = "Consolidated network description. Pass into downstream workload modules."
  value = {
    vpc_id        = local.vpc_id
    vpc_cidr      = local.vpc_cidr_block
    azs           = local.azs
    subnets_by_az = local.subnets_by_az
    subnets = {
      public   = local.public_subnet_ids_effective
      private  = local.private_subnet_ids_effective
      database = local.database_subnet_ids_effective
      intra    = local.intra_subnet_ids_effective
      transit  = local.transit_subnet_ids_effective
    }
    igw_id          = local.internet_gateway_id
    nat_gateway_ids = aws_nat_gateway.this[*].id
    nat_public_ips  = aws_nat_gateway.this[*].public_ip
    route_tables = {
      public   = aws_route_table.public[*].id
      private  = aws_route_table.private[*].id
      database = length(aws_route_table.database) > 0 ? aws_route_table.database[0].id : null
      intra    = length(aws_route_table.intra) > 0 ? aws_route_table.intra[0].id : null
      transit  = length(aws_route_table.transit) > 0 ? aws_route_table.transit[0].id : null
    }
    security_groups = {
      custom            = { for k, v in aws_security_group.custom : k => v.id }
      default           = local.should_create_vpc ? aws_vpc.this[0].default_security_group_id : null
      endpoints_default = local.default_endpoint_security_group_id
    }
    endpoints = {
      interface = { for k, v in aws_vpc_endpoint.interface : k => v.id }
      gateway   = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
    }
    tgw_attachment_id = var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : null
  }
}

# Backward-compat with callers that referenced the old `summary` output. Same
# keys as the v1 module; new code should use `network` above.
output "summary" {
  description = "DEPRECATED: use `network` instead. Kept for backward compatibility with the previous network-hub module."
  value = {
    vpc_id           = local.vpc_id
    vpc_cidr         = local.vpc_cidr_block
    azs              = local.azs
    public_subnets   = local.public_subnet_ids_effective
    private_subnets  = local.private_subnet_ids_effective
    database_subnets = local.database_subnet_ids_effective
    intra_subnets    = local.intra_subnet_ids_effective
    transit_subnets  = local.transit_subnet_ids_effective
    igw_id           = local.internet_gateway_id
    nat_gateways     = aws_nat_gateway.this[*].id
    route_tables = {
      public   = aws_route_table.public[*].id
      private  = aws_route_table.private[*].id
      database = length(aws_route_table.database) > 0 ? aws_route_table.database[0].id : null
      intra    = length(aws_route_table.intra) > 0 ? aws_route_table.intra[0].id : null
      transit  = length(aws_route_table.transit) > 0 ? aws_route_table.transit[0].id : null
    }
    security_groups   = { for k, v in aws_security_group.custom : k => v.id }
    tgw_attachment_id = var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : null
  }
}
