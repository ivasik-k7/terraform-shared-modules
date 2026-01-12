
data "aws_region" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_vpc" "existing" {
  count = local.using_existing_vpc ? 1 : 0
  id    = var.vpc_id
}

data "aws_subnet" "existing_public" {
  count = local.using_existing_vpc && length(var.public_subnet_ids) > 0 ? length(var.public_subnet_ids) : 0
  id    = var.public_subnet_ids[count.index]
}

data "aws_subnet" "existing_private" {
  count = local.using_existing_vpc && length(var.private_subnet_ids) > 0 ? length(var.private_subnet_ids) : 0
  id    = var.private_subnet_ids[count.index]
}

data "aws_subnet" "existing_database" {
  count = local.using_existing_vpc && length(var.database_subnet_ids) > 0 ? length(var.database_subnet_ids) : 0
  id    = var.database_subnet_ids[count.index]
}

data "aws_security_group" "default" {
  count  = local.using_existing_vpc ? 1 : 0
  vpc_id = local.vpc_id
  name   = "default"
}

data "aws_network_acls" "default" {
  count  = local.using_existing_vpc ? 1 : 0
  vpc_id = local.vpc_id

  filter {
    name   = "default"
    values = ["true"]
  }
}
