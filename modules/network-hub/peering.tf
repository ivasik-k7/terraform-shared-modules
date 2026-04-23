# Peering connections keyed by a short name.
#
# For accepter-side resources (the peer VPC accepting this request), manage
# them in the peer's Terraform. auto_accept works only for same-account,
# same-region peerings.
resource "aws_vpc_peering_connection" "this" {
  for_each = var.vpc_peerings

  peer_vpc_id   = each.value.peer_vpc_id
  peer_owner_id = each.value.peer_owner_id
  peer_region   = each.value.peer_region
  vpc_id        = local.vpc_id
  auto_accept   = each.value.auto_accept

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-peer-${each.key}"
  })
}

# One route per (peering, route table). The caller lists the route tables
# that should learn about the peer's CIDR.
resource "aws_route" "peering" {
  for_each = merge([
    for k, v in var.vpc_peerings : {
      for rt in v.route_table_ids :
      "${k}:${rt}" => {
        key            = k
        route_table_id = rt
        peer_cidr      = v.peer_vpc_cidr
      } if v.peer_vpc_cidr != null && length(v.route_table_ids) > 0
    }
  ]...)

  route_table_id            = each.value.route_table_id
  destination_cidr_block    = each.value.peer_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.value.key].id
}
