# Created only when the module is building the VPC and the caller hasn't
# supplied an existing IGW id.
resource "aws_internet_gateway" "this" {
  count = local.should_create_vpc && var.create_internet_gateway && var.internet_gateway_id == null ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.internet_gateway_tags, {
    Name = "${var.name}-igw"
  })
}
