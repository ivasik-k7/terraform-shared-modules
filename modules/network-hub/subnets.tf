# All tiers are created only when the module is building a new VPC and
# create_subnets is true. Existing-VPC adoption passes subnet IDs in directly.
#
# Subnet count per tier equals the AZ list length (enforced by preconditions
# in vpc.tf). Index i always maps to AZ i, which keeps downstream route-table
# associations predictable.

# Public: reachable from the internet. Backs IGW-facing workloads and NAT
# gateways.
resource "aws_subnet" "public" {
  count = local.should_create_vpc && var.create_subnets ? local.public_subnet_count : 0

  vpc_id                  = aws_vpc.this[0].id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.base_tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

# Private: general-purpose workloads. Default route goes through NAT when
# enable_nat_gateway = true.
resource "aws_subnet" "private" {
  count = local.should_create_vpc && var.create_subnets ? local.private_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# Database: isolated subnets for RDS/ElastiCache. No default route out.
# Typically associated with an aws_db_subnet_group in the consumer module.
resource "aws_subnet" "database" {
  count = local.should_create_vpc && var.create_subnets ? local.database_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.database_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.database_subnet_tags, {
    Name = "${var.name}-database-${local.azs[count.index]}"
    Tier = "database"
  })
}

# Intra: internal-only traffic. Hosts things like VPC endpoint ENIs, EKS
# control-plane ENIs, and internal load balancers. No default route out.
resource "aws_subnet" "intra" {
  count = local.should_create_vpc && var.create_subnets ? local.intra_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.intra_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.intra_subnet_tags, {
    Name = "${var.name}-intra-${local.azs[count.index]}"
    Tier = "intra"
  })
}

# Transit: dedicated host subnets for the Transit Gateway / Cloud WAN
# attachment ENIs. Best practice for hybrid setups:
#   - Keep the attachment off workload subnets so on-prem routing decisions
#     aren't intermingled with workload traffic.
#   - /28 per AZ is enough (AWS reserves 5 IPs; a few more ENIs fit).
#   - No default route added by this module; TGW routing happens at the TGW
#     route table level.
resource "aws_subnet" "transit" {
  count = local.should_create_vpc && var.create_subnets ? local.transit_subnet_count : 0

  vpc_id            = aws_vpc.this[0].id
  cidr_block        = var.transit_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.transit_subnet_tags, {
    Name = "${var.name}-transit-${local.azs[count.index]}"
    Tier = "transit"
  })
}
