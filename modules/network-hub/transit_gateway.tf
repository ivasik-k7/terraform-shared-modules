# Transit Gateway attachment.
#
# The attachment lives in the transit subnets when they exist (best practice
# for hybrid/TGW-heavy setups: keeps TGW ENIs isolated from workloads). If
# the caller didn't create a transit tier, the module falls back to the
# private subnets so the attachment still works out of the box.
#
# transit_gateway_routes lets the caller install TGW routes on any number of
# route tables (typically the private + intra RTs, so on-prem CIDRs route
# through the TGW rather than the NAT).

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.transit_gateway_id != null ? 1 : 0

  transit_gateway_id = var.transit_gateway_id
  vpc_id             = local.vpc_id
  subnet_ids         = local.transit_gateway_attachment_subnets

  appliance_mode_support = var.transit_gateway_appliance_mode
  dns_support            = var.transit_gateway_dns_support
  ipv6_support           = var.transit_gateway_ipv6_support

  tags = merge(local.base_tags, var.transit_gateway_attachment_tags, {
    Name = "${var.name}-tgw-attachment"
  })
}

resource "aws_route" "transit_gateway" {
  for_each = local.transit_gateway_routes_expanded

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination_cidr_block
  transit_gateway_id     = var.transit_gateway_id

  # The attachment must be active before routes pointing at the TGW resolve
  # successfully, otherwise the first apply can race.
  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
