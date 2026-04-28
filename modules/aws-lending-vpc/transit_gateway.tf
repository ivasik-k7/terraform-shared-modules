# =============================================================================
# Transit Gateway VPC attachment
# =============================================================================
# The attachment lives in the transit subnets when they exist (best practice
# for hybrid: dedicated tier keeps the ENIs isolated). When the caller didn't
# create transit subnets, the module falls back to private subnets so the
# simple case still works without surprises.
#
# IMPORTANT REMINDERS:
# - The attachment subnets you pick determine which AZs the TGW serves
#   traffic from. Cross-AZ TGW data transfer is also charged. Match the
#   AZ count to your subnet layout.
# - This module handles the VPC-side route-table routes. PROPAGATION at the
#   TGW route table itself is a separate object owned by whoever runs the
#   TGW. Plan that side too — otherwise this VPC happily ships traffic at
#   the TGW only for the TGW to drop it.
# - appliance_mode_support = enable is for VPCs hosting a stateful firewall
#   appliance. It pins forward + return paths to the same AZ, which the
#   firewall needs to keep flow state. Don't enable for normal workload VPCs.
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

# Routes pointing AT the TGW from VPC route tables. Without depends_on the
# first apply can race: aws_route resolves before the attachment is active
# and AWS rejects the route.
#
# Blackhole semantics live at the TGW route table, not here. If you want a
# specific VPC tier to refuse a CIDR, use a NACL or just don't add the
# route — the absence of a TGW route is the blackhole at the VPC level.
resource "aws_route" "transit_gateway" {
  for_each = local.transit_gateway_routes_expanded

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination_cidr_block
  transit_gateway_id     = var.transit_gateway_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.this]
}
