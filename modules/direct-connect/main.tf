# ============================================================================
# AWS Direct Connect Terraform Module
# ============================================================================
# This module provisions AWS Direct Connect resources including connections,
# LAGs, virtual interfaces (private, public, transit), and gateway associations.
# ============================================================================

# -----------------------------------------------------------------------------
# Direct Connect Connection
# -----------------------------------------------------------------------------
resource "aws_dx_connection" "this" {
  count = var.create_connection ? 1 : 0

  name            = var.connection_name
  bandwidth       = var.bandwidth
  location        = var.location
  provider_name   = var.provider_name
  request_macsec  = var.request_macsec
  skip_destroy    = var.skip_destroy
  encryption_mode = var.encryption_mode

  tags = merge(
    var.tags,
    var.connection_tags,
    {
      Name = var.connection_name
    }
  )
}

# -----------------------------------------------------------------------------
# Link Aggregation Group (LAG)
# -----------------------------------------------------------------------------
resource "aws_dx_lag" "this" {
  count = var.create_lag ? 1 : 0

  name                  = var.lag_name
  connections_bandwidth = var.lag_bandwidth
  location              = var.location
  provider_name         = var.provider_name
  force_destroy         = var.lag_force_destroy

  tags = merge(
    var.tags,
    var.lag_tags,
    {
      Name = var.lag_name
    }
  )
}

# Associate existing connections to LAG
resource "aws_dx_lag_association" "this" {
  for_each = var.lag_connection_associations

  connection_id = each.value
  lag_id        = aws_dx_lag.this[0].id
}

# -----------------------------------------------------------------------------
# Private Virtual Interface
# -----------------------------------------------------------------------------
resource "aws_dx_private_virtual_interface" "this" {
  for_each = var.private_virtual_interfaces

  connection_id    = var.use_lag ? aws_dx_lag.this[0].id : (var.create_connection ? aws_dx_connection.this[0].id : var.existing_connection_id)
  name             = each.value.name
  vlan             = each.value.vlan
  address_family   = lookup(each.value, "address_family", "ipv4")
  bgp_asn          = each.value.bgp_asn
  amazon_address   = lookup(each.value, "amazon_address", null)
  customer_address = lookup(each.value, "customer_address", null)
  bgp_auth_key     = lookup(each.value, "bgp_auth_key", null)
  dx_gateway_id    = lookup(each.value, "dx_gateway_id", null)
  vpn_gateway_id   = lookup(each.value, "vpn_gateway_id", null)
  mtu              = lookup(each.value, "mtu", 1500)
  sitelink_enabled = lookup(each.value, "sitelink_enabled", false)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.name
    }
  )
}

# -----------------------------------------------------------------------------
# Public Virtual Interface
# -----------------------------------------------------------------------------
resource "aws_dx_public_virtual_interface" "this" {
  for_each = var.public_virtual_interfaces

  connection_id         = var.use_lag ? aws_dx_lag.this[0].id : (var.create_connection ? aws_dx_connection.this[0].id : var.existing_connection_id)
  name                  = each.value.name
  vlan                  = each.value.vlan
  address_family        = lookup(each.value, "address_family", "ipv4")
  bgp_asn               = each.value.bgp_asn
  amazon_address        = each.value.amazon_address
  customer_address      = each.value.customer_address
  bgp_auth_key          = lookup(each.value, "bgp_auth_key", null)
  route_filter_prefixes = each.value.route_filter_prefixes

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.name
    }
  )
}

# -----------------------------------------------------------------------------
# Transit Virtual Interface
# -----------------------------------------------------------------------------
resource "aws_dx_transit_virtual_interface" "this" {
  for_each = var.transit_virtual_interfaces

  connection_id    = var.use_lag ? aws_dx_lag.this[0].id : (var.create_connection ? aws_dx_connection.this[0].id : var.existing_connection_id)
  name             = each.value.name
  vlan             = each.value.vlan
  address_family   = lookup(each.value, "address_family", "ipv4")
  bgp_asn          = each.value.bgp_asn
  dx_gateway_id    = each.value.dx_gateway_id
  amazon_address   = lookup(each.value, "amazon_address", null)
  customer_address = lookup(each.value, "customer_address", null)
  bgp_auth_key     = lookup(each.value, "bgp_auth_key", null)
  mtu              = lookup(each.value, "mtu", 1500)
  sitelink_enabled = lookup(each.value, "sitelink_enabled", false)

  tags = merge(
    var.tags,
    lookup(each.value, "tags", {}),
    {
      Name = each.value.name
    }
  )
}

