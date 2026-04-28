# Full migration-factory landing zone:
#   - 5 tiers carved automatically (public/private/database/intra/transit)
#   - 3 AZs, per-AZ NAT
#   - SSM + ECR + Logs + Secrets Manager interface endpoints
#   - S3 + DDB gateway endpoints on private + intra route tables
#   - Default SG locked down
#   - VPC flow logs to S3
#   - TGW attachment + on-prem routing
#   - FinOps tag enforcement
#   - Inter-tier SG rules (alb -> app -> db)
#
# Set hub_transit_gateway_id to skip the TGW pieces entirely (default null).

variable "hub_transit_gateway_id" {
  description = "Existing TGW id. Null skips the attachment."
  type        = string
  default     = null
}

variable "hub_on_prem_cidr" {
  description = "On-prem CIDR reachable via the TGW."
  type        = string
  default     = "172.16.0.0/12"
}

# S3 bucket for flow logs. Owned by the example so destroy cleans up cleanly.
resource "aws_s3_bucket" "flow_logs" {
  bucket        = "ldvpc-flowlogs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project = "aws-lending-vpc-demo"
  }
}

data "aws_caller_identity" "current" {}

module "landing" {
  source = "../../modules/aws-lending-vpc"

  name        = "ldvpc-wave3"
  environment = "prod"
  create_vpc  = true

  enforce_finops_tags = true
  tags = {
    Project    = "migration-wave-3"
    Team       = "platform-network"
    CostCenter = "NET-001"
    Owner      = "network@acme.io"
  }

  vpc_cidr_block     = "10.40.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  auto_carve_subnets = true

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  # Curated endpoint sets. Region prefix added automatically.
  interface_endpoint_services = [
    "ssm", "ssmmessages", "ec2messages",
    "ecr.api", "ecr.dkr", "logs",
    "sts", "secretsmanager", "kms",
  ]
  gateway_endpoint_services = ["s3", "dynamodb"]

  # Default endpoint SG is built automatically. Add the on-prem CIDR so corp
  # callers reaching the endpoints over TGW are also allowed.
  endpoint_security_group_extra_cidrs = [var.hub_on_prem_cidr]

  # Lock the default SG. Empty rule lists strip every rule from it.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Flow logs to S3 — no IAM role needed for S3 destination.
  enable_flow_logs                  = true
  flow_log_destination_type         = "s3"
  flow_log_destination_arn          = aws_s3_bucket.flow_logs.arn
  flow_log_traffic_type             = "ALL"
  flow_log_max_aggregation_interval = 60

  # TGW attachment lands automatically on the auto-carved transit subnets.
  transit_gateway_id = var.hub_transit_gateway_id

  transit_gateway_routes = var.hub_transit_gateway_id == null ? [] : [
    {
      destination_cidr_block = var.hub_on_prem_cidr
      route_table_ids = concat(
        module.landing.private_route_table_ids,
        [module.landing.intra_route_table_id],
      )
    },
  ]

  # Custom SGs and the inter-tier shorthand. The module wires the SG-to-SG
  # ingress rules for you.
  security_groups = {
    alb = {
      description = "Public ALB"
      ingress_rules = [
        { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"], description = "HTTPS in" },
      ]
    }
    app = {
      description = "Application tier"
    }
    db = {
      description = "Database tier"
    }
  }

  inter_tier_rules = [
    { from = "alb", to = "app", from_port = 8080, to_port = 8080, description = "ALB -> app" },
    { from = "app", to = "db", from_port = 5432, to_port = 5432, description = "app -> postgres" },
  ]
}

output "landing_network" {
  value       = module.landing.network
  description = "Full network description, ready to feed into downstream modules."
}

output "landing_nat_public_ips" {
  value       = module.landing.nat_public_ips
  description = "NAT public IPs. Hand these to the on-prem firewall team."
}

output "landing_subnets_by_az" {
  value       = module.landing.subnets_by_az
  description = "Per-AZ subnet map."
}
