locals {
  using_existing_vpc = var.vpc_id != null
  should_create_vpc  = !local.using_existing_vpc && var.create_vpc

  # Base tags
  base_tags = merge({
    Name        = var.name
    Environment = var.environment
    Module      = "network-hub"
    ManagedBy   = "Terraform"
  }, var.tags)

  # Determine AZs
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    min(3, length(data.aws_availability_zones.available.names))
  )

  vpc_id = local.using_existing_vpc ? var.vpc_id : (local.should_create_vpc ? aws_vpc.main[0].id : null)

  public_subnet_count   = length(var.public_subnets)
  private_subnet_count  = length(var.private_subnets)
  database_subnet_count = length(var.database_subnets)
  intra_subnet_count    = length(var.intra_subnets)

  generated_public_subnets = length(var.public_subnets) == 0 ? [
    for i in range(local.public_subnet_count) : cidrsubnet(var.vpc_cidr_block, 8, i + 1)
  ] : var.public_subnets

  generated_private_subnets = length(var.private_subnets) == 0 ? [
    for i in range(local.private_subnet_count) : cidrsubnet(var.vpc_cidr_block, 8, i + 11)
  ] : var.private_subnets

  generated_database_subnets = length(var.database_subnets) == 0 ? [
    for i in range(local.database_subnet_count) : cidrsubnet(var.vpc_cidr_block, 8, i + 21)
  ] : var.database_subnets

  generated_intra_subnets = length(var.intra_subnets) == 0 ? [
    for i in range(local.intra_subnet_count) : cidrsubnet(var.vpc_cidr_block, 8, i + 31)
  ] : var.intra_subnets

  nat_gateway_count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : (
      var.one_nat_gateway_per_az ? length(local.azs) : min(length(local.generated_public_subnets), length(local.azs))
    )
  ) : 0

  nat_gateway_azs = var.single_nat_gateway ? [local.azs[0]] : slice(local.azs, 0, local.nat_gateway_count)

  nat_gateway_subnet_ids = length(var.nat_gateway_subnet_ids) > 0 ? var.nat_gateway_subnet_ids : (
    local.using_existing_vpc ? slice(var.public_subnet_ids, 0, local.nat_gateway_count) : (
      length(aws_subnet.public) > 0 ? slice(aws_subnet.public[*].id, 0, local.nat_gateway_count) : []
    )
  )

  dns_resolver_security_group_ids = length(var.dns_resolver_security_group_ids) > 0 ? var.dns_resolver_security_group_ids : (
    var.enable_dns_resolver_endpoints ? [aws_security_group.dns_resolver[0].id] : []
  )

  subnet_validation = {
    public   = local.public_subnet_count == 0 || local.public_subnet_count == length(local.azs)
    private  = local.private_subnet_count == 0 || local.private_subnet_count == length(local.azs)
    database = local.database_subnet_count == 0 || local.database_subnet_count == length(local.azs)
    intra    = local.intra_subnet_count == 0 || local.intra_subnet_count == length(local.azs)
  }
}
