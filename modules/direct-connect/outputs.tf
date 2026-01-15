output "connection_id" {
  description = "ID of the Direct Connect connection"
  value       = try(aws_dx_connection.this[0].id, null)
}

output "connection_arn" {
  description = "ARN of the Direct Connect connection"
  value       = try(aws_dx_connection.this[0].arn, null)
}

output "connection_aws_device" {
  description = "Direct Connect endpoint on which the physical connection terminates"
  value       = try(aws_dx_connection.this[0].aws_device, null)
}

output "connection_jumbo_frame_capable" {
  description = "Whether jumbo frames (9001 MTU) are supported"
  value       = try(aws_dx_connection.this[0].jumbo_frame_capable, null)
}

output "connection_has_logical_redundancy" {
  description = "Whether the connection supports logical redundancy"
  value       = try(aws_dx_connection.this[0].has_logical_redundancy, null)
}

output "connection_macsec_capable" {
  description = "Whether the connection supports MACsec encryption"
  value       = try(aws_dx_connection.this[0].macsec_capable, null)
}

output "connection_port_encryption_status" {
  description = "Encryption status of the connection"
  value       = try(aws_dx_connection.this[0].port_encryption_status, null)
}

output "lag_id" {
  description = "ID of the Link Aggregation Group"
  value       = try(aws_dx_lag.this[0].id, null)
}

output "lag_arn" {
  description = "ARN of the Link Aggregation Group"
  value       = try(aws_dx_lag.this[0].arn, null)
}

output "lag_jumbo_frame_capable" {
  description = "Whether the LAG supports jumbo frames"
  value       = try(aws_dx_lag.this[0].jumbo_frame_capable, null)
}

output "lag_has_logical_redundancy" {
  description = "Whether the LAG has logical redundancy"
  value       = try(aws_dx_lag.this[0].has_logical_redundancy, null)
}

output "private_virtual_interface_ids" {
  description = "Map of private virtual interface IDs"
  value       = { for k, v in aws_dx_private_virtual_interface.this : k => v.id }
}

output "private_virtual_interface_arns" {
  description = "Map of private virtual interface ARNs"
  value       = { for k, v in aws_dx_private_virtual_interface.this : k => v.arn }
}

output "private_virtual_interface_aws_devices" {
  description = "Map of AWS devices for private virtual interfaces"
  value       = { for k, v in aws_dx_private_virtual_interface.this : k => v.aws_device }
}

output "private_virtual_interface_jumbo_frame_capable" {
  description = "Map of jumbo frame capability for private virtual interfaces"
  value       = { for k, v in aws_dx_private_virtual_interface.this : k => v.jumbo_frame_capable }
}

output "public_virtual_interface_ids" {
  description = "Map of public virtual interface IDs"
  value       = { for k, v in aws_dx_public_virtual_interface.this : k => v.id }
}

output "public_virtual_interface_arns" {
  description = "Map of public virtual interface ARNs"
  value       = { for k, v in aws_dx_public_virtual_interface.this : k => v.arn }
}

output "public_virtual_interface_aws_devices" {
  description = "Map of AWS devices for public virtual interfaces"
  value       = { for k, v in aws_dx_public_virtual_interface.this : k => v.aws_device }
}

output "transit_virtual_interface_ids" {
  description = "Map of transit virtual interface IDs"
  value       = { for k, v in aws_dx_transit_virtual_interface.this : k => v.id }
}

output "transit_virtual_interface_arns" {
  description = "Map of transit virtual interface ARNs"
  value       = { for k, v in aws_dx_transit_virtual_interface.this : k => v.arn }
}

output "transit_virtual_interface_aws_devices" {
  description = "Map of AWS devices for transit virtual interfaces"
  value       = { for k, v in aws_dx_transit_virtual_interface.this : k => v.aws_device }
}

output "transit_virtual_interface_jumbo_frame_capable" {
  description = "Map of jumbo frame capability for transit virtual interfaces"
  value       = { for k, v in aws_dx_transit_virtual_interface.this : k => v.jumbo_frame_capable }
}

output "dx_gateway_ids" {
  description = "Map of Direct Connect Gateway IDs"
  value       = { for k, v in aws_dx_gateway.this : k => v.id }
}

output "dx_gateway_owner_account_ids" {
  description = "Map of Direct Connect Gateway owner account IDs"
  value       = { for k, v in aws_dx_gateway.this : k => v.owner_account_id }
}

output "dx_gateway_association_ids" {
  description = "Map of Direct Connect Gateway association IDs"
  value       = { for k, v in aws_dx_gateway_association.this : k => v.id }
}

output "dx_gateway_association_gateway_ids" {
  description = "Map of associated gateway IDs"
  value       = { for k, v in aws_dx_gateway_association.this : k => v.associated_gateway_id }
}

output "dx_gateway_association_proposal_ids" {
  description = "Map of Direct Connect Gateway association proposal IDs"
  value       = { for k, v in aws_dx_gateway_association_proposal.this : k => v.id }
}

output "hosted_connection_ids" {
  description = "Map of hosted connection IDs"
  value       = { for k, v in aws_dx_hosted_connection.this : k => v.id }
}

output "hosted_connection_states" {
  description = "Map of hosted connection states"
  value       = { for k, v in aws_dx_hosted_connection.this : k => v.state }
}

output "hosted_connection_aws_devices" {
  description = "Map of AWS devices for hosted connections"
  value       = { for k, v in aws_dx_hosted_connection.this : k => v.aws_device }
}

output "bgp_peer_private_ids" {
  description = "Map of BGP peer IDs for private virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.private : k => v.id }
}

output "bgp_peer_private_statuses" {
  description = "Map of BGP peer statuses for private virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.private : k => v.bgp_status }
}

output "bgp_peer_public_ids" {
  description = "Map of BGP peer IDs for public virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.public : k => v.id }
}

output "bgp_peer_public_statuses" {
  description = "Map of BGP peer statuses for public virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.public : k => v.bgp_status }
}

output "bgp_peer_transit_ids" {
  description = "Map of BGP peer IDs for transit virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.transit : k => v.id }
}

output "bgp_peer_transit_statuses" {
  description = "Map of BGP peer statuses for transit virtual interfaces"
  value       = { for k, v in aws_dx_bgp_peer.transit : k => v.bgp_status }
}


output "macsec_key_ids" {
  description = "Map of MACsec key association IDs"
  value       = { for k, v in aws_dx_macsec_key_association.this : k => v.id }
}

output "macsec_key_statuses" {
  description = "Map of MACsec key association statuses"
  value       = { for k, v in aws_dx_macsec_key_association.this : k => v.state }
}

output "summary" {
  description = "Summary of created Direct Connect resources"
  value = {
    connection_created           = var.create_connection
    connection_id                = try(aws_dx_connection.this[0].id, var.existing_connection_id)
    lag_created                  = var.create_lag
    lag_id                       = try(aws_dx_lag.this[0].id, null)
    private_vif_count            = length(aws_dx_private_virtual_interface.this)
    public_vif_count             = length(aws_dx_public_virtual_interface.this)
    transit_vif_count            = length(aws_dx_transit_virtual_interface.this)
    dx_gateway_count             = length(aws_dx_gateway.this)
    dx_gateway_association_count = length(aws_dx_gateway_association.this)
    hosted_connection_count      = length(aws_dx_hosted_connection.this)
    macsec_enabled               = length(aws_dx_macsec_key_association.this) > 0
  }
}
