# Route 53 Resolver inbound + outbound endpoints for hybrid DNS.
#   inbound   on-prem -> AWS  (DNS queries from corp resolvers into private hosted zones)
#   outbound  AWS -> on-prem  (forwarder rules to corporate DNS)
#
# Subnets default to the intra tier when the caller didn't specify them; if
# intra is empty the module falls back to private. AWS requires endpoints
# to span at least 2 AZs.
#
# The auto-built SG is permissive (53/tcp+udp from 0.0.0.0/0). Replace it in
# any non-sandbox deployment.

resource "aws_security_group" "dns_resolver" {
  count = var.enable_dns_resolver_endpoints && length(var.dns_resolver_security_group_ids) == 0 ? 1 : 0

  name        = "${var.name}-dns-resolver"
  description = "Route 53 Resolver endpoints (module-default, replace in prod)."
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
  count = var.enable_dns_resolver_endpoints && length(local.effective_dns_resolver_subnet_ids) >= 2 ? 1 : 0

  name               = "${var.name}-dns-inbound"
  direction          = "INBOUND"
  security_group_ids = local.dns_resolver_security_group_ids

  dynamic "ip_address" {
    for_each = slice(local.effective_dns_resolver_subnet_ids, 0, min(2, length(local.effective_dns_resolver_subnet_ids)))
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-dns-inbound"
  })
}

resource "aws_route53_resolver_endpoint" "outbound" {
  count = var.enable_dns_resolver_endpoints && length(local.effective_dns_resolver_subnet_ids) >= 2 ? 1 : 0

  name               = "${var.name}-dns-outbound"
  direction          = "OUTBOUND"
  security_group_ids = local.dns_resolver_security_group_ids

  dynamic "ip_address" {
    for_each = slice(local.effective_dns_resolver_subnet_ids, 0, min(2, length(local.effective_dns_resolver_subnet_ids)))
    content {
      subnet_id = ip_address.value
    }
  }

  tags = merge(local.base_tags, {
    Name = "${var.name}-dns-outbound"
  })
}
