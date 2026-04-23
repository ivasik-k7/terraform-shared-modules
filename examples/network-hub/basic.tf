# Minimal network-hub example: public + private subnets in three AZs, one NAT
# per AZ, an IGW. Nothing else. Good for kicking the tires.
#
# Apply:
#   terraform init
#   terraform apply -target=module.basic
#
# Cost note: three NAT gateways at ~$33/month each. Set one_nat_gateway_per_az
# = false and single_nat_gateway = true if you don't need HA egress.

module "basic" {
  source = "../../modules/network-hub"

  name       = "nethub-basic"
  create_vpc = true

  environment = "sandbox"
  tags = {
    Project    = "network-hub-demo"
    Team       = "platform"
    CostCenter = "DEMO"
  }

  vpc_cidr_block     = "10.10.0.0/16"
  availability_zones = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]

  public_subnets  = ["10.10.0.0/24", "10.10.1.0/24", "10.10.2.0/24"]
  private_subnets = ["10.10.16.0/20", "10.10.32.0/20", "10.10.48.0/20"]

  # database / intra / transit tiers disabled by passing empty lists (default).

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true
}

output "basic_vpc_id" {
  value       = module.basic.vpc_id
  description = "VPC id for the basic example."
}

output "basic_private_subnets" {
  value       = module.basic.private_subnet_ids
  description = "Private subnet ids, ready to hand to workload modules."
}
