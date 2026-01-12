# ============================================================================
# Preconditions
# ============================================================================

resource "null_resource" "preconditions" {
  lifecycle {
    precondition {
      condition     = local.should_create_vpc || local.using_existing_vpc
      error_message = "Either provide an existing vpc_id or set create_vpc to true."
    }

    precondition {
      condition     = !local.should_create_vpc || var.vpc_cidr_block != null
      error_message = "vpc_cidr_block is required when creating a new VPC."
    }

    precondition {
      condition     = local.subnet_validation.public
      error_message = "Number of public subnets must be 0 or equal to number of availability zones."
    }

    precondition {
      condition     = local.subnet_validation.private
      error_message = "Number of private subnets must be 0 or equal to number of availability zones."
    }

    precondition {
      condition     = local.subnet_validation.database
      error_message = "Number of database subnets must be 0 or equal to number of availability zones."
    }

    precondition {
      condition     = local.subnet_validation.intra
      error_message = "Number of intra subnets must be 0 or equal to number of availability zones."
    }

    precondition {
      condition     = !var.enable_nat_gateway || local.nat_gateway_count <= length(local.nat_gateway_subnet_ids)
      error_message = "Not enough subnets available for NAT gateways. Need ${local.nat_gateway_count} but have ${length(local.nat_gateway_subnet_ids)}."
    }
  }
}

# ============================================================================
# VPC Resources
# ============================================================================

resource "aws_vpc" "main" {
  count = local.should_create_vpc ? 1 : 0

  cidr_block                           = var.vpc_cidr_block
  instance_tenancy                     = var.instance_tenancy
  enable_dns_support                   = var.enable_dns_support
  enable_dns_hostnames                 = var.enable_dns_hostnames
  enable_network_address_usage_metrics = var.enable_network_address_usage_metrics

  tags = merge(local.base_tags, {
    Name = "${var.name}-vpc"
  })

  lifecycle {
    ignore_changes = [ipv6_cidr_block]
  }
}

resource "aws_vpc_ipv4_cidr_block_association" "secondary" {
  count = local.should_create_vpc ? length(var.secondary_cidr_blocks) : 0

  vpc_id     = aws_vpc.main[0].id
  cidr_block = var.secondary_cidr_blocks[count.index]
}

resource "aws_vpc_ipv6_cidr_block_association" "ipv6" {
  count = local.should_create_vpc && var.enable_ipv6 ? 1 : 0

  vpc_id          = aws_vpc.main[0].id
  ipv6_cidr_block = "2001:db8::/56"
  ipv6_pool       = "amazon"
}

# ============================================================================
# Subnets (for new VPC)
# ============================================================================

resource "aws_subnet" "public" {
  count = local.should_create_vpc && var.create_subnets && local.public_subnet_count > 0 ? local.public_subnet_count : 0

  vpc_id                  = aws_vpc.main[0].id
  cidr_block              = local.generated_public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(local.base_tags, var.public_subnet_tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Type = "public"
  })
}

resource "aws_subnet" "private" {
  count = local.should_create_vpc && var.create_subnets && local.private_subnet_count > 0 ? local.private_subnet_count : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = local.generated_private_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.private_subnet_tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Type = "private"
  })
}

resource "aws_subnet" "database" {
  count = local.should_create_vpc && var.create_subnets && local.database_subnet_count > 0 ? local.database_subnet_count : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = local.generated_database_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.database_subnet_tags, {
    Name = "${var.name}-database-${local.azs[count.index]}"
    Type = "database"
  })
}

resource "aws_subnet" "intra" {
  count = local.should_create_vpc && var.create_subnets && local.intra_subnet_count > 0 ? local.intra_subnet_count : 0

  vpc_id            = aws_vpc.main[0].id
  cidr_block        = local.generated_intra_subnets[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(local.base_tags, var.intra_subnet_tags, {
    Name = "${var.name}-intra-${local.azs[count.index]}"
    Type = "intra"
  })
}

# ============================================================================
# Internet Gateway
# ============================================================================

resource "aws_internet_gateway" "this" {
  count = local.should_create_vpc && var.create_internet_gateway && var.internet_gateway_id == null ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.internet_gateway_tags, {
    Name = "${var.name}-igw"
  })
}

locals {
  internet_gateway_id = var.internet_gateway_id != null ? var.internet_gateway_id : (
    length(aws_internet_gateway.this) > 0 ? aws_internet_gateway.this[0].id : null
  )
}

# ============================================================================
# NAT Gateways
# ============================================================================

resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  domain = "vpc"
  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-eip-${local.nat_gateway_azs[count.index]}"
  })
}

resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? local.nat_gateway_count : 0

  allocation_id = length(var.nat_gateway_eip_ids) > count.index ? var.nat_gateway_eip_ids[count.index] : aws_eip.nat[count.index].id

  subnet_id = local.nat_gateway_subnet_ids[count.index]

  tags = merge(local.base_tags, var.nat_gateway_tags, {
    Name = "${var.name}-nat-${local.nat_gateway_azs[count.index]}"
  })

  depends_on = [aws_internet_gateway.this]
}

# ============================================================================
# Route Tables
# ============================================================================

resource "aws_route_table" "public" {
  count = (var.create_public_route_table && length(var.public_subnet_ids) > 0) || (local.should_create_vpc && var.create_subnets && local.public_subnet_count > 0) ? 1 : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.public_route_table_tags, {
    Name = "${var.name}-public-rt"
  })
}

resource "aws_route" "public_internet_gateway" {
  count = (length(aws_route_table.public) > 0 && (var.create_internet_gateway || var.internet_gateway_id != null)) ? 1 : 0

  route_table_id         = aws_route_table.public[0].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = local.internet_gateway_id
}

resource "aws_route_table_association" "public_new" {
  count = local.should_create_vpc && length(aws_subnet.public) > 0 && length(aws_route_table.public) > 0 ? length(aws_subnet.public) : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_existing" {
  count = local.using_existing_vpc && length(var.public_subnet_ids) > 0 && length(aws_route_table.public) > 0 ? length(var.public_subnet_ids) : 0

  subnet_id      = var.public_subnet_ids[count.index]
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table" "private" {
  count = var.create_private_route_tables ? (
    local.should_create_vpc ? length(aws_subnet.private) :
    local.using_existing_vpc ? max(length(var.private_subnet_ids), 1) : 0
  ) : 0

  vpc_id = local.vpc_id

  tags = merge(local.base_tags, var.private_route_table_tags, {
    Name = "${var.name}-private-rt-${count.index}"
  })
}

resource "aws_route" "private_nat_gateway" {
  count = var.create_private_route_tables && var.enable_nat_gateway ? (
    local.should_create_vpc ? length(aws_subnet.private) :
    local.using_existing_vpc ? max(length(var.private_subnet_ids), 1) : 0
  ) : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = var.nat_gateway_destination_cidr_block
  nat_gateway_id         = aws_nat_gateway.this[count.index % local.nat_gateway_count].id
}

resource "aws_route_table_association" "private_new" {
  count = local.should_create_vpc && length(aws_subnet.private) > 0 && length(aws_route_table.private) > 0 ? min(length(aws_subnet.private), length(aws_route_table.private)) : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "private_existing" {
  count = local.using_existing_vpc && length(var.private_subnet_ids) > 0 && length(aws_route_table.private) > 0 ? min(length(var.private_subnet_ids), length(aws_route_table.private)) : 0

  subnet_id      = var.private_subnet_ids[count.index]
  route_table_id = aws_route_table.private[count.index].id
}

# ============================================================================
# Additional Routes (for both new and existing VPC)
# ============================================================================

resource "aws_route" "public_additional" {
  for_each = { for i, route in var.public_routes : i => route }

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = each.value.destination_cidr_block
  gateway_id                 = each.value.gateway_id
  nat_gateway_id             = each.value.nat_gateway_id
  vpc_endpoint_id            = each.value.vpc_endpoint_id
  transit_gateway_id         = each.value.transit_gateway_id
  vpc_peering_connection_id  = each.value.vpc_peering_connection_id
  egress_only_gateway_id     = each.value.egress_only_gateway_id
  carrier_gateway_id         = each.value.carrier_gateway_id
  network_interface_id       = each.value.network_interface_id
  local_gateway_id           = each.value.local_gateway_id
  destination_prefix_list_id = each.value.destination_prefix_list_id
}

resource "aws_route" "private_additional" {
  for_each = { for i, route in var.private_routes : i => route }

  route_table_id             = each.value.route_table_id
  destination_cidr_block     = each.value.destination_cidr_block
  gateway_id                 = each.value.gateway_id
  nat_gateway_id             = each.value.nat_gateway_id
  vpc_endpoint_id            = each.value.vpc_endpoint_id
  transit_gateway_id         = each.value.transit_gateway_id
  vpc_peering_connection_id  = each.value.vpc_peering_connection_id
  egress_only_gateway_id     = each.value.egress_only_gateway_id
  carrier_gateway_id         = each.value.carrier_gateway_id
  network_interface_id       = each.value.network_interface_id
  local_gateway_id           = each.value.local_gateway_id
  destination_prefix_list_id = each.value.destination_prefix_list_id
}

# ============================================================================
# VPC Endpoints
# ============================================================================

resource "aws_vpc_endpoint" "interface" {
  for_each = var.vpc_endpoints

  vpc_id            = local.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Interface"

  subnet_ids         = lookup(each.value, "subnet_ids", null)
  security_group_ids = lookup(each.value, "security_group_ids", null)

  private_dns_enabled = lookup(each.value, "private_dns_enabled", false)

  dynamic "dns_options" {
    for_each = strcontains(each.value.service_name, "s3") ? [1] : []
    content {
      private_dns_only_for_inbound_resolver_endpoint = false
    }
  }
}

resource "aws_vpc_endpoint" "gateway" {
  for_each = var.gateway_vpc_endpoints

  vpc_id            = local.vpc_id
  service_name      = each.value.service_name
  vpc_endpoint_type = "Gateway"
  route_table_ids   = each.value.route_table_ids
  policy            = each.value.policy

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })
}

