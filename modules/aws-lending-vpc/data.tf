# Region + AZ lookups. Used to:
#   - default the AZ list when the caller doesn't pass one
#   - build region-prefixed VPC endpoint service names ("ssm" -> "com.amazonaws.eu-west-1.ssm")
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Reads attributes (CIDR, ARN, ...) from a VPC the caller adopted, so outputs
# stay symmetric with the create_vpc path.
data "aws_vpc" "existing" {
  count = local.using_existing_vpc ? 1 : 0
  id    = var.vpc_id
}

# Per-tier subnet lookups so we can echo CIDRs back as outputs even when the
# subnets were not created here. Looking them up one-by-one is cheap and
# avoids the "tags filter" foot-gun (subnets without the right tag silently
# disappear from the result).
data "aws_subnet" "existing_public" {
  count = local.using_existing_vpc ? length(var.public_subnet_ids) : 0
  id    = var.public_subnet_ids[count.index]
}

data "aws_subnet" "existing_private" {
  count = local.using_existing_vpc ? length(var.private_subnet_ids) : 0
  id    = var.private_subnet_ids[count.index]
}

data "aws_subnet" "existing_database" {
  count = local.using_existing_vpc ? length(var.database_subnet_ids) : 0
  id    = var.database_subnet_ids[count.index]
}

data "aws_subnet" "existing_intra" {
  count = local.using_existing_vpc ? length(var.intra_subnet_ids) : 0
  id    = var.intra_subnet_ids[count.index]
}

data "aws_subnet" "existing_transit" {
  count = local.using_existing_vpc ? length(var.transit_subnet_ids) : 0
  id    = var.transit_subnet_ids[count.index]
}

# Default NACL for an adopted VPC. We need the id explicitly because
# aws_default_network_acl wants it as input.
data "aws_network_acls" "default" {
  count  = local.using_existing_vpc && var.manage_default_network_acl ? 1 : 0
  vpc_id = local.vpc_id

  filter {
    name   = "default"
    values = ["true"]
  }
}
