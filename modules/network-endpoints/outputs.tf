# ─────────────────────────────────────────────────────────────────────────────
# Security Group
# ─────────────────────────────────────────────────────────────────────────────

output "security_group_id" {
  description = "ID of the default security group created by this module (null when create_default_security_group = false)."
  value       = local.create_default_sg ? aws_security_group.default[0].id : null
}

output "security_group_arn" {
  description = "ARN of the default security group."
  value       = local.create_default_sg ? aws_security_group.default[0].arn : null
}

# ─────────────────────────────────────────────────────────────────────────────
# Merged view across all endpoint types
# ─────────────────────────────────────────────────────────────────────────────

output "endpoints" {
  description = <<-EOT
    Flat map of ALL provisioned VPC endpoints keyed by the logical name you
    provided in var.endpoints. Each value exposes the full aws_vpc_endpoint
    resource attributes, giving you a single place to look up IDs, DNS entries,
    ARNs, and state regardless of the underlying endpoint type.
  EOT

  value = merge(
    { for k, v in aws_vpc_endpoint.interface : k => v },
    { for k, v in aws_vpc_endpoint.gateway : k => v },
    { for k, v in aws_vpc_endpoint.gwlb : k => v },
  )
}

# ─────────────────────────────────────────────────────────────────────────────
# Interface endpoints
# ─────────────────────────────────────────────────────────────────────────────

output "interface_endpoints" {
  description = "Map of Interface VPC endpoint objects keyed by logical name."
  value       = aws_vpc_endpoint.interface
}

output "interface_endpoint_ids" {
  description = "Map of Interface endpoint IDs keyed by logical name."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "interface_endpoint_arns" {
  description = "Map of Interface endpoint ARNs keyed by logical name."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.arn }
}

output "interface_endpoint_dns_entries" {
  description = "Map of DNS entry lists for each Interface endpoint. Each list item has 'dns_name' and 'hosted_zone_id' attributes."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.dns_entry }
}

output "interface_endpoint_network_interface_ids" {
  description = "Map of network interface ID lists for each Interface endpoint."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.network_interface_ids }
}

output "interface_endpoint_states" {
  description = "Map of current state for each Interface endpoint (e.g. 'available', 'pending')."
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.state }
}

# ─────────────────────────────────────────────────────────────────────────────
# Gateway endpoints
# ─────────────────────────────────────────────────────────────────────────────

output "gateway_endpoints" {
  description = "Map of Gateway VPC endpoint objects keyed by logical name."
  value       = aws_vpc_endpoint.gateway
}

output "gateway_endpoint_ids" {
  description = "Map of Gateway endpoint IDs keyed by logical name."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.id }
}

output "gateway_endpoint_arns" {
  description = "Map of Gateway endpoint ARNs keyed by logical name."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.arn }
}

output "gateway_endpoint_prefix_list_ids" {
  description = "Map of prefix list IDs for each Gateway endpoint. Use these in security group rules."
  value       = { for k, v in aws_vpc_endpoint.gateway : k => v.prefix_list_id }
}

# ─────────────────────────────────────────────────────────────────────────────
# GatewayLoadBalancer endpoints
# ─────────────────────────────────────────────────────────────────────────────

output "gwlb_endpoints" {
  description = "Map of GatewayLoadBalancer VPC endpoint objects keyed by logical name."
  value       = aws_vpc_endpoint.gwlb
}

output "gwlb_endpoint_ids" {
  description = "Map of GatewayLoadBalancer endpoint IDs keyed by logical name."
  value       = { for k, v in aws_vpc_endpoint.gwlb : k => v.id }
}

# ─────────────────────────────────────────────────────────────────────────────
# Convenience helpers
# ─────────────────────────────────────────────────────────────────────────────

output "all_endpoint_ids" {
  description = "Flat map of every endpoint ID regardless of type."
  value = merge(
    { for k, v in aws_vpc_endpoint.interface : k => v.id },
    { for k, v in aws_vpc_endpoint.gateway : k => v.id },
    { for k, v in aws_vpc_endpoint.gwlb : k => v.id },
  )
}

output "s3_prefix_list_id" {
  description = "Prefix list ID for the S3 Gateway endpoint, if one was provisioned with the key 's3'. Useful for building security group egress rules."
  value       = try(aws_vpc_endpoint.gateway["s3"].prefix_list_id, null)
}

output "dynamodb_prefix_list_id" {
  description = "Prefix list ID for the DynamoDB Gateway endpoint, if one was provisioned with the key 'dynamodb'."
  value       = try(aws_vpc_endpoint.gateway["dynamodb"].prefix_list_id, null)
}
