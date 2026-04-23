# Interface endpoints attach ENIs in the subnets you list. Typical placement
# is the intra subnets so the ENIs are reachable VPC-wide without leaving the
# private network.
resource "aws_vpc_endpoint" "interface" {
  for_each = var.vpc_endpoints

  vpc_id              = local.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = each.value.subnet_ids
  security_group_ids  = each.value.security_group_ids
  private_dns_enabled = each.value.private_dns_enabled
  policy              = each.value.policy

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })
}

# Gateway endpoints (S3, DynamoDB) attach to route tables, not subnets. Cost
# nothing and skip the NAT hop for S3/DDB traffic.
resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_vpc_endpoints

  vpc_id            = local.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = each.value.route_table_ids
  policy            = each.value.policy

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })
}
