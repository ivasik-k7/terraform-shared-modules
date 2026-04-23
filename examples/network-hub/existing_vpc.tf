# Adopting an existing VPC.
#
# Scenario: the VPC was created by someone else (another Terraform state,
# CloudFormation, ClickOps) and the network team wants to attach endpoints
# and flow logs to it without importing or re-creating it.
#
# The module looks up the VPC and subnets by id, skips VPC/subnet creation,
# and only provisions the things you ask for (endpoints, SGs, flow logs,
# peering, TGW attachment, etc.).
#
# Toggle this example by setting existing_vpc_id to a real VPC id.

variable "existing_vpc_id" {
  description = "Existing VPC id to adopt. Leave null to skip this example."
  type        = string
  default     = null
}

variable "existing_private_subnet_ids" {
  description = "Private subnet ids in the existing VPC. Required when existing_vpc_id is set."
  type        = list(string)
  default     = []
}

variable "existing_intra_subnet_ids" {
  description = "Intra subnet ids in the existing VPC. Optional."
  type        = list(string)
  default     = []
}

# Only instantiate the module when the caller provides a VPC id. Using a
# for_each over a one- or zero-element map is the least-ugly way to make a
# module call conditional.
module "existing" {
  source   = "../../modules/network-hub"
  for_each = var.existing_vpc_id == null ? {} : { this = true }

  name   = "nethub-existing"
  vpc_id = var.existing_vpc_id

  environment = "prod"
  tags = {
    Project = "network-hub-demo"
    Owner   = "network@acme.io"
  }

  # We're not creating subnets or route tables - just adding things around
  # the existing VPC.
  create_subnets              = false
  create_internet_gateway     = false
  enable_nat_gateway          = false
  create_public_route_table   = false
  create_private_route_tables = false
  create_database_route_table = false
  create_intra_route_table    = false
  create_transit_route_table  = false

  # Pass the subnet ids through so the module can use them as inputs to other
  # resources (e.g. endpoints).
  private_subnet_ids = var.existing_private_subnet_ids
  intra_subnet_ids   = var.existing_intra_subnet_ids

  # Interface endpoints. Prefer intra subnets if the caller has them; fall
  # back to private.
  vpc_endpoints = {
    ssm = {
      service_name = "com.amazonaws.${var.aws_region}.ssm"
      subnet_ids   = length(var.existing_intra_subnet_ids) > 0 ? var.existing_intra_subnet_ids : var.existing_private_subnet_ids
    }
    secretsmanager = {
      service_name = "com.amazonaws.${var.aws_region}.secretsmanager"
      subnet_ids   = length(var.existing_intra_subnet_ids) > 0 ? var.existing_intra_subnet_ids : var.existing_private_subnet_ids
    }
  }
}

output "existing_vpc_endpoints" {
  value       = { for k, m in module.existing : k => m.vpc_endpoint_ids }
  description = "Interface endpoint ids added to the adopted VPC."
}
