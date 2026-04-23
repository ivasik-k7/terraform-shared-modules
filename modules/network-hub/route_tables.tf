# Route-table layout:
#   public    one shared route table (default route: IGW)
#   private   one per AZ              (default route: NAT in same AZ)
#   database  one shared route table (no default route; internal only)
#   intra     one shared route table (no default route; internal only)
#   transit   one shared route table (no default route; TGW-attachment ENIs only)
#
# Per-AZ private RTs are what let you drop a NAT in each AZ and avoid the
# cross-AZ data charge on the return path.

# Public

resource "aws_route_table" "public" {
  count = (var.create_public_route_table && (
    (local.should_create_vpc && length(aws_subnet.public) > 0) ||
    (local.using_existing_vpc && length(var.public_subnet_ids) > 0)
  )) ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.public_route_table_tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet_gateway" {
  count = length(aws_route_table.public) > 0 && local.internet_gateway_id != null ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.internet_gateway_id
}

resource "aws_route_table_association" "public_new" {
  count = local.should_create_vpc && length(aws_subnet.public) > 0 && length(aws_route_table.public) > 0 ? length(aws_subnet.public) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_existing" {
  count = local.using_existing_vpc && length(var.public_subnet_ids) > 0 && length(aws_route_table.public) > 0 ? length(var.public_subnet_ids) : 0

  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public[0].id
}

# Private: one route table per AZ. Indexed by AZ so the module can wire the
# NAT in the same AZ (avoids cross-AZ NAT charges on the return path).

resource "aws_route_table" "private" {
  count = var.create_private_route_tables ? (
    local.should_create_vpc ? length(aws_subnet.private) :
    local.using_existing_vpc ? length(var.private_subnet_ids) : 0
  ) : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.private_route_table_tags, {
    Name = "${var.name}-private-rt-${count.index}"
  })
}

resource "aws_route" "private_nat_gateway" {
  count = var.create_private_route_tables && var.enable_nat_gateway && local.nat_gateway_count > 0 ? length(aws_route_table.private) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  # When single_nat_gateway = true the modulo collapses every private RT onto
  # the one NAT. Otherwise it lines up per-AZ.
  nat_gateway_id = aws_nat_gateway.this[count.index % local.nat_gateway_count].id
}

resource "aws_route_table_association" "private_new" {
  count = local.should_create_vpc && length(aws_subnet.private) > 0 && length(aws_route_table.private) > 0 ? min(length(aws_subnet.private), length(aws_route_table.private)) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_existing" {
  count = local.using_existing_vpc && length(var.private_subnet_ids) > 0 && length(aws_route_table.private) > 0 ? min(length(var.private_subnet_ids), length(aws_route_table.private)) : 0

  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

# Database: one shared RT. No default route; add routes via var.private_routes
# or the caller's own resources.

resource "aws_route_table" "database" {
  count = var.create_database_route_table && (
    (local.should_create_vpc && length(aws_subnet.database) > 0) ||
    (local.using_existing_vpc && length(var.database_subnet_ids) > 0)
  ) ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.database_route_table_tags, {
    Name = "${var.name}-database-rt"
  })
}

resource "aws_route_table_association" "database_new" {
  count = local.should_create_vpc && length(aws_subnet.database) > 0 && length(aws_route_table.database) > 0 ? length(aws_subnet.database) : 0

  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database[0].id
}

resource "aws_route_table_association" "database_existing" {
  count = local.using_existing_vpc && length(var.database_subnet_ids) > 0 && length(aws_route_table.database) > 0 ? length(var.database_subnet_ids) : 0

  subnet_id      = var.database_subnet_ids[count.index]
  route_table_id = aws_route_table.database[0].id
}

# Intra

resource "aws_route_table" "intra" {
  count = var.create_intra_route_table && (
    (local.should_create_vpc && length(aws_subnet.intra) > 0) ||
    (local.using_existing_vpc && length(var.intra_subnet_ids) > 0)
  ) ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.intra_route_table_tags, {
    Name = "${var.name}-intra-rt"
  })
}

resource "aws_route_table_association" "intra_new" {
  count = local.should_create_vpc && length(aws_subnet.intra) > 0 && length(aws_route_table.intra) > 0 ? length(aws_subnet.intra) : 0

  subnet_id      = aws_subnet.intra[count.index].id
  route_table_id = aws_route_table.intra[0].id
}

resource "aws_route_table_association" "intra_existing" {
  count = local.using_existing_vpc && length(var.intra_subnet_ids) > 0 && length(aws_route_table.intra) > 0 ? length(var.intra_subnet_ids) : 0

  subnet_id      = var.intra_subnet_ids[count.index]
  route_table_id = aws_route_table.intra[0].id
}

# Transit: host-only subnets for TGW/Cloud WAN ENIs. No default route added;
# traffic destined for on-prem gets routed at the TGW route table level, not
# here.

resource "aws_route_table" "transit" {
  count = var.create_transit_route_table && (
    (local.should_create_vpc && length(aws_subnet.transit) > 0) ||
    (local.using_existing_vpc && length(var.transit_subnet_ids) > 0)
  ) ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.transit_route_table_tags, {
    Name = "${var.name}-transit-rt"
  })
}

resource "aws_route_table_association" "transit_new" {
  count = local.should_create_vpc && length(aws_subnet.transit) > 0 && length(aws_route_table.transit) > 0 ? length(aws_subnet.transit) : 0

  subnet_id      = aws_subnet.transit[count.index].id
  route_table_id = aws_route_table.transit[0].id
}

resource "aws_route_table_association" "transit_existing" {
  count = local.using_existing_vpc && length(var.transit_subnet_ids) > 0 && length(aws_route_table.transit) > 0 ? length(var.transit_subnet_ids) : 0

  subnet_id      = var.transit_subnet_ids[count.index]
  route_table_id = aws_route_table.transit[0].id
}

# Additional routes passed in by the caller. Kept generic so the caller can
# target any route table they own (not just the ones this module creates).

resource "aws_route" "public_additional" {
  for_each = { for i, r in var.public_routes : i => r }

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = each.value.destination_cidr_block
  destination_prefix_list_id = each.value.destination_prefix_list_id
  gateway_id                 = each.value.gateway_id
  nat_gateway_id             = each.value.nat_gateway_id
  vpc_endpoint_id            = each.value.vpc_endpoint_id
  transit_gateway_id         = each.value.transit_gateway_id
  vpc_peering_connection_id  = each.value.vpc_peering_connection_id
  egress_only_gateway_id     = each.value.egress_only_gateway_id
  carrier_gateway_id         = each.value.carrier_gateway_id
  network_interface_id       = each.value.network_interface_id
  local_gateway_id           = each.value.local_gateway_id
}

resource "aws_route" "private_additional" {
  for_each = { for i, r in var.private_routes : i => r }

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = each.value.destination_cidr_block
  destination_prefix_list_id = each.value.destination_prefix_list_id
  gateway_id                 = each.value.gateway_id
  nat_gateway_id             = each.value.nat_gateway_id
  vpc_endpoint_id            = each.value.vpc_endpoint_id
  transit_gateway_id         = each.value.transit_gateway_id
  vpc_peering_connection_id  = each.value.vpc_peering_connection_id
  egress_only_gateway_id     = each.value.egress_only_gateway_id
  carrier_gateway_id         = each.value.carrier_gateway_id
  network_interface_id       = each.value.network_interface_id
  local_gateway_id           = each.value.local_gateway_id
}
