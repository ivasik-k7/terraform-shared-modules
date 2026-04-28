# EIPs for NATs. Only allocate as many as we need beyond what the caller
# already supplied via nat_gateway_eip_ids. The aws_nat_gateway resource
# below stitches the two pools together by index.
resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? max(local.nat_gateway_count - length(var.nat_gateway_eip_ids), 0) : 0

  domain = "vpc"

  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-eip-${local.nat_gateway_azs[count.index + length(var.nat_gateway_eip_ids)]}"
  })

  # AWS occasionally issues an EIP whose IP collides with something on-prem
  # already firewalled out. If that happens, taint and re-apply rather than
  # patching the NAT gateway in place.
}

# Public NAT gateways. One per AZ by default — keeps NAT data transfer in-AZ
# and avoids the "billed twice for crossing AZ boundaries" charge that adds
# up fast at multi-PB migrations.
resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id     = count.index < length(var.nat_gateway_eip_ids) ? var.nat_gateway_eip_ids[count.index] : aws_eip.nat[count.index - length(var.nat_gateway_eip_ids)].id
  subnet_id         = local.nat_gateway_subnet_ids[count.index]
  connectivity_type = "public"

  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-${local.nat_gateway_azs[count.index]}"
  })

  # NAT gateway provisioning fails until the IGW is in place on a fresh VPC.
  # Without this depends_on, the first apply hits a race and you have to
  # re-run.
  depends_on = [aws_internet_gateway.this]
}
