# Adoption mode. The VPC was provisioned by something else (CloudFormation,
# ClickOps, an old Terraform state) and the platform team wants to wrap it
# with endpoints + flow logs + the TGW attachment without touching the VPC
# resource itself.
#
# Toggle by setting existing_vpc_id; left null, the example does nothing.

variable "existing_vpc_id" {
  description = "Existing VPC id to adopt. Null = skip the example."
  type        = string
  default     = null
}

variable "existing_intra_subnet_ids" {
  description = "Intra subnet ids in the existing VPC. Used to host the endpoint ENIs."
  type        = list(string)
  default     = []
}

variable "existing_private_subnet_ids" {
  description = "Private subnet ids in the existing VPC. Optional fallback for endpoint placement."
  type        = list(string)
  default     = []
}

# for_each over a 1- or 0-element map is the cleanest way to make a module
# call conditional in Terraform.
module "existing" {
  source   = "../../modules/aws-lending-vpc"
  for_each = var.existing_vpc_id == null ? {} : { this = true }

  name   = "ldvpc-existing"
  vpc_id = var.existing_vpc_id

  environment = "prod"
  tags = {
    Project    = "aws-lending-vpc-demo"
    Team       = "platform-network"
    CostCenter = "NET-001"
    Owner      = "network@acme.io"
  }

  create_subnets              = false
  create_internet_gateway     = false
  enable_nat_gateway          = false
  create_public_route_table   = false
  create_private_route_tables = false
  create_database_route_table = false
  create_intra_route_table    = false
  create_transit_route_table  = false

  intra_subnet_ids   = var.existing_intra_subnet_ids
  private_subnet_ids = var.existing_private_subnet_ids

  # Endpoints land on the intra tier when present, else fall back to private.
  # Region prefix added automatically — same code works in any region.
  interface_endpoint_services = ["ssm", "ssmmessages", "ec2messages", "secretsmanager"]
}

output "existing_vpc_endpoints" {
  value       = { for k, m in module.existing : k => m.vpc_endpoint_ids }
  description = "Endpoint ids attached to the adopted VPC."
}
