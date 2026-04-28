locals {
  # ===========================================================================
  # VPC lifecycle flags. Exactly one of these is true; the check{} block in
  # vpc.tf rejects "neither" at plan time.
  # ===========================================================================
  using_existing_vpc = var.vpc_id != null
  should_create_vpc  = !local.using_existing_vpc && var.create_vpc

  # Effective VPC id, regardless of which mode we're in.
  vpc_id = local.using_existing_vpc ? var.vpc_id : (
    local.should_create_vpc ? aws_vpc.this[0].id : null
  )

  # Effective VPC CIDR. Used for default endpoint SG, inter-tier rules, etc.
  vpc_cidr_block = local.using_existing_vpc ? data.aws_vpc.existing[0].cidr_block : (
    local.should_create_vpc ? aws_vpc.this[0].cidr_block : null
  )

  # ===========================================================================
  # Availability zones
  # ===========================================================================
  # Caller-provided list wins. Otherwise pick the first N available AZs in
  # the region (N = az_count). Sorted to keep results stable across runs;
  # AWS sometimes returns AZs in a non-deterministic order.
  azs = length(var.availability_zones) > 0 ? var.availability_zones : slice(
    sort(data.aws_availability_zones.available.names),
    0,
    min(var.az_count, length(data.aws_availability_zones.available.names))
  )

  # ===========================================================================
  # Tag baseline
  # ===========================================================================
  # Order matters: caller tags first, then module-owned keys override. So
  # things like Name and ManagedBy stay trustworthy even if a caller tries
  # to set them.
  base_tags = merge(var.tags, {
    Environment = var.environment
    Name        = var.name
    ManagedBy   = "Terraform"
    Module      = "aws-lending-vpc"
  })

  # FinOps tag enforcement. Plan-time check in vpc.tf reads this.
  finops_required_tags = ["Project", "Team", "CostCenter", "Owner"]
  finops_missing_tags  = [for t in local.finops_required_tags : t if !contains(keys(var.tags), t)]

  # ===========================================================================
  # Subnet CIDRs (auto-carve mode)
  # ===========================================================================
  # When auto_carve_subnets = true the module slices the VPC CIDR into 5
  # tiers using cidrsubnet(). Layout for a /16 + subnet_newbits=4:
  #   public    -> /20 starting at offset 0   (10.0.0.0/20  ... up to 3 AZs)
  #   private   -> /20 starting at offset 4   (10.0.64.0/20 ...)
  #   database  -> /20 starting at offset 8   (10.0.128.0/20 ...)
  #   intra     -> /20 starting at offset 12  (10.0.192.0/20 ...)
  #   transit   -> /28 starting at offset (varies; see below)
  #
  # Transit uses a much smaller mask because TGW attachments need only a few
  # IPs. We park it in the last /20 of the VPC and slice that into /28s.
  auto_carve = local.should_create_vpc && var.auto_carve_subnets

  # Number of AZs we're carving for. Capped at 4 in auto-carve mode because
  # subnet_newbits=4 only gives us 16 slots and we want 4 tiers + room.
  carve_az_count = min(length(local.azs), 4)

  carved_public_subnets = local.auto_carve ? [
    for i in range(local.carve_az_count) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, i)
  ] : []

  carved_private_subnets = local.auto_carve ? [
    for i in range(local.carve_az_count) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, i + 4)
  ] : []

  carved_database_subnets = local.auto_carve ? [
    for i in range(local.carve_az_count) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, i + 8)
  ] : []

  carved_intra_subnets = local.auto_carve ? [
    for i in range(local.carve_az_count) : cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, i + 12)
  ] : []

  # Transit: take the last /20 of the VPC (offset 15) and carve /28s from it.
  # 12 newbits added on top of subnet_newbits (4) ends up at /28 for a /16 VPC.
  carved_transit_block = local.auto_carve ? cidrsubnet(var.vpc_cidr_block, var.subnet_newbits, 15) : null
  carved_transit_subnets = local.auto_carve ? [
    for i in range(local.carve_az_count) : cidrsubnet(local.carved_transit_block, var.transit_subnet_newbits - var.subnet_newbits, i)
  ] : []

  # Effective per-tier CIDR lists. Carved values when auto-carve, else what
  # the caller passed in.
  effective_public_subnets   = local.auto_carve ? local.carved_public_subnets : var.public_subnets
  effective_private_subnets  = local.auto_carve ? local.carved_private_subnets : var.private_subnets
  effective_database_subnets = local.auto_carve ? local.carved_database_subnets : var.database_subnets
  effective_intra_subnets    = local.auto_carve ? local.carved_intra_subnets : var.intra_subnets
  effective_transit_subnets  = local.auto_carve ? local.carved_transit_subnets : var.transit_subnets

  # ===========================================================================
  # Subnet counts and sanity checks
  # ===========================================================================
  public_subnet_count   = length(local.effective_public_subnets)
  private_subnet_count  = length(local.effective_private_subnets)
  database_subnet_count = length(local.effective_database_subnets)
  intra_subnet_count    = length(local.effective_intra_subnets)
  transit_subnet_count  = length(local.effective_transit_subnets)

  # Each tier must be empty OR exactly one CIDR per AZ. The check{} block in
  # vpc.tf runs these.
  subnet_validation = {
    public   = local.public_subnet_count == 0 || local.public_subnet_count == length(local.azs)
    private  = local.private_subnet_count == 0 || local.private_subnet_count == length(local.azs)
    database = local.database_subnet_count == 0 || local.database_subnet_count == length(local.azs)
    intra    = local.intra_subnet_count == 0 || local.intra_subnet_count == length(local.azs)
    transit  = local.transit_subnet_count == 0 || local.transit_subnet_count == length(local.azs)
  }

  # ===========================================================================
  # NAT gateway layout
  # ===========================================================================
  nat_gateway_count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : (
      var.one_nat_gateway_per_az ? length(local.azs) : min(local.public_subnet_count, length(local.azs))
    )
  ) : 0

  # Which AZ each NAT lands in. Used in the Name tag.
  nat_gateway_azs = var.single_nat_gateway ? [local.azs[0]] : slice(local.azs, 0, local.nat_gateway_count)

  # Subnet ids hosting the NAT ENIs. Caller can override; otherwise pick from
  # the public subnets (created here or passed in).
  nat_gateway_subnet_ids = length(var.nat_gateway_subnet_ids) > 0 ? var.nat_gateway_subnet_ids : (
    local.using_existing_vpc
    ? slice(var.public_subnet_ids, 0, min(local.nat_gateway_count, length(var.public_subnet_ids)))
    : (length(aws_subnet.public) > 0 ? slice(aws_subnet.public[*].id, 0, local.nat_gateway_count) : [])
  )

  # ===========================================================================
  # Internet gateway id (created or adopted)
  # ===========================================================================
  internet_gateway_id = var.internet_gateway_id != null ? var.internet_gateway_id : (
    length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
  )

  # ===========================================================================
  # Effective subnet id lists per tier (created or adopted)
  # ===========================================================================
  public_subnet_ids_effective   = local.using_existing_vpc ? var.public_subnet_ids : aws_subnet.public[*].id
  private_subnet_ids_effective  = local.using_existing_vpc ? var.private_subnet_ids : aws_subnet.private[*].id
  database_subnet_ids_effective = local.using_existing_vpc ? var.database_subnet_ids : aws_subnet.database[*].id
  intra_subnet_ids_effective    = local.using_existing_vpc ? var.intra_subnet_ids : aws_subnet.intra[*].id
  transit_subnet_ids_effective  = local.using_existing_vpc ? var.transit_subnet_ids : aws_subnet.transit[*].id

  # subnets_by_az: a map keyed by AZ, with per-tier ids inside. Lets downstream
  # callers do module.vpc.subnets_by_az["eu-west-1a"].private without index math.
  subnets_by_az = {
    for i, az in local.azs : az => {
      public   = i < local.public_subnet_count ? local.public_subnet_ids_effective[i] : null
      private  = i < local.private_subnet_count ? local.private_subnet_ids_effective[i] : null
      database = i < local.database_subnet_count ? local.database_subnet_ids_effective[i] : null
      intra    = i < local.intra_subnet_count ? local.intra_subnet_ids_effective[i] : null
      transit  = i < local.transit_subnet_count ? local.transit_subnet_ids_effective[i] : null
    }
  }

  # ===========================================================================
  # TGW attachment subnets — preference order
  # ===========================================================================
  #   1. Explicit override
  #   2. Transit tier (best practice)
  #   3. Private tier (fallback so simple setups still work)
  transit_gateway_attachment_subnets = (
    var.transit_gateway_attachment_subnet_ids != null ? var.transit_gateway_attachment_subnet_ids :
    length(local.transit_subnet_ids_effective) > 0 ? local.transit_subnet_ids_effective :
    local.private_subnet_ids_effective
  )

  # Flatten transit_gateway_routes into one entry per (route_table, destination)
  # pair, since aws_route is a single-route resource.
  transit_gateway_routes_expanded = var.transit_gateway_id == null ? {} : merge([
    for r in var.transit_gateway_routes : {
      for rt in r.route_table_ids :
      "${rt}:${r.destination_cidr_block}" => {
        route_table_id         = rt
        destination_cidr_block = r.destination_cidr_block
      }
    }
  ]...)

  # ===========================================================================
  # VPC endpoints
  # ===========================================================================
  # Region-prefix helper. Short names ("ssm") get prefixed; full names
  # ("com.amazonaws.eu-west-1.ssm") pass through.
  region_prefix = "com.amazonaws.${data.aws_region.current.name}"

  endpoint_service_full = {
    for short, full in {
      # Common interface endpoints. Extend this map as new services come up.
      ssm               = "${local.region_prefix}.ssm"
      ssmmessages       = "${local.region_prefix}.ssmmessages"
      ec2               = "${local.region_prefix}.ec2"
      ec2messages       = "${local.region_prefix}.ec2messages"
      kms               = "${local.region_prefix}.kms"
      logs              = "${local.region_prefix}.logs"
      monitoring        = "${local.region_prefix}.monitoring"
      sts               = "${local.region_prefix}.sts"
      secretsmanager    = "${local.region_prefix}.secretsmanager"
      sns               = "${local.region_prefix}.sns"
      sqs               = "${local.region_prefix}.sqs"
      "ecr.api"         = "${local.region_prefix}.ecr.api"
      "ecr.dkr"         = "${local.region_prefix}.ecr.dkr"
      ecs               = "${local.region_prefix}.ecs"
      "ecs-agent"       = "${local.region_prefix}.ecs-agent"
      "ecs-telemetry"   = "${local.region_prefix}.ecs-telemetry"
      eks               = "${local.region_prefix}.eks"
      elasticfilesystem = "${local.region_prefix}.elasticfilesystem"
      events            = "${local.region_prefix}.events"
      lambda            = "${local.region_prefix}.lambda"
      states            = "${local.region_prefix}.states"
      bedrock           = "${local.region_prefix}.bedrock"
      "bedrock-runtime" = "${local.region_prefix}.bedrock-runtime"
      s3                = "${local.region_prefix}.s3"
      dynamodb          = "${local.region_prefix}.dynamodb"
    } : short => full
  }

  # Resolve a service_name input: either a short alias from the table above,
  # or pass-through if it's already in the long form (starts with com.).
  resolve_service_name = {
    for k, v in merge(
      { for k, ep in var.vpc_endpoints : k => ep.service_name },
      { for k, ep in var.gateway_vpc_endpoints : k => ep.service_name },
    ) : k => startswith(v, "com.amazonaws.") ? v : lookup(local.endpoint_service_full, v, "${local.region_prefix}.${v}")
  }

  # Build the effective interface endpoint set: explicit map merged with the
  # shorthand list (interface_endpoint_services). Shorthand entries use module
  # defaults: intra subnets, module SG, private DNS on.
  preset_interface_endpoints = {
    for s in var.interface_endpoint_services : s => {
      service_name        = lookup(local.endpoint_service_full, s, "${local.region_prefix}.${s}")
      private_dns_enabled = true
      security_group_ids  = []
      subnet_ids          = []
      policy              = null
      tags                = {}
    }
  }

  preset_gateway_endpoints = {
    for s in var.gateway_endpoint_services : s => {
      service_name    = lookup(local.endpoint_service_full, s, "${local.region_prefix}.${s}")
      route_table_ids = []
      policy          = null
      tags            = {}
    }
  }

  # Merged. Explicit var.vpc_endpoints wins over the preset for the same key,
  # since the merge order makes the latter override.
  effective_interface_endpoints = merge(local.preset_interface_endpoints, {
    for k, ep in var.vpc_endpoints : k => {
      service_name        = startswith(ep.service_name, "com.amazonaws.") ? ep.service_name : lookup(local.endpoint_service_full, ep.service_name, "${local.region_prefix}.${ep.service_name}")
      private_dns_enabled = ep.private_dns_enabled
      security_group_ids  = ep.security_group_ids
      subnet_ids          = ep.subnet_ids
      policy              = ep.policy
      tags                = ep.tags
    }
  })

  effective_gateway_endpoints = merge(local.preset_gateway_endpoints, {
    for k, ep in var.gateway_vpc_endpoints : k => {
      service_name    = startswith(ep.service_name, "com.amazonaws.") ? ep.service_name : lookup(local.endpoint_service_full, ep.service_name, "${local.region_prefix}.${ep.service_name}")
      route_table_ids = ep.route_table_ids
      policy          = ep.policy
      tags            = ep.tags
    }
  })

  # Default subnet ids for endpoints (intra preferred, fall back to private).
  default_endpoint_subnet_ids = length(local.intra_subnet_ids_effective) > 0 ? local.intra_subnet_ids_effective : local.private_subnet_ids_effective

  # Default route tables that gateway endpoints attach to (private + intra).
  default_gateway_endpoint_route_tables = compact(concat(
    aws_route_table.private[*].id,
    length(aws_route_table.intra) > 0 ? [aws_route_table.intra[0].id] : [],
  ))

  # Whether a default endpoint SG should exist. Only when interface endpoints
  # are present and at least one of them needs a fallback SG.
  needs_default_endpoint_sg = var.create_endpoint_security_group && length(local.effective_interface_endpoints) > 0 && anytrue([
    for ep in values(local.effective_interface_endpoints) : length(ep.security_group_ids) == 0
  ])

  default_endpoint_security_group_id = local.needs_default_endpoint_sg ? aws_security_group.endpoints[0].id : null

  # ===========================================================================
  # DNS resolver: pick subnets if the caller didn't
  # ===========================================================================
  effective_dns_resolver_subnet_ids = length(var.dns_resolver_subnet_ids) > 0 ? var.dns_resolver_subnet_ids : (
    length(local.intra_subnet_ids_effective) >= 2 ? slice(local.intra_subnet_ids_effective, 0, 2) :
    length(local.private_subnet_ids_effective) >= 2 ? slice(local.private_subnet_ids_effective, 0, 2) :
    []
  )

  dns_resolver_security_group_ids = length(var.dns_resolver_security_group_ids) > 0 ? var.dns_resolver_security_group_ids : (
    var.enable_dns_resolver_endpoints ? [aws_security_group.dns_resolver[0].id] : []
  )
}
