# Hub VPC for an on-prem-to-AWS migration.
#
# Layout:
#   public    ALBs / bastion / NAT gateways
#   private   workloads (EKS nodes, ECS tasks, EC2)
#   database  RDS subnet group, no default route
#   intra     VPC endpoint ENIs, EKS control plane ENIs, internal LBs
#   transit   small /28 per AZ, TGW attachment lives here
#
# Connectivity:
#   - IGW + per-AZ NAT gateways for internet egress from private subnets.
#   - S3 + DynamoDB gateway endpoints to skip the NAT for those services.
#   - Interface endpoints for SSM / ECR / Secrets Manager, attached in the
#     intra tier.
#   - Transit Gateway attachment on the transit subnets.
#   - On-prem CIDR (172.16.0.0/12) routed from private + intra via TGW.
#   - VPC flow logs pushed to an S3 bucket.
#
# The TGW id is a variable so you can point this at an existing TGW. Leave it
# null (the default) to skip the attachment entirely.

variable "hub_transit_gateway_id" {
  description = "Existing Transit Gateway id to attach the hub VPC to. Null skips the attachment."
  type        = string
  default     = null
}

variable "hub_on_prem_cidr" {
  description = "On-prem corporate CIDR reachable via the TGW."
  type        = string
  default     = "172.16.0.0/12"
}

# Destination for flow logs. The bucket is owned by the example so you can
# destroy everything in one apply.
resource "aws_s3_bucket" "flow_logs" {
  bucket        = "nethub-hub-flowlogs-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = {
    Project = "network-hub-demo"
  }
}

data "aws_caller_identity" "current" {}

module "hub" {
  source = "../../modules/network-hub"

  name       = "nethub-hub"
  create_vpc = true

  environment = "prod"
  tags = {
    Project    = "migration-factory"
    Team       = "platform-network"
    CostCenter = "NET-001"
    Owner      = "network@acme.io"
  }

  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  # Subnet layout: 3 AZs, one CIDR per AZ per tier.
  public_subnets   = ["10.0.0.0/24", "10.0.1.0/24", "10.0.2.0/24"]
  private_subnets  = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  database_subnets = ["10.0.64.0/24", "10.0.65.0/24", "10.0.66.0/24"]
  intra_subnets    = ["10.0.80.0/24", "10.0.81.0/24", "10.0.82.0/24"]

  # /28 is sufficient: AWS reserves 5 addresses, TGW uses 1 ENI per AZ, and
  # that still leaves room for future attachments (Cloud WAN, Direct Connect
  # gateway association, etc).
  transit_subnets = ["10.0.96.0/28", "10.0.96.16/28", "10.0.96.32/28"]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  # Lock down the default security group. Empty rule lists mean no traffic is
  # allowed by the default SG - anything that wants connectivity must use a
  # purpose-built SG.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []

  # Gateway endpoints are free and bypass NAT for S3/DDB traffic.
  gateway_vpc_endpoints = {
    s3 = {
      service_name    = "com.amazonaws.${var.aws_region}.s3"
      route_table_ids = concat(module.hub.private_route_table_ids, [module.hub.intra_route_table_id])
    }
    dynamodb = {
      service_name    = "com.amazonaws.${var.aws_region}.dynamodb"
      route_table_ids = concat(module.hub.private_route_table_ids, [module.hub.intra_route_table_id])
    }
  }

  # Interface endpoints land in the intra tier. They cost ~$7/month each per
  # AZ plus data processing, so only enable the ones you actually need.
  vpc_endpoints = {
    ssm = {
      service_name       = "com.amazonaws.${var.aws_region}.ssm"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
    ssmmessages = {
      service_name       = "com.amazonaws.${var.aws_region}.ssmmessages"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
    ec2messages = {
      service_name       = "com.amazonaws.${var.aws_region}.ec2messages"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
    ecr_api = {
      service_name       = "com.amazonaws.${var.aws_region}.ecr.api"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
    ecr_dkr = {
      service_name       = "com.amazonaws.${var.aws_region}.ecr.dkr"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
    secretsmanager = {
      service_name       = "com.amazonaws.${var.aws_region}.secretsmanager"
      subnet_ids         = module.hub.intra_subnet_ids
      security_group_ids = [aws_security_group.endpoints.id]
    }
  }

  # Flow logs to S3 (no IAM role needed for S3 destination).
  enable_flow_logs                  = true
  flow_log_destination_type         = "s3"
  flow_log_destination_arn          = aws_s3_bucket.flow_logs.arn
  flow_log_traffic_type             = "ALL"
  flow_log_max_aggregation_interval = 60

  # TGW attachment. The module picks the transit subnets automatically because
  # we populated transit_subnets above.
  transit_gateway_id = var.hub_transit_gateway_id

  # Send on-prem traffic via the TGW from the private and intra route tables.
  # The database route table stays blank - RDS never needs to reach on-prem.
  transit_gateway_routes = var.hub_transit_gateway_id == null ? [] : [
    {
      destination_cidr_block = var.hub_on_prem_cidr
      route_table_ids = concat(
        module.hub.private_route_table_ids,
        [module.hub.intra_route_table_id],
      )
    },
  ]
}

# Security group consumed by the interface endpoints. HTTPS in from the VPC,
# all out. The module creates the endpoints but not the SG because in real
# deployments you usually want to share one SG across many endpoints.
resource "aws_security_group" "endpoints" {
  name        = "nethub-hub-endpoints"
  description = "Interface VPC endpoints in the hub VPC"
  vpc_id      = module.hub.vpc_id

  ingress {
    description = "HTTPS from the VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.hub.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nethub-hub-endpoints"
  }
}

output "hub_summary" {
  value       = module.hub.summary
  description = "Consolidated network layout - pass this into downstream workload modules."
}

output "hub_transit_route_table_id" {
  value       = module.hub.transit_route_table_id
  description = "Transit subnet route table. Useful if you want to install Direct Connect propagation routes here."
}
