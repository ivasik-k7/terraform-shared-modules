# terraform-aws-security-groups

Security Group constructor module. Define all your SGs in one place, reference them by key — no circular dependency headaches, no copy-pasting rule blocks.

## Key capabilities

- **Cross-SG references by key** — reference any SG defined in the same module call by its map key. The module resolves IDs automatically after creation.
- **Presets** — drop-in baseline rule sets for common workloads (`eks_nodes`, `eks_control_plane`, `rds`, `alb_internal`, `vpc_endpoints`, `bastion_ssm`, `lambda`).
- **Presets are additive** — your custom rules merge on top of preset rules, never replace them.
- **All source types** — CIDR IPv4/IPv6, self, SG key (internal), SG ID (external), prefix list.
- **Uses modern rule resources** — `aws_vpc_security_group_ingress_rule` / `aws_vpc_security_group_egress_rule` instead of deprecated `aws_security_group_rule`.

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | >= 5.0 |

---

## Usage

### Simple — EKS full stack with presets

```hcl
module "sg" {
  source = "path/to/terraform-aws-security-groups"

  vpc_id      = module.vpc.vpc_id
  vpc_cidr    = module.vpc.vpc_cidr_block
  name_prefix = "acme-prod"

  security_groups = {

    "eks-control-plane" = {
      description = "EKS control plane ENIs"
      preset      = "eks_control_plane"
      preset_config = {
        eks_nodes_sg_key = "eks-nodes"   # resolved automatically
      }
    }

    "eks-nodes" = {
      description = "EKS worker nodes"
      preset      = "eks_nodes"
      preset_config = {
        eks_control_plane_sg_key = "eks-control-plane"   # resolved automatically
      }

      # Custom rules merged on top of preset
      ingress_rules = [
        {
          description              = "HTTPS from internal ALB"
          from_port                = 443
          to_port                  = 443
          protocol                 = "tcp"
          source_security_group_key = "alb-internal"
        }
      ]
      egress_rules = [
        {
          description                   = "PostgreSQL to RDS"
          from_port                     = 5432
          to_port                       = 5432
          protocol                      = "tcp"
          destination_security_group_key = "rds-postgres"
        }
      ]
    }

    "alb-internal" = {
      description = "Internal Application Load Balancer"
      preset      = "alb_internal"
    }

    "rds-postgres" = {
      description = "RDS PostgreSQL — application database"
      preset      = "rds"
      preset_config = {
        db_port          = 5432
        eks_nodes_sg_key = "eks-nodes"
      }
    }

    "vpc-endpoints" = {
      description = "VPC Interface Endpoints (SSM, ECR, Secrets Manager)"
      preset      = "vpc_endpoints"
    }

    "bastion" = {
      description = "Bastion EC2 — SSM access only, no inbound SSH"
      preset      = "bastion_ssm"
    }
  }

  default_tags = {
    environment = "prod"
    managed-by  = "terraform"
  }
}
```

### Attaching SGs to resources

```hcl
# EKS cluster
module "eks" {
  source = "terraform-aws-modules/eks/aws"

  cluster_security_group_id  = module.sg.security_group_ids["eks-control-plane"]

  eks_managed_node_groups = {
    main = {
      vpc_security_group_ids = [module.sg.security_group_ids["eks-nodes"]]
    }
  }
}

# RDS
resource "aws_db_instance" "postgres" {
  vpc_security_group_ids = [module.sg.security_group_ids["rds-postgres"]]
}

# ALB
resource "aws_lb" "internal" {
  security_groups = [module.sg.security_group_ids["alb-internal"]]
}

# Bastion
resource "aws_instance" "bastion" {
  vpc_security_group_ids = [module.sg.security_group_ids["bastion"]]
}

# VPC endpoints
resource "aws_vpc_endpoint" "ssm" {
  security_group_ids = [module.sg.security_group_ids["vpc-endpoints"]]
}
```

### External SG reference (cross-module)

```hcl
module "sg" {
  source = "path/to/terraform-aws-security-groups"

  vpc_id   = module.vpc.vpc_id
  vpc_cidr = module.vpc.vpc_cidr_block

  security_groups = {
    "app" = {
      description = "App servers"
      ingress_rules = [
        {
          description              = "Traffic from shared monitoring SG (external module)"
          from_port                = 9090
          to_port                  = 9090
          protocol                 = "tcp"
          source_security_group_id = data.terraform_remote_state.shared.outputs.monitoring_sg_id
        }
      ]
      egress_rules = []
    }
  }
}
```

### Prefix list — S3 Gateway Endpoint

```hcl
data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

module "sg" {
  source = "path/to/terraform-aws-security-groups"

  vpc_id = module.vpc.vpc_id

  security_groups = {
    "app" = {
      description = "App servers"
      ingress_rules = []
      egress_rules = [
        {
          description    = "HTTPS to S3 via Gateway Endpoint prefix list"
          from_port      = 443
          to_port        = 443
          protocol       = "tcp"
          prefix_list_id = data.aws_ec2_managed_prefix_list.s3.id
        }
      ]
    }
  }
}
```

---

## Presets

| Preset | Inbound | Outbound |
|---|---|---|
| `eks_nodes` | node-to-node (self all), kubelet 10250 from control plane, CoreDNS 53 from VPC | 443 to VPC, kubelet 10250 self, CoreDNS 53 to VPC |
| `eks_control_plane` | 443 + 10250 from nodes SG | 10250 to nodes SG, 443 to VPC |
| `rds` | DB port from nodes SG | none (DB never initiates outbound) |
| `alb_internal` | 443 + 80 from VPC CIDR | 443 + ephemeral to VPC CIDR |
| `vpc_endpoints` | 443 from VPC CIDR | none |
| `bastion_ssm` | none (no SSH) | 443 to VPC CIDR |
| `lambda` | none | 443 to VPC CIDR |

All preset rules are prefixed with `[preset]` in their description so you can identify them in the AWS console.

---

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `vpc_id` | `string` | required | VPC ID |
| `vpc_cidr` | `string` | `null` | VPC CIDR — used by presets |
| `name_prefix` | `string` | `""` | Prefix for all SG names |
| `security_groups` | `map(object)` | `{}` | SG definitions — see variables.tf |
| `default_tags` | `map(string)` | `{}` | Tags merged into all SGs |
| `revoke_rules_on_delete` | `bool` | `true` | Revoke rules before deleting SG |

## Outputs

| Name | Description |
|------|-------------|
| `security_group_ids` | `map(string)` — key → SG ID. Primary attachment output. |
| `security_group_arns` | `map(string)` — key → SG ARN |
| `security_groups` | `map(object)` — key → `{ id, arn, name, description }` |
