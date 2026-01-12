# ============================================================================
# VPC Outputs
# ============================================================================

output "vpc_id" {
  description = "The ID of the VPC"
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "The CIDR block of the VPC"
  value = local.using_existing_vpc ? (
    data.aws_vpc.existing[0].cidr_block
    ) : (
    local.should_create_vpc ? aws_vpc.main[0].cidr_block : null
  )
}

output "vpc_arn" {
  description = "The ARN of the VPC"
  value = local.using_existing_vpc ? (
    data.aws_vpc.existing[0].arn
    ) : (
    local.should_create_vpc ? aws_vpc.main[0].arn : null
  )
}

output "vpc_default_security_group_id" {
  description = "The ID of the default security group"
  value = local.using_existing_vpc ? (
    data.aws_security_group.default[0].id
    ) : (
    local.should_create_vpc ? aws_vpc.main[0].default_security_group_id : null
  )
}

# ============================================================================
# Subnet Outputs
# ============================================================================

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value = local.using_existing_vpc ? var.public_subnet_ids : (
    local.should_create_vpc ? aws_subnet.public[*].id : []
  )
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value = local.using_existing_vpc ? var.private_subnet_ids : (
    local.should_create_vpc ? aws_subnet.private[*].id : []
  )
}

output "database_subnet_ids" {
  description = "List of database subnet IDs"
  value = local.using_existing_vpc ? var.database_subnet_ids : (
    local.should_create_vpc ? aws_subnet.database[*].id : []
  )
}

output "intra_subnet_ids" {
  description = "List of intra subnet IDs"
  value = local.using_existing_vpc ? var.intra_subnet_ids : (
    local.should_create_vpc ? aws_subnet.intra[*].id : []
  )
}

output "public_subnet_cidrs" {
  description = "List of public subnet CIDR blocks"
  value = local.using_existing_vpc ? (
    data.aws_subnet.existing_public[*].cidr_block
    ) : (
    local.should_create_vpc ? aws_subnet.public[*].cidr_block : []
  )
}

output "private_subnet_cidrs" {
  description = "List of private subnet CIDR blocks"
  value = local.using_existing_vpc ? (
    data.aws_subnet.existing_private[*].cidr_block
    ) : (
    local.should_create_vpc ? aws_subnet.private[*].cidr_block : []
  )
}

# ============================================================================
# Internet Gateway Outputs
# ============================================================================

output "internet_gateway_id" {
  description = "The ID of the Internet Gateway"
  value       = local.internet_gateway_id
}

# ============================================================================
# NAT Gateway Outputs
# ============================================================================

output "nat_gateway_ids" {
  description = "List of NAT Gateway IDs"
  value       = aws_nat_gateway.this[*].id
}

output "nat_eip_ids" {
  description = "List of Elastic IP IDs for NAT Gateways"
  value       = aws_eip.nat[*].id
}

# ============================================================================
# Route Table Outputs
# ============================================================================

output "public_route_table_ids" {
  description = "List of public route table IDs"
  value       = aws_route_table.public[*].id
}

output "private_route_table_ids" {
  description = "List of private route table IDs"
  value       = aws_route_table.private[*].id
}

# ============================================================================
# Security Group Outputs
# ============================================================================

output "security_group_ids" {
  description = "Map of security group IDs"
  value       = { for k, v in aws_security_group.custom : k => v.id }
}

# ============================================================================
# VPC Endpoint Outputs
# ============================================================================

output "vpc_endpoint_ids" {
  description = "Map of VPC endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "gateway_vpc_endpoint_ids" {
  description = "Map of gateway VPC endpoint IDs"
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

# ============================================================================
# Flow Logs Outputs
# ============================================================================

output "flow_log_id" {
  description = "The ID of the flow log"
  value       = var.enable_flow_logs ? aws_flow_log.this[0].id : null
}

# ============================================================================
# DNS Resolver Outputs
# ============================================================================

output "dns_resolver_endpoint_ids" {
  description = "Map of DNS resolver endpoint IDs"
  value = {
    inbound  = var.enable_dns_resolver_endpoints ? try(aws_route53_resolver_endpoint.inbound[0].id, null) : null
    outbound = var.enable_dns_resolver_endpoints ? try(aws_route53_resolver_endpoint.outbound[0].id, null) : null
  }
}

# ============================================================================
# VPC Peering Outputs
# ============================================================================

output "vpc_peering_connection_ids" {
  description = "Map of VPC peering connection IDs"
  value       = { for k, v in aws_vpc_peering_connection.this : k => v.id }
}

# ============================================================================
# Transit Gateway Outputs
# ============================================================================

output "transit_gateway_attachment_id" {
  description = "The ID of the transit gateway attachment"
  value       = var.transit_gateway_id != null ? aws_ec2_transit_gateway_vpc_attachment.this[0].id : null
}

# ============================================================================
# Availability Zones Outputs
# ============================================================================

output "availability_zones" {
  description = "List of availability zones used"
  value       = local.azs
}

# ============================================================================
# Complete Configuration
# ============================================================================

output "complete" {
  description = "Complete configuration of the network module"
  value = {
    vpc_id          = local.vpc_id
    public_subnets  = local.using_existing_vpc ? var.public_subnet_ids : aws_subnet.public[*].id
    private_subnets = local.using_existing_vpc ? var.private_subnet_ids : aws_subnet.private[*].id
    igw_id          = local.internet_gateway_id
    nat_gateways    = aws_nat_gateway.this[*].id
    route_tables = {
      public  = aws_route_table.public[*].id
      private = aws_route_table.private[*].id
    }
    security_groups = { for k, v in aws_security_group.custom : k => v.id }
  }
}
