# One EIP per NAT gateway, unless the caller supplies pre-allocated EIPs via
# nat_gateway_eip_ids. The count expression in aws_nat_gateway picks the
# supplied EIP first and falls back to this resource.
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? max(local.nat_gateway_count - length(var.nat_gateway_eip_ids), 0) : 0

  domain = "vpc"

  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-eip-${local.nat_gateway_azs[count.index + length(var.nat_gateway_eip_ids)]}"
  })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = count.index < length(var.nat_gateway_eip_ids) ? var.nat_gateway_eip_ids[count.index] : aws_eip.nat[count.index - length(var.nat_gateway_eip_ids)].id
  subnet_id     = local.nat_gateway_subnet_ids[count.index]

  # Explicit so plans show the field even though PUBLIC is the default.
  connectivity_type = "public"

  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-${local.nat_gateway_azs[count.index]}"
  })

  # NAT gateway provisioning fails until the IGW is in place when running on a
  # new VPC, so wait on it explicitly.
  depends_on = [aws_internet_gateway.this]
}
