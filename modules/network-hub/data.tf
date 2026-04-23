data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

# Used to read CIDRs and other attributes from a VPC the caller passes in.
data "aws_vpc" "existing" {
  count = local.using_existing_vpc ? 1 : 0
  id    = var.vpc_id
}

# Per-tier subnet lookups, so outputs can expose CIDRs for adopted subnets too.
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

# Default NACL id, needed when adopting an existing VPC and the caller asks
# the module to manage the default NACL's rules.
data "aws_network_acls" "default" {
  count  = local.using_existing_vpc && var.manage_default_network_acl ? 1 : 0
  vpc_id = local.vpc_id

  filter {
    name   = "default"
    values = ["true"]
  }
}
