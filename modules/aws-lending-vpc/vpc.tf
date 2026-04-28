# =============================================================================
# Plan-time preconditions
# =============================================================================
# check{} blocks fire at plan time. They don't create state and produce
# cleaner messages than the old null_resource trick. Keep module-wide
# preconditions here; per-resource ones live next to their resource.

check "module_inputs" {
  # Mode selection
  assert {
    condition     = local.should_create_vpc || local.using_existing_vpc
    error_message = "Set vpc_id to adopt an existing VPC, or create_vpc = true to make a new one. (You set neither.)"
  }

  # New VPC requires a CIDR
  assert {
    condition     = !local.should_create_vpc || var.vpc_cidr_block != null
    error_message = "vpc_cidr_block is required when create_vpc = true."
  }

  # auto-carve sanity: only valid when creating a VPC
  assert {
    condition     = !var.auto_carve_subnets || local.should_create_vpc
    error_message = "auto_carve_subnets only works when create_vpc = true (no source CIDR to slice when adopting)."
  }

  # Tier sizing: empty or one CIDR per AZ. Anything else is a typo and the
  # downstream count expressions get awkward.
  assert {
    condition     = local.subnet_validation.public
    error_message = "public_subnets must be empty or have exactly one CIDR per AZ (got ${local.public_subnet_count} for ${length(local.azs)} AZs)."
  }

  assert {
    condition     = local.subnet_validation.private
    error_message = "private_subnets must be empty or have exactly one CIDR per AZ (got ${local.private_subnet_count} for ${length(local.azs)} AZs)."
  }

  assert {
    condition     = local.subnet_validation.database
    error_message = "database_subnets must be empty or have exactly one CIDR per AZ (got ${local.database_subnet_count} for ${length(local.azs)} AZs)."
  }

  assert {
    condition     = local.subnet_validation.intra
    error_message = "intra_subnets must be empty or have exactly one CIDR per AZ (got ${local.intra_subnet_count} for ${length(local.azs)} AZs)."
  }

  assert {
    condition     = local.subnet_validation.transit
    error_message = "transit_subnets must be empty or have exactly one CIDR per AZ (got ${local.transit_subnet_count} for ${length(local.azs)} AZs)."
  }

  # NAT layout sanity: we must have at least as many NAT-host subnets as NATs
  # we're trying to create. Otherwise the count expression silently picks the
  # wrong subnet and the plan is confusing.
  assert {
    condition     = !var.enable_nat_gateway || local.nat_gateway_count == 0 || local.nat_gateway_count <= length(local.nat_gateway_subnet_ids)
    error_message = "Not enough public/host subnets for the requested NAT layout. Need ${local.nat_gateway_count}, have ${length(local.nat_gateway_subnet_ids)}."
  }

  # CW Logs flow log destination requires an IAM role; S3/Firehose don't.
  # Catching this at plan time is way friendlier than the AWS API error.
  assert {
    condition     = !var.enable_flow_logs || var.flow_log_destination_type != "cloud-watch-logs" || var.flow_log_iam_role_arn != null
    error_message = "flow_log_iam_role_arn is required when flow_log_destination_type = cloud-watch-logs."
  }

  assert {
    condition     = !var.enable_flow_logs || var.flow_log_destination_arn != null
    error_message = "flow_log_destination_arn is required when enable_flow_logs = true."
  }

  # TGW attachment: you need ENIs in at least 2 AZs for any kind of HA.
  assert {
    condition     = var.transit_gateway_id == null || length(distinct(local.transit_gateway_attachment_subnets)) >= 1
    error_message = "TGW attachment needs at least one subnet."
  }

  # DNS resolver: AWS requires the endpoint to span at least 2 AZs.
  assert {
    condition     = !var.enable_dns_resolver_endpoints || length(local.effective_dns_resolver_subnet_ids) >= 2
    error_message = "DNS resolver endpoints need at least 2 subnets in different AZs. None available - either pass dns_resolver_subnet_ids or create intra/private subnets."
  }

  # Inter-tier rules can only target SGs the module created.
  assert {
    condition     = alltrue([for r in var.inter_tier_rules : contains(keys(var.security_groups), r.from) && contains(keys(var.security_groups), r.to)])
    error_message = "inter_tier_rules.from and .to must be keys in var.security_groups."
  }

  # FinOps tags: optional but recommended. Loud failure when enforce is on.
  assert {
    condition     = !var.enforce_finops_tags || length(local.finops_missing_tags) == 0
    error_message = "Required FinOps tags missing from var.tags: ${join(", ", local.finops_missing_tags)}. Add them or set enforce_finops_tags = false."
  }

  # Endpoint subnet sanity: interface endpoints with an empty subnet list will
  # try to use the intra/private fallback, but if neither exists it fails.
  assert {
    condition = length(local.effective_interface_endpoints) == 0 || alltrue([
      for ep in values(local.effective_interface_endpoints) :
      length(ep.subnet_ids) > 0 || length(local.default_endpoint_subnet_ids) > 0
    ])
    error_message = "Interface endpoints requested but no subnet_ids supplied and no intra/private subnets to fall back to."
  }
}

# =============================================================================
# The VPC itself
# =============================================================================
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

# Secondary CIDRs. Common when a /16 wasn't enough after a few migration
# waves; AWS supports up to 5 CIDR blocks per VPC.
resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = local.should_create_vpc ? length(var.secondary_cidr_blocks) : 0

  vpc_id     = aws_vpc.this[0].id
  cidr_block = var.secondary_cidr_blocks[count.index]
}
