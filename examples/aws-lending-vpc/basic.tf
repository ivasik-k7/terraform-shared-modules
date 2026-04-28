# Smallest viable VPC. Auto-carved subnets, default per-AZ NAT, IGW. Good
# for kicking the tires.
#
# Apply:
#   terraform init
#   terraform apply -target=module.basic
#
# Cost note: 3 NAT gateways at ~$33/month each. Use single_nat_gateway = true
# for dev/test if HA isn't required.

module "basic" {
  source = "../../modules/aws-lending-vpc"

  name        = "ldvpc-basic"
  environment = "sandbox"
  create_vpc  = true

  vpc_cidr_block     = "10.10.0.0/16"
  auto_carve_subnets = true

  tags = {
    Project    = "aws-lending-vpc-demo"
    Team       = "platform"
    CostCenter = "DEMO"
    Owner      = "platform@acme.io"
  }
}

output "basic_vpc_id" {
  value       = module.basic.vpc_id
  description = "VPC id."
}

output "basic_subnets_by_az" {
  value       = module.basic.subnets_by_az
  description = "Per-AZ subnet map. Pass into workload modules."
}
