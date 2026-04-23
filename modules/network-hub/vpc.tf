# Input preconditions. Anchored on a local variable (has no side effects) so
# Terraform evaluates them at plan time without needing a null_resource.
# Anything that needs to validate against `var.*` lives here; per-resource
# preconditions live next to their resource.
check "inputs" {
  assert {
    condition     = local.should_create_vpc || local.using_existing_vpc
    error_message = "Set vpc_id to adopt an existing VPC, or set create_vpc = true to create one."
  }

  assert {
    condition     = !local.should_create_vpc || var.vpc_cidr_block != null
    error_message = "vpc_cidr_block is required when create_vpc = true."
  }

  assert {
    condition     = local.subnet_validation.public
    error_message = "public_subnets must be empty or one CIDR per AZ."
  }

  assert {
    condition     = local.subnet_validation.private
    error_message = "private_subnets must be empty or one CIDR per AZ."
  }

  assert {
    condition     = local.subnet_validation.database
    error_message = "database_subnets must be empty or one CIDR per AZ."
  }

  assert {
    condition     = local.subnet_validation.intra
    error_message = "intra_subnets must be empty or one CIDR per AZ."
  }

  assert {
    condition     = local.subnet_validation.transit
    error_message = "transit_subnets must be empty or one CIDR per AZ."
  }

  assert {
    condition     = !var.enable_nat_gateway || local.nat_gateway_count <= length(local.nat_gateway_subnet_ids) || local.nat_gateway_count == 0
    error_message = "Not enough public subnets for the requested NAT gateway layout."
  }
}

resource "aws_vpc" "this" {
  count = local.should_create_vpc ? 1 : 0

  cidr_block                           = var.vpc_cidr_block
  instance_tenancy                     = var.instance_tenancy
  enable_dns_support                   = var.enable_dns_support
  enable_dns_hostnames                 = var.enable_dns_hostnames
  enable_network_address_usage_metrics = var.enable_network_address_usage_metrics
  assign_generated_ipv6_cidr_block     = var.enable_ipv6

  tags = merge(local.base_tags, {
    Name = "${var.name}-vpc"
  })
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = local.should_create_vpc ? length(var.secondary_cidr_blocks) : 0

  vpc_id     = aws_vpc.this[0].id
  cidr_block = var.secondary_cidr_blocks[count.index]
}
