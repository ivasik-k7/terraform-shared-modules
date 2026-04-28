# Subnets are only created when:
#   - we're building the VPC ourselves AND
#   - var.create_subnets is true (default).
# Index i ALWAYS maps to AZ i so route-table associations stay predictable.
# count is fine here because the per-tier lists never reorder; they're
# CIDR-by-AZ and the AZ list is sorted upstream.

# Public: routed to the IGW. Hosts ALBs, bastions, NAT gateways. Anything
# you put here gets a public IP if map_public_ip_on_launch is true.
resource "aws_subnet" "public" {
  count = local.should_create_vpc && var.create_subnets ? local.public_subnet_count : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = local.effective_public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.base_tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

# Private: workloads. Default route hops to the NAT in the same AZ.
resource "aws_subnet" "private" {
  count = local.should_create_vpc && var.create_subnets ? local.private_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = local.effective_private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# Database: isolated. No default route — RDS doesn't need internet, and
# leaving a route off prevents accidental egress paths from the data tier.
resource "aws_subnet" "database" {
  count = local.should_create_vpc && var.create_subnets ? local.database_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = local.effective_database_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.database_subnet_tags, {
    Name = "${var.name}-database-${local.azs[count.index]}"
    Tier = "database"
  })
}

# Intra: internal-only. Hosts VPC endpoint ENIs, EKS control-plane ENIs,
# internal LBs. Nothing here ever needs internet.
resource "aws_subnet" "intra" {
  count = local.should_create_vpc && var.create_subnets ? local.intra_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = local.effective_intra_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.intra_subnet_tags, {
    Name = "${var.name}-intra-${local.azs[count.index]}"
    Tier = "intra"
  })
}

# Transit: dedicated host subnets for TGW / Cloud WAN attachment ENIs.
# AWS reserves 5 IPs per subnet, and the attachment uses 1 ENI per AZ, so a
# /28 (16 - 5 = 11 usable) is plenty.
#
# Why a separate tier? It keeps on-prem routing decisions out of workload
# RTs and lets you NACL the attachment surface tightly. Common gotcha if
# you skip this: every workload subnet ends up with TGW routes mixed in
# with the NAT default, and debugging asymmetric flows gets painful.
resource "aws_subnet" "transit" {
  count = local.should_create_vpc && var.create_subnets ? local.transit_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = local.effective_transit_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.transit_subnet_tags, {
    Name = "${var.name}-transit-${local.azs[count.index]}"
    Tier = "transit"
  })
}