# -----------------------------------------------------------------------------
# Direct Connect Gateway
# -----------------------------------------------------------------------------
resource "aws_dx_gateway" "this" {
  for_each = var.dx_gateways

  name            = each.value.name
  amazon_side_asn = each.value.amazon_side_asn

  timeouts {
    create = lookup(each.value, "timeout_create", "10m")
    delete = lookup(each.value, "timeout_delete", "10m")
  }
}

# -----------------------------------------------------------------------------
# Direct Connect Gateway Association
# -----------------------------------------------------------------------------
resource "aws_dx_gateway_association" "this" {
  for_each = var.dx_gateway_associations

  dx_gateway_id         = lookup(each.value, "dx_gateway_id", null) != null ? each.value.dx_gateway_id : aws_dx_gateway.this[each.value.dx_gateway_key].id
  associated_gateway_id = each.value.associated_gateway_id
  allowed_prefixes      = lookup(each.value, "allowed_prefixes", null)

  proposal_id = lookup(each.value, "proposal_id", null)

  timeouts {
    create = lookup(each.value, "timeout_create", "30m")
    update = lookup(each.value, "timeout_update", "30m")
    delete = lookup(each.value, "timeout_delete", "30m")
  }
}

# -----------------------------------------------------------------------------
# Direct Connect Gateway Association Proposal (for cross-account)
# -----------------------------------------------------------------------------
resource "aws_dx_gateway_association_proposal" "this" {
  for_each = var.dx_gateway_association_proposals

  dx_gateway_id               = lookup(each.value, "dx_gateway_id", null) != null ? each.value.dx_gateway_id : aws_dx_gateway.this[each.value.dx_gateway_key].id
  dx_gateway_owner_account_id = each.value.dx_gateway_owner_account_id
  associated_gateway_id       = each.value.associated_gateway_id
  allowed_prefixes            = lookup(each.value, "allowed_prefixes", null)
}

# -----------------------------------------------------------------------------
# Hosted Connection (if using AWS Partner)
# -----------------------------------------------------------------------------
resource "aws_dx_hosted_connection" "this" {
  for_each = var.hosted_connections

  owner_account_id = var.hosted_connection_owner_account_id

  connection_id = var.use_lag ? aws_dx_lag.this[0].id : (var.create_connection ? aws_dx_connection.this[0].id : var.existing_connection_id)
  name          = each.value.name
  bandwidth     = each.value.bandwidth
  vlan          = each.value.vlan
}

# -----------------------------------------------------------------------------
# Connection Confirmation (for hosted connections)
# -----------------------------------------------------------------------------
resource "aws_dx_connection_confirmation" "this" {
  for_each = var.connection_confirmations

  connection_id = aws_dx_hosted_connection.this[each.key].id
}

# -----------------------------------------------------------------------------
# BGP Peer (for redundancy configuration)
# -----------------------------------------------------------------------------
resource "aws_dx_bgp_peer" "private" {
  for_each = var.bgp_peers_private

  virtual_interface_id = aws_dx_private_virtual_interface.this[each.value.vif_key].id
  address_family       = lookup(each.value, "address_family", "ipv4")
  bgp_asn              = each.value.bgp_asn
  amazon_address       = lookup(each.value, "amazon_address", null)
  customer_address     = lookup(each.value, "customer_address", null)
  bgp_auth_key         = lookup(each.value, "bgp_auth_key", null)
}

resource "aws_dx_bgp_peer" "public" {
  for_each = var.bgp_peers_public

  virtual_interface_id = aws_dx_public_virtual_interface.this[each.value.vif_key].id
  address_family       = lookup(each.value, "address_family", "ipv4")
  bgp_asn              = each.value.bgp_asn
  amazon_address       = each.value.amazon_address
  customer_address     = each.value.customer_address
  bgp_auth_key         = lookup(each.value, "bgp_auth_key", null)
}

resource "aws_dx_bgp_peer" "transit" {
  for_each = var.bgp_peers_transit

  virtual_interface_id = aws_dx_transit_virtual_interface.this[each.value.vif_key].id
  address_family       = lookup(each.value, "address_family", "ipv4")
  bgp_asn              = each.value.bgp_asn
  amazon_address       = lookup(each.value, "amazon_address", null)
  customer_address     = lookup(each.value, "customer_address", null)
  bgp_auth_key         = lookup(each.value, "bgp_auth_key", null)
}

# -----------------------------------------------------------------------------
# MACsec Association (for MACsec encryption)
# -----------------------------------------------------------------------------
resource "aws_dx_macsec_key_association" "this" {
  for_each = var.macsec_keys

  connection_id = var.use_lag ? aws_dx_lag.this[0].id : (var.create_connection ? aws_dx_connection.this[0].id : var.existing_connection_id)

  secret_arn = lookup(each.value, "secret_arn", null)
  ckn        = lookup(each.value, "ckn", null)
  cak        = lookup(each.value, "cak", null)
}