# ============================================================================
# Security Groups
# ============================================================================

resource "aws_security_group" "custom" {
  for_each = var.security_groups

  name        = "${var.name}-${each.key}"
  description = each.value.description
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = each.value.ingress_rules != null ? each.value.ingress_rules : []
    content {
      description      = ingress.value.description
      from_port        = ingress.value.from_port
      to_port          = ingress.value.to_port
      protocol         = ingress.value.protocol
      cidr_blocks      = ingress.value.cidr_blocks != null ? ingress.value.cidr_blocks : []
      ipv6_cidr_blocks = ingress.value.ipv6_cidr_blocks != null ? ingress.value.ipv6_cidr_blocks : []
      prefix_list_ids  = ingress.value.prefix_list_ids != null ? ingress.value.prefix_list_ids : []
      security_groups  = ingress.value.security_groups != null ? ingress.value.security_groups : []
      self             = ingress.value.self != null ? ingress.value.self : false
    }
  }

  dynamic "egress" {
    for_each = each.value.egress_rules != null ? each.value.egress_rules : []
    content {
      description      = egress.value.description
      from_port        = egress.value.from_port
      to_port          = egress.value.to_port
      protocol         = egress.value.protocol
      cidr_blocks      = egress.value.cidr_blocks != null ? egress.value.cidr_blocks : []
      ipv6_cidr_blocks = egress.value.ipv6_cidr_blocks != null ? egress.value.ipv6_cidr_blocks : []
      prefix_list_ids  = egress.value.prefix_list_ids != null ? egress.value.prefix_list_ids : []
      security_groups  = egress.value.security_groups != null ? egress.value.security_groups : []
      self             = egress.value.self != null ? egress.value.self : false
    }
  }

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-${each.key}"
  })
}

resource "aws_security_group_rule" "default_ingress" {
  count = length(var.default_security_group_ingress)

  type        = "ingress"
  description = var.default_security_group_ingress[count.index].description
  from_port   = var.default_security_group_ingress[count.index].from_port
  to_port     = var.default_security_group_ingress[count.index].to_port
  protocol    = var.default_security_group_ingress[count.index].protocol
  cidr_blocks = var.default_security_group_ingress[count.index].cidr_blocks != null ? var.default_security_group_ingress[count.index].cidr_blocks : []
  self        = var.default_security_group_ingress[count.index].self != null ? var.default_security_group_ingress[count.index].self : false

  security_group_id = local.using_existing_vpc ? data.aws_vpc.existing[0].main_route_table_id == null ? null : data.aws_security_group.default[0].id : aws_vpc.main[0].default_security_group_id
}

resource "aws_security_group_rule" "default_egress" {
  count = length(var.default_security_group_egress)

  type        = "egress"
  description = var.default_security_group_egress[count.index].description
  from_port   = var.default_security_group_egress[count.index].from_port
  to_port     = var.default_security_group_egress[count.index].to_port
  protocol    = var.default_security_group_egress[count.index].protocol
  cidr_blocks = var.default_security_group_egress[count.index].cidr_blocks != null ? var.default_security_group_egress[count.index].cidr_blocks : []
  self        = var.default_security_group_egress[count.index].self != null ? var.default_security_group_egress[count.index].self : false

  security_group_id = local.using_existing_vpc ? data.aws_security_group.default[0].id : aws_vpc.main[0].default_security_group_id
}

