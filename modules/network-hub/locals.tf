locals {
  # VPC lifecycle flags. Exactly one of these two should be true.
  using_existing_vpc = var.vpc_id != null
  should_create_vpc  = !local.using_existing_vpc && var.create_vpc

  # Effective VPC id. Null when the caller sets neither vpc_id nor create_vpc =
  # true; the preconditions in vpc.tf reject that state explicitly.
  vpc_id = local.using_existing_vpc ? var.vpc_id : (
    local.should_create_vpc ? aws_vpc.this[0].id : null
  )

  # AZs: caller-provided list wins. Otherwise pull the first three available
  # in the region.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    data.aws_availability_zones.available.names,
    0,
    min(3, length(data.aws_availability_zones.available.names))
  )

  # Tag baseline. Caller tags win, then module-provenance keys override so the
  # Name/Environment/ManagedBy/Module values remain trustworthy.
  base_tags = merge(var.tags, {
    Environment = var.environment
    Name        = var.name
    ManagedBy   = "Terraform"
    Module      = "network-hub"
  })

  # Subnet counts per tier. Used for resource count + precondition checks.
  public_subnet_count   = length(var.public_subnets)
  private_subnet_count  = length(var.private_subnets)
  database_subnet_count = length(var.database_subnets)
  intra_subnet_count    = length(var.intra_subnets)
  transit_subnet_count  = length(var.transit_subnets)

  # Every subnet tier must either be empty or have exactly one entry per AZ.
  # Enforced by preconditions in vpc.tf.
  subnet_validation = {
    public   = local.public_subnet_count == 0 || local.public_subnet_count == length(local.azs)
    private  = local.private_subnet_count == 0 || local.private_subnet_count == length(local.azs)
    database = local.database_subnet_count == 0 || local.database_subnet_count == length(local.azs)
    intra    = local.intra_subnet_count == 0 || local.intra_subnet_count == length(local.azs)
    transit  = local.transit_subnet_count == 0 || local.transit_subnet_count == length(local.azs)
  }

  # NAT gateway layout.
  # - single_nat_gateway = true  => 1 NAT for the whole VPC (cheaper, no HA)
  # - one_nat_gateway_per_az     => one per AZ (default HA layout)
  # - otherwise uses however many public subnets are available
  nat_gateway_count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : (
      var.one_nat_gateway_per_az ? length(local.azs) : min(length(var.public_subnets), length(local.azs))
    )
  ) : 0

  nat_gateway_azs = var.single_nat_gateway ? [local.azs[0]] : slice(local.azs, 0, local.nat_gateway_count)

  # Which subnets host the NAT gateway ENIs. Callers can override; otherwise
  # we pick from the public subnets we created or the public_subnet_ids they
  # passed in for an existing VPC.
  nat_gateway_subnet_ids = length(var.nat_gateway_subnet_ids) > 0 ? var.nat_gateway_subnet_ids : (
    local.using_existing_vpc
    ? slice(var.public_subnet_ids, 0, min(local.nat_gateway_count, length(var.public_subnet_ids)))
    : (length(aws_subnet.public) > 0 ? slice(aws_subnet.public[*].id, 0, local.nat_gateway_count) : [])
  )

  # Internet gateway id, whether adopted or newly created.
  internet_gateway_id = var.internet_gateway_id != null ? var.internet_gateway_id : (
    length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
  )

  # Default SG for fallback rule targeting when managing the existing VPC's SG.
  dns_resolver_security_group_ids = length(var.dns_resolver_security_group_ids) > 0 ? var.dns_resolver_security_group_ids : (
    var.enable_dns_resolver_endpoints ? [aws_security_group.dns_resolver[0].id] : []
  )

  # TGW attachment subnets. Preference order:
  #   1. transit_gateway_attachment_subnet_ids (explicit override)
  #   2. transit subnets (dedicated tier, AWS best practice)
  #   3. private subnets (fallback, still works but less isolated)
  transit_gateway_attachment_subnets = (
    var.transit_gateway_attachment_subnet_ids != null ? var.transit_gateway_attachment_subnet_ids :
    local.transit_subnet_ids_effective != null && length(local.transit_subnet_ids_effective) > 0 ? local.transit_subnet_ids_effective :
    local.private_subnet_ids_effective
  )

  # Convenience: the set of subnet IDs the module is managing per tier,
  # whether created or passed through from the caller.
  public_subnet_ids_effective   = local.using_existing_vpc ? var.public_subnet_ids : aws_subnet.public[*].id
  private_subnet_ids_effective  = local.using_existing_vpc ? var.private_subnet_ids : aws_subnet.private[*].id
  database_subnet_ids_effective = local.using_existing_vpc ? var.database_subnet_ids : aws_subnet.database[*].id
  intra_subnet_ids_effective    = local.using_existing_vpc ? var.intra_subnet_ids : aws_subnet.intra[*].id
  transit_subnet_ids_effective  = local.using_existing_vpc ? var.transit_subnet_ids : aws_subnet.transit[*].id

  # Expand the compact transit_gateway_routes input into a flat list keyed by
  # (route_table_id, destination_cidr_block). The raw variable form is a list
  # of {destination, route_table_ids[]}; the resource needs one entry per
  # route table.
  transit_gateway_routes_expanded = var.transit_gateway_id == null ? {} : merge([
    for r in var.transit_gateway_routes : {
      for rt in r.route_table_ids :
      "${rt}:${r.destination_cidr_block}" => {
        route_table_id         = rt
        destination_cidr_block = r.destination_cidr_block
      }
    }
  ]...)
}
