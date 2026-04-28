# Route-table layout, so it's obvious in one place:
#
#   public    1 shared RT, default route -> IGW
#   private   1 RT per AZ, default route -> NAT in same AZ (skippable)
#   database  1 shared RT, NO default route
#   intra     1 shared RT, NO default route
#   transit   1 shared RT, NO default route (TGW propagation lives at the
#             TGW route table, not on this VPC RT)
#
# Per-AZ private RTs are deliberate. Pointing all private subnets at one NAT
# means traffic from AZ-b/c crosses the AZ boundary to reach NAT in AZ-a,
# and AWS bills that data transfer at both ends. With per-AZ RTs and per-AZ
# NATs, traffic stays in-AZ and the bill stays sane.

# =============================================================================
# Public
# =============================================================================
resource "aws_route_table" "public" {
  count = (var.create_public_route_table && (
    (local.should_create_vpc && local.public_subnet_count > 0) ||
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

# =============================================================================
# Private
# =============================================================================
# One RT per AZ. Indexed by AZ position so [i] -> RT for AZ i; the NAT
# default route lookup later modulos against nat_gateway_count, which makes
# single_nat_gateway = true collapse all private RTs onto the one NAT.

resource "aws_route_table" "private" {
  count = var.create_private_route_tables ? (
    local.should_create_vpc ? length(aws_subnet.private) :
    local.using_existing_vpc ? length(var.private_subnet_ids) : 0
  ) : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.private_route_table_tags, {
    Name = "${var.name}-private-rt-${count.index < length(local.azs) ? local.azs[count.index] : count.index}"
    AZ   = count.index < length(local.azs) ? local.azs[count.index] : ""
  })
}

# 0.0.0.0/0 -> NAT default route. Skippable for "central egress" topologies
# where a TGW route handles outbound and you want a clean RT.
resource "aws_route" "private_nat_gateway" {
  count = var.create_private_route_tables && var.enable_nat_gateway && local.nat_gateway_count > 0 && !var.skip_private_nat_default_route ? length(aws_route_table.private) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  # modulo so single_nat_gateway = true sends every RT to the one NAT, while
  # one-per-AZ sends each RT to its same-AZ NAT.
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

# =============================================================================
# Database
# =============================================================================
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

# =============================================================================
# Intra
# =============================================================================
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

# =============================================================================
# Transit
# =============================================================================
# Stays empty by design. If you need to push something at the TGW from the
# transit subnets themselves (rare — usually hosts only the attachment ENI),
# add it via var.private_routes / var.public_routes targeting this RT id.

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

# =============================================================================
# Caller-supplied extra routes
# =============================================================================
# Generic on purpose: caller picks any route table they own (whether the
# module created it or not) and any single target field.
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
