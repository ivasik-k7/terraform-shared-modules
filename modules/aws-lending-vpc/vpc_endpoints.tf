# =============================================================================
# Default endpoint security group
# =============================================================================
# Most interface endpoints want exactly one rule: 443/tcp inbound from the
# VPC CIDR. Without an SG with that rule, the endpoint is unreachable and
# the failure mode looks like "AWS SDK timeouts" — pure pain to debug.
#
# This SG is auto-attached to any endpoint whose security_group_ids list is
# empty. Users with stricter requirements pass their own SG; otherwise this
# is the sane default.
resource "aws_security_group" "endpoints" {
  count = local.needs_default_endpoint_sg ? 1 : 0

  name        = "${var.name}-endpoints"
  description = "Default SG for interface VPC endpoints (${var.name}). 443/tcp from VPC + extra CIDRs."
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = compact(concat([local.vpc_cidr_block], var.endpoint_security_group_extra_cidrs))
  }

  egress {
    description = "All egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-endpoints"
  })

  lifecycle {
    create_before_destroy = true
  }
}

# =============================================================================
# Interface endpoints
# =============================================================================
# Service name is region-aware: short ("ssm") expands to
# "com.amazonaws.<region>.ssm" automatically, full names pass through.
# Subnet/SG defaults kick in when the caller leaves them empty.
#
# GOTCHA #1: private_dns_enabled requires enable_dns_support AND
# enable_dns_hostnames on the VPC. We default both to true.
#
# GOTCHA #2: enabling private DNS for the same service across two endpoints
# in the same VPC fails. AWS only allows one private-DNS-enabled endpoint
# per service per VPC. If you want a second endpoint (e.g. for a different
# SG), set private_dns_enabled = false on it.
resource "aws_vpc_endpoint" "interface" {
  for_each = local.effective_interface_endpoints

  vpc_id              = local.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : local.default_endpoint_subnet_ids
  security_group_ids  = length(each.value.security_group_ids) > 0 ? each.value.security_group_ids : compact([local.default_endpoint_security_group_id])
  private_dns_enabled = each.value.private_dns_enabled
  policy              = each.value.policy

  tags = merge(local.base_tags, each.value.tags, {
    Name    = "${var.name}-${each.key}"
    Service = each.value.service_name
  })
}

# =============================================================================
# Gateway endpoints (S3, DynamoDB)
# =============================================================================
# Gateway endpoints attach to ROUTE TABLES, not subnets, and they're free.
# Default behaviour: attach to every private + intra RT so workloads in
# those tiers skip the NAT for S3/DDB. Override via route_table_ids.
#
# GOTCHA: gateway endpoints add a more-specific route to the prefix list of
# the service. If you have a 0.0.0.0/0 route to NAT and a /16 prefix list
# route from the gateway endpoint, AWS prefers the more specific one, which
# is what we want — but if you also have a TGW route covering the same
# prefix list, the longest-prefix-match wins. Worth checking when debugging
# "S3 traffic is going through NAT instead of the endpoint".
resource "aws_vpc_endpoint" "gateway" {
  for_each = local.effective_gateway_endpoints

  vpc_id            = local.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = length(each.value.route_table_ids) > 0 ? each.value.route_table_ids : local.default_gateway_endpoint_route_tables
  policy            = each.value.policy

  tags = merge(local.base_tags, each.value.tags, {
    Name    = "${var.name}-${each.key}"
    Service = each.value.service_name
  })
}