# ============================================================================
# Flow Logs
# ============================================================================

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id                   = local.vpc_id
  traffic_type             = var.flow_log_traffic_type
  log_destination_type     = upper(var.flow_log_destination_type)
  log_destination          = var.flow_log_destination_arn
  iam_role_arn             = var.flow_log_iam_role_arn
  log_format               = var.flow_log_log_format
  max_aggregation_interval = var.flow_log_max_aggregation_interval

  tags = merge(local.base_tags, {
    Name = "${var.name}-flow-logs"
  })
}

# ============================================================================
# Network ACL Configuration
# ============================================================================

resource "aws_default_network_acl" "this" {
  count = var.manage_default_network_acl ? 1 : 0

  default_network_acl_id = local.using_existing_vpc ? data.aws_network_acls.default[0].ids[0] : aws_vpc.main[0].default_network_acl_id

  dynamic "ingress" {
    for_each = var.default_network_acl_ingress
    content {
      rule_no    = ingress.value.rule_no
      action     = ingress.value.action
      protocol   = ingress.value.protocol
      from_port  = ingress.value.from_port
      to_port    = ingress.value.to_port
      cidr_block = ingress.value.cidr_block
    }
  }

  dynamic "egress" {
    for_each = var.default_network_acl_egress
    content {
      rule_no    = egress.value.rule_no
      action     = egress.value.action
      protocol   = egress.value.protocol
      from_port  = egress.value.from_port
      to_port    = egress.value.to_port
      cidr_block = egress.value.cidr_block
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-default-nacl"
  })
}

# ============================================================================
# DNS Resolver Endpoints
# ============================================================================

resource "aws_security_group" "dns_resolver" {
  count = var.enable_dns_resolver_endpoints && length(var.dns_resolver_security_group_ids) == 0 ? 1 : 0

  name        = "${var.name}-dns-resolver"
  description = "Security group for DNS resolver endpoints"
  vpc_id      = local.vpc_id

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-dns-resolver-sg"
  })
}

resource "aws_route53_resolver_endpoint" "inbound" {
  count = var.enable_dns_resolver_endpoints && length(var.dns_resolver_subnet_ids) >= 2 ? 1 : 0

  name               = "${var.name}-dns-inbound"
  direction          = "INBOUND"
  security_group_ids = local.dns_resolver_security_group_ids

  dynamic "ip_address" {
    for_each = slice(var.dns_resolver_subnet_ids, 0, min(2, length(var.dns_resolver_subnet_ids)))
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-dns-inbound"
  })
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.enable_dns_resolver_endpoints && length(var.dns_resolver_subnet_ids) >= 2 ? 1 : 0

  name               = "${var.name}-dns-outbound"
  direction          = "OUTBOUND"
  security_group_ids = local.dns_resolver_security_group_ids

  dynamic "ip_address" {
    for_each = slice(var.dns_resolver_subnet_ids, 0, min(2, length(var.dns_resolver_subnet_ids)))
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-dns-outbound"
  })
}

# ============================================================================
# VPC Peering
# ============================================================================

resource "aws_vpc_peering_connection" "this" {
  for_each = var.vpc_peerings

  peer_vpc_id   = each.value.peer_vpc_id
  peer_owner_id = each.value.peer_owner_id
  peer_region   = each.value.peer_region
  vpc_id        = local.vpc_id
  auto_accept   = each.value.auto_accept

  tags = merge(local.base_tags, each.value.tags, {
    Name = "${var.name}-peer-${each.key}"
  })
}

resource "aws_route" "peering" {
  for_each = { for k, v in var.vpc_peerings : k => v if length(v.route_table_ids) > 0 }

  route_table_id            = each.value.route_table_ids[0]
  destination_cidr_block    = each.value.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this[each.key].id
}

# ============================================================================
# Transit Gateway Attachment
# ============================================================================

resource "aws_ec2_transit_gateway_vpc_attachment" "this" {
  count = var.transit_gateway_id != null ? 1 : 0

  subnet_ids         = local.using_existing_vpc ? var.private_subnet_ids : aws_subnet.private[*].id
  transit_gateway_id = var.transit_gateway_id
  vpc_id             = local.vpc_id

  tags = merge(local.base_tags, {
    Name = "${var.name}-tgw-attachment"
  })
}

resource "aws_route" "transit_gateway" {
  for_each = { for i, route in var.transit_gateway_routes : i => route }

  route_table_id         = each.value.route_table_id
  destination_cidr_block = each.value.destination_cidr_block
  transit_gateway_id     = var.transit_gateway_id
}
