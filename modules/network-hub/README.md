# Network Hub Module

Enterprise-grade VPC module for creating centralized network infrastructure with connectivity options. This module serves as the foundation for hub-and-spoke network architectures, providing secure, scalable, and highly available networking infrastructure.

## Overview

The Network Hub module is designed to create and manage complex VPC infrastructures that serve as central connectivity points in enterprise AWS environments. It supports both greenfield deployments (new VPC creation) and brownfield scenarios (existing VPC integration), making it ideal for organizations at any stage of their cloud journey.

### Key Capabilities

- **🏗️ Flexible VPC Management** - Create new VPC or integrate with existing infrastructure
- **🌐 Multi-AZ Subnets** - Public, private, database, and intra subnets across availability zones
- **🚪 NAT Gateway Support** - Single or per-AZ NAT gateways with automatic EIP management
- **🔍 DNS Resolver Endpoints** - Inbound/outbound DNS resolution for hybrid cloud connectivity
- **🔗 VPC Endpoints** - Interface and gateway endpoints for secure AWS service access
- **🤝 VPC Peering** - Cross-VPC connectivity with automated route management
- **🛡️ Security Groups** - Custom and default security group management with validation
- **📊 Flow Logs** - VPC traffic monitoring and logging
- **⚙️ DHCP Options** - Custom DNS and NTP server configuration for enterprise requirements

## Architecture Patterns

### Hub-and-Spoke Network

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Spoke VPC A   │────│   Network Hub   │────│   Spoke VPC B   │
│  (Workloads)    │    │  (Shared Svcs)  │    │  (Workloads)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                              │
                       ┌─────────────────┐
                       │   On-Premises   │
                       │   (via DX/VPN)  │
                       └─────────────────┘
```

### Multi-Tier Application Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        VPC (10.0.0.0/16)                   │
├─────────────────────────────────────────────────────────────┤
│ Public Subnets (10.0.1-3.0/24)                             │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │
│ │     ALB     │ │   NAT GW    │ │   Bastion   │             │
│ └─────────────┘ └─────────────┘ └─────────────┘             │
├─────────────────────────────────────────────────────────────┤
│ Private Subnets (10.0.11-13.0/24)                          │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │
│ │   App Tier  │ │   App Tier  │ │   App Tier  │             │
│ └─────────────┘ └─────────────┘ └─────────────┘             │
├─────────────────────────────────────────────────────────────┤
│ Database Subnets (10.0.21-23.0/24)                         │
│ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐             │
│ │     RDS     │ │     RDS     │ │   ElastiC   │             │
│ │   Primary   │ │   Standby   │ │    Cache    │             │
│ └─────────────┘ └─────────────┘ └─────────────┘             │
└─────────────────────────────────────────────────────────────┘
```

## Usage Examples

### 1. Production-Ready Multi-AZ VPC

```hcl
module "production_network" {
  source = "./modules/network-hub"

  name        = "prod-network"
  environment = "prod"

  # VPC Configuration
  vpc_cidr_block = "10.0.0.0/16"
  secondary_cidr_blocks = ["10.1.0.0/16"]  # Additional IP space

  # Multi-AZ deployment across 3 zones
  availability_zones = ["us-west-2a", "us-west-2b", "us-west-2c"]

  # Subnet configuration
  public_subnet_cidrs   = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs  = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  database_subnet_cidrs = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]
  intra_subnet_cidrs    = ["10.0.31.0/24", "10.0.32.0/24", "10.0.33.0/24"]

  # High availability NAT configuration
  create_internet_gateway = true
  enable_nat_gateway      = true
  single_nat_gateway      = false  # One NAT per AZ for HA
  one_nat_gateway_per_az  = true

  # DNS configuration
  enable_dns_support   = true
  enable_dns_hostnames = true

  # Monitoring and logging
  enable_flow_logs = true
  flow_log_destination_type = "cloud-watch-logs"
  flow_log_traffic_type     = "ALL"

  tags = {
    Project     = "enterprise-app"
    CostCenter  = "engineering"
    Compliance  = "sox"
  }
}
```

### 2. Hybrid Cloud with DNS Resolution

```hcl
module "hybrid_network" {
  source = "./modules/network-hub"

  name        = "hybrid-hub"
  environment = "prod"

  vpc_cidr_block = "10.100.0.0/16"
  availability_zones = ["us-east-1a", "us-east-1b"]

  private_subnet_cidrs = ["10.100.1.0/24", "10.100.2.0/24"]

  # DNS resolver endpoints for hybrid connectivity
  enable_dns_resolver_endpoints = true
  dns_resolver_subnet_ids = [
    "subnet-12345678",  # Private subnet in AZ-a
    "subnet-87654321"   # Private subnet in AZ-b
  ]

  # Custom security group for DNS resolver
  security_groups = {
    dns-resolver = {
      description = "DNS resolver endpoint security group"
      ingress_rules = [
        {
          description = "DNS from on-premises"
          from_port   = 53
          to_port     = 53
          protocol    = "tcp"
          cidr_blocks = ["192.168.0.0/16"]  # On-premises CIDR
        },
        {
          description = "DNS UDP from on-premises"
          from_port   = 53
          to_port     = 53
          protocol    = "udp"
          cidr_blocks = ["192.168.0.0/16"]
        }
      ]
      egress_rules = [
        {
          description = "All outbound"
          from_port   = 0
          to_port     = 0
          protocol    = "-1"
          cidr_blocks = ["0.0.0.0/0"]
        }
      ]
      tags = { Purpose = "hybrid-dns" }
    }
  }

  # DHCP options for custom DNS
  enable_dhcp_options = true
  dhcp_options_domain_name = "corp.example.com"
  dhcp_options_domain_name_servers = ["10.100.1.10", "10.100.2.10"]
}
```

### 3. Service-Optimized VPC with Endpoints

```hcl
module "service_network" {
  source = "./modules/network-hub"

  name        = "services-vpc"
  environment = "prod"

  vpc_cidr_block = "10.200.0.0/16"
  private_subnet_cidrs = ["10.200.1.0/24", "10.200.2.0/24"]

  # VPC Endpoints for AWS services (no internet required)
  vpc_endpoints = {
    s3 = {
      service_name        = "com.amazonaws.us-west-2.s3"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = ["subnet-private1", "subnet-private2"]
      security_group_ids  = ["sg-vpc-endpoints"]
      private_dns_enabled = true
      policy              = null
      tags                = { Service = "s3" }
    }

    ec2 = {
      service_name        = "com.amazonaws.us-west-2.ec2"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = ["subnet-private1", "subnet-private2"]
      security_group_ids  = ["sg-vpc-endpoints"]
      private_dns_enabled = true
      policy              = null
      tags                = { Service = "ec2" }
    }

    ssm = {
      service_name        = "com.amazonaws.us-west-2.ssm"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = ["subnet-private1", "subnet-private2"]
      security_group_ids  = ["sg-vpc-endpoints"]
      private_dns_enabled = true
      policy              = null
      tags                = { Service = "ssm" }
    }
  }

  # Gateway endpoints (no additional charges)
  gateway_vpc_endpoints = {
    s3 = {
      service_name    = "com.amazonaws.us-west-2.s3"
      route_table_ids = ["rt-private"]
      policy          = null
      tags            = { Type = "gateway" }
    }

    dynamodb = {
      service_name    = "com.amazonaws.us-west-2.dynamodb"
      route_table_ids = ["rt-private"]
      policy          = null
      tags            = { Type = "gateway" }
    }
  }
}
```

### 4. Multi-VPC Peering Hub

```hcl
module "peering_hub" {
  source = "./modules/network-hub"

  name        = "peering-hub"
  environment = "prod"

  vpc_cidr_block = "10.0.0.0/16"
  private_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24"]

  # VPC Peering connections
  vpc_peerings = {
    spoke-a = {
      peer_vpc_id      = "vpc-spoke-a-12345"
      peer_vpc_cidr    = "10.1.0.0/16"
      peer_owner_id    = "123456789012"
      peer_region      = "us-west-2"
      auto_accept      = true
      route_table_ids  = ["rt-private-hub"]
      tags = {
        Purpose = "spoke-a-connectivity"
      }
    }

    spoke-b = {
      peer_vpc_id      = "vpc-spoke-b-67890"
      peer_vpc_cidr    = "10.2.0.0/16"
      peer_owner_id    = "123456789012"
      peer_region      = "us-west-2"
      auto_accept      = true
      route_table_ids  = ["rt-private-hub"]
      tags = {
        Purpose = "spoke-b-connectivity"
      }
    }
  }
}
```

### 5. Existing VPC Integration

```hcl
module "existing_vpc_enhancement" {
  source = "./modules/network-hub"

  name        = "enhanced-existing"
  environment = "prod"

  # Use existing VPC
  create_vpc = false
  vpc_id     = "vpc-existing-12345"

  # Work with existing subnets
  public_subnet_ids  = ["subnet-pub-1", "subnet-pub-2"]
  private_subnet_ids = ["subnet-prv-1", "subnet-prv-2"]

  # Add route table management
  create_public_route_table   = true
  create_private_route_tables = true

  # Add NAT Gateway to existing public subnets
  enable_nat_gateway = true
  single_nat_gateway = true

  # Enhance with VPC endpoints
  vpc_endpoints = {
    s3 = {
      service_name        = "com.amazonaws.us-west-2.s3"
      vpc_endpoint_type   = "Interface"
      subnet_ids          = ["subnet-prv-1", "subnet-prv-2"]
      security_group_ids  = ["sg-existing-endpoints"]
      private_dns_enabled = true
      policy              = null
      tags                = { Enhancement = "true" }
    }
  }
}
```

## Advanced Configuration

### Custom Security Groups

```hcl
security_groups = {
  web-tier = {
    description = "Web tier security group"
    ingress_rules = [
      {
        description = "HTTP from ALB"
        from_port   = 80
        to_port     = 80
        protocol    = "tcp"
        security_groups = ["sg-alb-12345"]
      },
      {
        description = "HTTPS from ALB"
        from_port   = 443
        to_port     = 443
        protocol    = "tcp"
        security_groups = ["sg-alb-12345"]
      }
    ]
    egress_rules = [
      {
        description = "Database access"
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        security_groups = ["sg-database-12345"]
      }
    ]
    tags = { Tier = "web" }
  }

  database = {
    description = "Database tier security group"
    ingress_rules = [
      {
        description = "PostgreSQL from app tier"
        from_port   = 5432
        to_port     = 5432
        protocol    = "tcp"
        security_groups = ["sg-app-tier"]
      }
    ]
    egress_rules = []
    tags = { Tier = "database" }
  }
}
```

### Flow Logs Configuration

```hcl
# CloudWatch Logs
enable_flow_logs = true
flow_log_destination_type = "cloud-watch-logs"
flow_log_destination_arn = "arn:aws:logs:us-west-2:123456789012:log-group:vpc-flow-logs"
flow_log_iam_role_arn = "arn:aws:iam::123456789012:role/flowlogsRole"
flow_log_traffic_type = "ALL"
flow_log_log_format = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${windowstart} $${windowend} $${action} $${flowlogstatus}"

# S3 Destination
enable_flow_logs = true
flow_log_destination_type = "s3"
flow_log_destination_arn = "arn:aws:s3:::my-vpc-flow-logs-bucket/flow-logs/"
flow_log_traffic_type = "REJECT"  # Only log rejected traffic
```

## Complete Input Reference

### Core Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `name` | Name prefix for all resources | `string` | n/a | yes |
| `environment` | Environment name (dev, staging, prod, test, sandbox) | `string` | `"dev"` | no |
| `tags` | Map of tags to apply to all resources | `map(string)` | `{}` | no |

### VPC Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_vpc` | Whether to create a new VPC | `bool` | `true` | no |
| `vpc_id` | ID of existing VPC to use (when create_vpc = false) | `string` | `null` | no |
| `vpc_cidr_block` | CIDR block for VPC | `string` | `null` | conditional |
| `secondary_cidr_blocks` | List of secondary CIDR blocks | `list(string)` | `[]` | no |
| `instance_tenancy` | Tenancy option for instances (default, dedicated) | `string` | `"default"` | no |
| `enable_dns_support` | Enable DNS support in VPC | `bool` | `true` | no |
| `enable_dns_hostnames` | Enable DNS hostnames in VPC | `bool` | `true` | no |
| `enable_ipv6` | Enable IPv6 CIDR block | `bool` | `false` | no |
| `enable_network_address_usage_metrics` | Enable network address usage metrics | `bool` | `false` | no |

### Subnet Configuration

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_subnets` | Whether to create subnets (when create_vpc = true) | `bool` | `true` | no |
| `availability_zones` | List of availability zones | `list(string)` | `[]` | no |
| `public_subnet_cidrs` | CIDR blocks for public subnets | `list(string)` | `[]` | no |
| `private_subnet_cidrs` | CIDR blocks for private subnets | `list(string)` | `[]` | no |
| `database_subnet_cidrs` | CIDR blocks for database subnets | `list(string)` | `[]` | no |
| `intra_subnet_cidrs` | CIDR blocks for intra subnets | `list(string)` | `[]` | no |
| `public_subnet_ids` | IDs of existing public subnets | `list(string)` | `[]` | no |
| `private_subnet_ids` | IDs of existing private subnets | `list(string)` | `[]` | no |
| `database_subnet_ids` | IDs of existing database subnets | `list(string)` | `[]` | no |
| `map_public_ip_on_launch` | Auto-assign public IP in public subnets | `bool` | `true` | no |

### Internet Gateway & NAT

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_internet_gateway` | Create Internet Gateway | `bool` | `true` | no |
| `internet_gateway_id` | ID of existing Internet Gateway | `string` | `null` | no |
| `enable_nat_gateway` | Enable NAT Gateway | `bool` | `false` | no |
| `single_nat_gateway` | Use single NAT Gateway for all AZs | `bool` | `false` | no |
| `one_nat_gateway_per_az` | Create one NAT Gateway per AZ | `bool` | `false` | no |
| `nat_gateway_eip_ids` | List of EIP IDs for NAT Gateways | `list(string)` | `[]` | no |
| `nat_gateway_destination_cidr_block` | CIDR for NAT Gateway routes | `string` | `"0.0.0.0/0"` | no |

### Route Tables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `create_public_route_table` | Create public route table | `bool` | `true` | no |
| `create_private_route_tables` | Create private route tables | `bool` | `true` | no |

### DNS Resolver Endpoints

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enable_dns_resolver_endpoints` | Enable DNS resolver endpoints | `bool` | `false` | no |
| `dns_resolver_subnet_ids` | Subnet IDs for DNS resolver endpoints (minimum 2) | `list(string)` | `[]` | no |
| `dns_resolver_security_group_ids` | Security group IDs for DNS resolver endpoints | `list(string)` | `[]` | no |

### VPC Endpoints

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_endpoints` | Map of VPC interface endpoints | `map(object)` | `{}` | no |
| `gateway_vpc_endpoints` | Map of VPC gateway endpoints | `map(object)` | `{}` | no |

### Security Groups

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `security_groups` | Map of custom security groups | `map(object)` | `{}` | no |
| `default_security_group_ingress` | Default security group ingress rules | `list(object)` | `[]` | no |
| `default_security_group_egress` | Default security group egress rules | `list(object)` | `[]` | no |

### VPC Peering

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `vpc_peerings` | Map of VPC peering connections | `map(object)` | `{}` | no |

### Flow Logs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enable_flow_logs` | Enable VPC Flow Logs | `bool` | `false` | no |
| `flow_log_destination_type` | Flow log destination type (cloud-watch-logs, s3) | `string` | `"cloud-watch-logs"` | no |
| `flow_log_destination_arn` | ARN of flow log destination | `string` | `null` | no |
| `flow_log_iam_role_arn` | IAM role ARN for flow logs | `string` | `null` | no |
| `flow_log_traffic_type` | Traffic type to log (ALL, ACCEPT, REJECT) | `string` | `"ALL"` | no |
| `flow_log_log_format` | Custom log format | `string` | `null` | no |
| `flow_log_max_aggregation_interval` | Max aggregation interval (60, 600) | `number` | `600` | no |

### DHCP Options

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `enable_dhcp_options` | Enable custom DHCP options | `bool` | `false` | no |
| `dhcp_options_domain_name` | Domain name for DHCP options | `string` | `null` | no |
| `dhcp_options_domain_name_servers` | DNS servers for DHCP options | `list(string)` | `[]` | no |
| `dhcp_options_ntp_servers` | NTP servers for DHCP options | `list(string)` | `[]` | no |
| `dhcp_options_netbios_name_servers` | NetBIOS name servers | `list(string)` | `[]` | no |
| `dhcp_options_netbios_node_type` | NetBIOS node type | `number` | `null` | no |

### Tagging

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `public_subnet_tags` | Additional tags for public subnets | `map(string)` | `{}` | no |
| `private_subnet_tags` | Additional tags for private subnets | `map(string)` | `{}` | no |
| `database_subnet_tags` | Additional tags for database subnets | `map(string)` | `{}` | no |
| `intra_subnet_tags` | Additional tags for intra subnets | `map(string)` | `{}` | no |
| `internet_gateway_tags` | Additional tags for Internet Gateway | `map(string)` | `{}` | no |
| `nat_gateway_tags` | Additional tags for NAT Gateways | `map(string)` | `{}` | no |
| `public_route_table_tags` | Additional tags for public route table | `map(string)` | `{}` | no |
| `private_route_table_tags` | Additional tags for private route tables | `map(string)` | `{}` | no |

## Complete Output Reference

### VPC Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | ID of the VPC |
| `vpc_arn` | ARN of the VPC |
| `vpc_cidr_block` | CIDR block of the VPC |
| `vpc_secondary_cidr_blocks` | Secondary CIDR blocks |
| `vpc_owner_id` | Owner ID of the VPC |
| `vpc_default_security_group_id` | Default security group ID |
| `vpc_default_network_acl_id` | Default network ACL ID |
| `vpc_default_route_table_id` | Default route table ID |
| `vpc_ipv6_cidr_block` | IPv6 CIDR block |

### Subnet Outputs

| Name | Description |
|------|-------------|
| `public_subnet_ids` | List of public subnet IDs |
| `public_subnet_arns` | List of public subnet ARNs |
| `public_subnet_cidr_blocks` | List of public subnet CIDR blocks |
| `private_subnet_ids` | List of private subnet IDs |
| `private_subnet_arns` | List of private subnet ARNs |
| `private_subnet_cidr_blocks` | List of private subnet CIDR blocks |
| `database_subnet_ids` | List of database subnet IDs |
| `database_subnet_arns` | List of database subnet ARNs |
| `database_subnet_cidr_blocks` | List of database subnet CIDR blocks |
| `intra_subnet_ids` | List of intra subnet IDs |
| `intra_subnet_arns` | List of intra subnet ARNs |
| `intra_subnet_cidr_blocks` | List of intra subnet CIDR blocks |

### Gateway & NAT Outputs

| Name | Description |
|------|-------------|
| `internet_gateway_id` | ID of the Internet Gateway |
| `internet_gateway_arn` | ARN of the Internet Gateway |
| `nat_gateway_ids` | List of NAT Gateway IDs |
| `nat_gateway_public_ips` | List of NAT Gateway public IPs |
| `nat_eip_ids` | List of NAT Gateway EIP IDs |
| `nat_eip_public_ips` | List of NAT Gateway EIP public IPs |

### Route Table Outputs

| Name | Description |
|------|-------------|
| `public_route_table_id` | ID of the public route table |
| `private_route_table_ids` | List of private route table IDs |
| `public_route_table_association_ids` | List of public route table association IDs |
| `private_route_table_association_ids` | List of private route table association IDs |

### DNS & Endpoint Outputs

| Name | Description |
|------|-------------|
| `dns_resolver_endpoint_ids` | Map of DNS resolver endpoint IDs |
| `dns_resolver_endpoint_ips` | Map of DNS resolver endpoint IP addresses |
| `vpc_endpoint_ids` | Map of VPC endpoint IDs |
| `vpc_endpoint_dns_names` | Map of VPC endpoint DNS names |
| `gateway_vpc_endpoint_ids` | Map of gateway VPC endpoint IDs |

### Security Group Outputs

| Name | Description |
|------|-------------|
| `security_group_ids` | Map of custom security group IDs |
| `security_group_arns` | Map of custom security group ARNs |
| `dns_resolver_default_security_group_id` | ID of default DNS resolver security group |

### Peering & Flow Log Outputs

| Name | Description |
|------|-------------|
| `vpc_peering_connection_ids` | Map of VPC peering connection IDs |
| `vpc_peering_connection_status` | Map of VPC peering connection status |
| `flow_log_id` | ID of the VPC Flow Log |
| `flow_log_arn` | ARN of the VPC Flow Log |
| `dhcp_options_id` | ID of the DHCP options set |

## Best Practices

### 🏗️ Network Design

- **CIDR Planning**: Use non-overlapping CIDR blocks across VPCs
- **Subnet Sizing**: Plan subnet sizes based on expected resource count
- **Multi-AZ**: Always deploy across multiple availability zones for HA
- **Subnet Types**: Use dedicated subnets for different tiers (web, app, db)

### 🔒 Security

- **Least Privilege**: Configure security groups with minimal required access
- **Network Segmentation**: Use separate subnets for different security zones
- **Flow Logs**: Enable VPC Flow Logs for security monitoring
- **Private Subnets**: Keep application and database tiers in private subnets

### 💰 Cost Optimization

- **NAT Gateway Strategy**: Use single NAT Gateway for dev/test environments
- **VPC Endpoints**: Use gateway endpoints (free) over interface endpoints when possible
- **EIP Management**: Reuse existing EIPs for NAT Gateways
- **Flow Log Filtering**: Log only necessary traffic types to reduce costs

### 🚀 Performance

- **Placement Groups**: Consider placement groups for high-performance computing
- **Enhanced Networking**: Enable enhanced networking for supported instances
- **Local Zones**: Use local zones for ultra-low latency requirements

## Troubleshooting

### Common Issues

**"DNS resolver endpoints require at least 2 subnet IDs"**
- Ensure `dns_resolver_subnet_ids` contains at least 2 subnet IDs
- Subnets must be in different availability zones

**"NAT Gateway creation failed"**
- Verify public subnets exist and have Internet Gateway route
- Check EIP limits in your AWS account
- Ensure subnets are in different AZs for multi-AZ NAT

**"VPC peering connection failed"**
- Verify peer VPC exists and CIDR blocks don't overlap
- Check cross-account/cross-region permissions
- Ensure auto-accept is configured correctly

**"VPC endpoint creation failed"**
- Verify service name is correct for your region
- Check security group allows required traffic
- Ensure subnets are in correct AZs for the service

### Validation Commands

```bash
# Validate Terraform configuration
terraform validate

# Plan with variable validation
terraform plan -var-file="terraform.tfvars"

# Check VPC connectivity
aws ec2 describe-vpcs --vpc-ids vpc-12345678

# Verify DNS resolution
nslookup example.com

# Test NAT Gateway connectivity
curl -I https://aws.amazon.com
```

## Migration Guide

### From Existing VPC Module

1. **Inventory Current Resources**
   ```bash
   terraform state list | grep aws_vpc
   terraform state list | grep aws_subnet
   ```

2. **Import Existing Resources**
   ```bash
   terraform import module.network_hub.aws_vpc.main vpc-12345678
   terraform import module.network_hub.aws_subnet.public[0] subnet-12345678
   ```

3. **Update Configuration**
   - Set `create_vpc = false`
   - Provide existing resource IDs
   - Gradually enable new features

### Version Compatibility

| Module Version | Terraform Version | AWS Provider Version |
|----------------|-------------------|----------------------|
| 1.x.x          | >= 1.3.0          | >= 5.0               |
| 2.x.x          | >= 1.5.0          | >= 5.20              |

## Contributing

See the main repository [CONTRIBUTING.md](../../CONTRIBUTING.md) for guidelines on:
- Code standards and formatting
- Testing requirements
- Documentation updates
- Pull request process

## License

This module is provided under the same license as the parent repository.

---

**Last Updated**: January 2026  
**Module Version**: 1.0.0  
**Terraform Compatibility**: >= 1.3.0  
**AWS Provider Compatibility**: >= 5.0

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 5.0 |
| <a name="provider_null"></a> [null](#provider\_null) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_default_network_acl.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/default_network_acl) | resource |
| [aws_ec2_transit_gateway_vpc_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ec2_transit_gateway_vpc_attachment) | resource |
| [aws_eip.nat](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eip) | resource |
| [aws_flow_log.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/flow_log) | resource |
| [aws_internet_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/internet_gateway) | resource |
| [aws_nat_gateway.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/nat_gateway) | resource |
| [aws_route.peering](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.private_nat_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.public_internet_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route.transit_gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route) | resource |
| [aws_route53_resolver_endpoint.inbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route53_resolver_endpoint.outbound](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_resolver_endpoint) | resource |
| [aws_route_table.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table) | resource |
| [aws_route_table_association.private_existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.private_new](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public_existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_route_table_association.public_new](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route_table_association) | resource |
| [aws_security_group.custom](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group.dns_resolver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_security_group_rule.default_egress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_security_group_rule.default_ingress](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group_rule) | resource |
| [aws_subnet.database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.intra](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_subnet.public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/subnet) | resource |
| [aws_vpc.main](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc) | resource |
| [aws_vpc_endpoint.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_endpoint.interface](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_endpoint) | resource |
| [aws_vpc_ipv4_cidr_block_association.secondary](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv4_cidr_block_association) | resource |
| [aws_vpc_ipv6_cidr_block_association.ipv6](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_ipv6_cidr_block_association) | resource |
| [aws_vpc_peering_connection.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_peering_connection) | resource |
| [null_resource.preconditions](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource) | resource |
| [aws_availability_zones.available](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/availability_zones) | data source |
| [aws_network_acls.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/network_acls) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |
| [aws_security_group.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/security_group) | data source |
| [aws_subnet.existing_database](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnet.existing_private](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_subnet.existing_public](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/subnet) | data source |
| [aws_vpc.existing](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/vpc) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_availability_zones"></a> [availability\_zones](#input\_availability\_zones) | List of availability zones to use for subnets | `list(string)` | <pre>[<br>  "us-east-1a",<br>  "us-east-1b",<br>  "us-east-1c"<br>]</pre> | no |
| <a name="input_create_internet_gateway"></a> [create\_internet\_gateway](#input\_create\_internet\_gateway) | Whether to create an Internet Gateway | `bool` | `true` | no |
| <a name="input_create_private_route_tables"></a> [create\_private\_route\_tables](#input\_create\_private\_route\_tables) | Whether to create private route tables | `bool` | `true` | no |
| <a name="input_create_public_route_table"></a> [create\_public\_route\_table](#input\_create\_public\_route\_table) | Whether to create public route table | `bool` | `true` | no |
| <a name="input_create_subnets"></a> [create\_subnets](#input\_create\_subnets) | Whether to create subnets in the VPC | `bool` | `true` | no |
| <a name="input_create_vpc"></a> [create\_vpc](#input\_create\_vpc) | Whether to create a new VPC. If vpc\_id is provided, this will be ignored. | `bool` | `false` | no |
| <a name="input_database_subnet_ids"></a> [database\_subnet\_ids](#input\_database\_subnet\_ids) | List of existing database subnet IDs to use with existing VPC | `list(string)` | `[]` | no |
| <a name="input_database_subnet_tags"></a> [database\_subnet\_tags](#input\_database\_subnet\_tags) | Additional tags for database subnets | `map(string)` | `{}` | no |
| <a name="input_database_subnets"></a> [database\_subnets](#input\_database\_subnets) | CIDR blocks for database subnets. If list is empty, no database subnets will be created. | `list(string)` | <pre>[<br>  "10.0.21.0/24",<br>  "10.0.22.0/24",<br>  "10.0.23.0/24"<br>]</pre> | no |
| <a name="input_default_network_acl_egress"></a> [default\_network\_acl\_egress](#input\_default\_network\_acl\_egress) | List of egress rules to add to default network ACL | <pre>list(object({<br>    rule_no    = number<br>    action     = string<br>    protocol   = string<br>    from_port  = number<br>    to_port    = number<br>    cidr_block = string<br>  }))</pre> | `[]` | no |
| <a name="input_default_network_acl_ingress"></a> [default\_network\_acl\_ingress](#input\_default\_network\_acl\_ingress) | List of ingress rules to add to default network ACL | <pre>list(object({<br>    rule_no    = number<br>    action     = string<br>    protocol   = string<br>    from_port  = number<br>    to_port    = number<br>    cidr_block = string<br>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_egress"></a> [default\_security\_group\_egress](#input\_default\_security\_group\_egress) | List of egress rules to apply to default security group | <pre>list(object({<br>    description     = optional(string, null)<br>    from_port       = number<br>    to_port         = number<br>    protocol        = string<br>    cidr_blocks     = optional(list(string), [])<br>    security_groups = optional(list(string), [])<br>    self            = optional(bool, false)<br>  }))</pre> | `[]` | no |
| <a name="input_default_security_group_ingress"></a> [default\_security\_group\_ingress](#input\_default\_security\_group\_ingress) | List of ingress rules to apply to default security group | <pre>list(object({<br>    description     = optional(string, null)<br>    from_port       = number<br>    to_port         = number<br>    protocol        = string<br>    cidr_blocks     = optional(list(string), [])<br>    security_groups = optional(list(string), [])<br>    self            = optional(bool, false)<br>  }))</pre> | `[]` | no |
| <a name="input_dns_resolver_security_group_ids"></a> [dns\_resolver\_security\_group\_ids](#input\_dns\_resolver\_security\_group\_ids) | Security group IDs for DNS resolver endpoints | `list(string)` | `[]` | no |
| <a name="input_dns_resolver_subnet_ids"></a> [dns\_resolver\_subnet\_ids](#input\_dns\_resolver\_subnet\_ids) | Subnet IDs for DNS resolver endpoints | `list(string)` | `[]` | no |
| <a name="input_enable_dns_hostnames"></a> [enable\_dns\_hostnames](#input\_enable\_dns\_hostnames) | Whether to enable DNS hostnames in the VPC | `bool` | `true` | no |
| <a name="input_enable_dns_resolver_endpoints"></a> [enable\_dns\_resolver\_endpoints](#input\_enable\_dns\_resolver\_endpoints) | Whether to create inbound and outbound DNS resolver endpoints | `bool` | `false` | no |
| <a name="input_enable_dns_support"></a> [enable\_dns\_support](#input\_enable\_dns\_support) | Whether to enable DNS support in the VPC | `bool` | `true` | no |
| <a name="input_enable_flow_logs"></a> [enable\_flow\_logs](#input\_enable\_flow\_logs) | Whether to enable VPC Flow Logs | `bool` | `false` | no |
| <a name="input_enable_ipv6"></a> [enable\_ipv6](#input\_enable\_ipv6) | Whether to request an IPv6 CIDR block from Amazon | `bool` | `false` | no |
| <a name="input_enable_nat_gateway"></a> [enable\_nat\_gateway](#input\_enable\_nat\_gateway) | Whether to create NAT gateways for private subnets | `bool` | `true` | no |
| <a name="input_enable_network_address_usage_metrics"></a> [enable\_network\_address\_usage\_metrics](#input\_enable\_network\_address\_usage\_metrics) | Whether to enable network address usage metrics | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (e.g., dev, staging, prod) | `string` | `"dev"` | no |
| <a name="input_flow_log_destination_arn"></a> [flow\_log\_destination\_arn](#input\_flow\_log\_destination\_arn) | ARN of the CloudWatch Logs log group or S3 bucket for flow logs | `string` | `null` | no |
| <a name="input_flow_log_destination_type"></a> [flow\_log\_destination\_type](#input\_flow\_log\_destination\_type) | Type of flow log destination (cloud-watch-logs, s3) | `string` | `"cloud-watch-logs"` | no |
| <a name="input_flow_log_iam_role_arn"></a> [flow\_log\_iam\_role\_arn](#input\_flow\_log\_iam\_role\_arn) | ARN of IAM role for flow logs (required for CloudWatch Logs) | `string` | `null` | no |
| <a name="input_flow_log_log_format"></a> [flow\_log\_log\_format](#input\_flow\_log\_log\_format) | The fields to include in the flow log record | `string` | `null` | no |
| <a name="input_flow_log_max_aggregation_interval"></a> [flow\_log\_max\_aggregation\_interval](#input\_flow\_log\_max\_aggregation\_interval) | Maximum interval during which a flow is captured and aggregated into a flow log record | `number` | `600` | no |
| <a name="input_flow_log_traffic_type"></a> [flow\_log\_traffic\_type](#input\_flow\_log\_traffic\_type) | Type of traffic to log (ALL, ACCEPT, REJECT) | `string` | `"ALL"` | no |
| <a name="input_gateway_vpc_endpoints"></a> [gateway\_vpc\_endpoints](#input\_gateway\_vpc\_endpoints) | Map of gateway VPC endpoint configurations | <pre>map(object({<br>    service_name    = string<br>    route_table_ids = list(string)<br>    policy          = optional(string, null)<br>    tags            = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| <a name="input_instance_tenancy"></a> [instance\_tenancy](#input\_instance\_tenancy) | Tenancy option for instances launched into the VPC | `string` | `"default"` | no |
| <a name="input_internet_gateway_id"></a> [internet\_gateway\_id](#input\_internet\_gateway\_id) | ID of existing Internet Gateway to use (for existing VPC) | `string` | `null` | no |
| <a name="input_internet_gateway_tags"></a> [internet\_gateway\_tags](#input\_internet\_gateway\_tags) | Additional tags for internet gateway | `map(string)` | `{}` | no |
| <a name="input_intra_subnet_ids"></a> [intra\_subnet\_ids](#input\_intra\_subnet\_ids) | List of existing intra subnet IDs to use with existing VPC | `list(string)` | `[]` | no |
| <a name="input_intra_subnet_tags"></a> [intra\_subnet\_tags](#input\_intra\_subnet\_tags) | Additional tags for intra subnets | `map(string)` | `{}` | no |
| <a name="input_intra_subnets"></a> [intra\_subnets](#input\_intra\_subnets) | CIDR blocks for intra subnets. If list is empty, no intra subnets will be created. | `list(string)` | `[]` | no |
| <a name="input_manage_default_network_acl"></a> [manage\_default\_network\_acl](#input\_manage\_default\_network\_acl) | Whether to manage default network ACL rules | `bool` | `false` | no |
| <a name="input_map_public_ip_on_launch"></a> [map\_public\_ip\_on\_launch](#input\_map\_public\_ip\_on\_launch) | Whether to auto-assign public IP on EC2 launch in public subnets | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | Name prefix for all resources | `string` | n/a | yes |
| <a name="input_nat_gateway_destination_cidr_block"></a> [nat\_gateway\_destination\_cidr\_block](#input\_nat\_gateway\_destination\_cidr\_block) | The destination CIDR block for NAT gateway routes (defaults to 0.0.0.0/0 for internet access) | `string` | `"0.0.0.0/0"` | no |
| <a name="input_nat_gateway_eip_ids"></a> [nat\_gateway\_eip\_ids](#input\_nat\_gateway\_eip\_ids) | List of existing Elastic IP IDs to attach to NAT gateways | `list(string)` | `[]` | no |
| <a name="input_nat_gateway_subnet_ids"></a> [nat\_gateway\_subnet\_ids](#input\_nat\_gateway\_subnet\_ids) | List of subnet IDs where NAT gateways should be created (for existing VPC) | `list(string)` | `[]` | no |
| <a name="input_nat_gateway_tags"></a> [nat\_gateway\_tags](#input\_nat\_gateway\_tags) | Additional tags for NAT gateways | `map(string)` | `{}` | no |
| <a name="input_one_nat_gateway_per_az"></a> [one\_nat\_gateway\_per\_az](#input\_one\_nat\_gateway\_per\_az) | Whether to create one NAT gateway per availability zone | `bool` | `true` | no |
| <a name="input_private_route_table_ids"></a> [private\_route\_table\_ids](#input\_private\_route\_table\_ids) | List of existing private route table IDs (for existing VPC) | `list(string)` | `[]` | no |
| <a name="input_private_route_table_tags"></a> [private\_route\_table\_tags](#input\_private\_route\_table\_tags) | Additional tags for private route tables | `map(string)` | `{}` | no |
| <a name="input_private_routes"></a> [private\_routes](#input\_private\_routes) | List of additional routes to add to private route tables | <pre>list(object({<br>    route_table_id            = string<br>    destination_cidr_block    = optional(string, null)<br>    gateway_id                = optional(string, null)<br>    nat_gateway_id            = optional(string, null)<br>    vpc_endpoint_id           = optional(string, null)<br>    transit_gateway_id        = optional(string, null)<br>    vpc_peering_connection_id = optional(string, null)<br>  }))</pre> | `[]` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | List of existing private subnet IDs to use with existing VPC | `list(string)` | `[]` | no |
| <a name="input_private_subnet_tags"></a> [private\_subnet\_tags](#input\_private\_subnet\_tags) | Additional tags for private subnets | `map(string)` | `{}` | no |
| <a name="input_private_subnets"></a> [private\_subnets](#input\_private\_subnets) | CIDR blocks for private subnets. If list is empty, no private subnets will be created. | `list(string)` | <pre>[<br>  "10.0.11.0/24",<br>  "10.0.12.0/24",<br>  "10.0.13.0/24"<br>]</pre> | no |
| <a name="input_public_route_table_ids"></a> [public\_route\_table\_ids](#input\_public\_route\_table\_ids) | List of existing public route table IDs (for existing VPC) | `list(string)` | `[]` | no |
| <a name="input_public_route_table_tags"></a> [public\_route\_table\_tags](#input\_public\_route\_table\_tags) | Additional tags for public route tables | `map(string)` | `{}` | no |
| <a name="input_public_routes"></a> [public\_routes](#input\_public\_routes) | List of additional routes to add to public route tables | <pre>list(object({<br>    route_table_id            = string<br>    destination_cidr_block    = optional(string, null)<br>    gateway_id                = optional(string, null)<br>    nat_gateway_id            = optional(string, null)<br>    vpc_endpoint_id           = optional(string, null)<br>    transit_gateway_id        = optional(string, null)<br>    vpc_peering_connection_id = optional(string, null)<br>  }))</pre> | `[]` | no |
| <a name="input_public_subnet_ids"></a> [public\_subnet\_ids](#input\_public\_subnet\_ids) | List of existing public subnet IDs to use with existing VPC | `list(string)` | `[]` | no |
| <a name="input_public_subnet_tags"></a> [public\_subnet\_tags](#input\_public\_subnet\_tags) | Additional tags for public subnets | `map(string)` | `{}` | no |
| <a name="input_public_subnets"></a> [public\_subnets](#input\_public\_subnets) | CIDR blocks for public subnets. If list is empty, no public subnets will be created. | `list(string)` | <pre>[<br>  "10.0.1.0/24",<br>  "10.0.2.0/24",<br>  "10.0.3.0/24"<br>]</pre> | no |
| <a name="input_secondary_cidr_blocks"></a> [secondary\_cidr\_blocks](#input\_secondary\_cidr\_blocks) | List of secondary IPv4 CIDR blocks to associate with the VPC | `list(string)` | `[]` | no |
| <a name="input_security_groups"></a> [security\_groups](#input\_security\_groups) | Map of security group configurations to create | <pre>map(object({<br>    name        = optional(string, null)<br>    description = string<br>    ingress_rules = optional(list(object({<br>      description      = optional(string, null)<br>      from_port        = number<br>      to_port          = number<br>      protocol         = string<br>      cidr_blocks      = optional(list(string), [])<br>      ipv6_cidr_blocks = optional(list(string), [])<br>      prefix_list_ids  = optional(list(string), [])<br>      security_groups  = optional(list(string), [])<br>      self             = optional(bool, false)<br>    })), [])<br>    egress_rules = optional(list(object({<br>      description      = optional(string, null)<br>      from_port        = number<br>      to_port          = number<br>      protocol         = string<br>      cidr_blocks      = optional(list(string), [])<br>      ipv6_cidr_blocks = optional(list(string), [])<br>      prefix_list_ids  = optional(list(string), [])<br>      security_groups  = optional(list(string), [])<br>      self             = optional(bool, false)<br>    })), [])<br>    tags = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| <a name="input_single_nat_gateway"></a> [single\_nat\_gateway](#input\_single\_nat\_gateway) | Whether to create a single shared NAT gateway across all AZs | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_transit_gateway_id"></a> [transit\_gateway\_id](#input\_transit\_gateway\_id) | ID of Transit Gateway to attach VPC to | `string` | `null` | no |
| <a name="input_transit_gateway_routes"></a> [transit\_gateway\_routes](#input\_transit\_gateway\_routes) | Routes to add through transit gateway | <pre>list(object({<br>    destination_cidr_block = string<br>    route_table_ids        = list(string)<br>  }))</pre> | `[]` | no |
| <a name="input_vpc_cidr_block"></a> [vpc\_cidr\_block](#input\_vpc\_cidr\_block) | CIDR block for the new VPC (required if creating new VPC) | `string` | `"10.0.0.0/16"` | no |
| <a name="input_vpc_endpoints"></a> [vpc\_endpoints](#input\_vpc\_endpoints) | Map of VPC endpoint configurations | <pre>map(object({<br>    service_name        = string<br>    vpc_endpoint_type   = optional(string, "Interface")<br>    private_dns_enabled = optional(bool, true)<br>    security_group_ids  = optional(list(string), [])<br>    subnet_ids          = optional(list(string), [])<br>    route_table_ids     = optional(list(string), [])<br>    policy              = optional(string, null)<br>    tags                = optional(map(string), {})<br>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of an existing VPC to use. If not provided, a new VPC will be created. | `string` | `null` | no |
| <a name="input_vpc_peerings"></a> [vpc\_peerings](#input\_vpc\_peerings) | Map of VPC peering connections to create | <pre>map(object({<br>    peer_vpc_id     = string<br>    peer_owner_id   = optional(string, null)<br>    peer_region     = optional(string, null)<br>    auto_accept     = optional(bool, true)<br>    route_table_ids = optional(list(string), [])<br>    tags            = optional(map(string), {})<br>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_availability_zones"></a> [availability\_zones](#output\_availability\_zones) | List of availability zones used |
| <a name="output_complete"></a> [complete](#output\_complete) | Complete configuration of the network module |
| <a name="output_database_subnet_ids"></a> [database\_subnet\_ids](#output\_database\_subnet\_ids) | List of database subnet IDs |
| <a name="output_dns_resolver_endpoint_ids"></a> [dns\_resolver\_endpoint\_ids](#output\_dns\_resolver\_endpoint\_ids) | Map of DNS resolver endpoint IDs |
| <a name="output_flow_log_id"></a> [flow\_log\_id](#output\_flow\_log\_id) | The ID of the flow log |
| <a name="output_gateway_vpc_endpoint_ids"></a> [gateway\_vpc\_endpoint\_ids](#output\_gateway\_vpc\_endpoint\_ids) | Map of gateway VPC endpoint IDs |
| <a name="output_internet_gateway_id"></a> [internet\_gateway\_id](#output\_internet\_gateway\_id) | The ID of the Internet Gateway |
| <a name="output_intra_subnet_ids"></a> [intra\_subnet\_ids](#output\_intra\_subnet\_ids) | List of intra subnet IDs |
| <a name="output_nat_eip_ids"></a> [nat\_eip\_ids](#output\_nat\_eip\_ids) | List of Elastic IP IDs for NAT Gateways |
| <a name="output_nat_gateway_ids"></a> [nat\_gateway\_ids](#output\_nat\_gateway\_ids) | List of NAT Gateway IDs |
| <a name="output_private_route_table_ids"></a> [private\_route\_table\_ids](#output\_private\_route\_table\_ids) | List of private route table IDs |
| <a name="output_private_subnet_cidrs"></a> [private\_subnet\_cidrs](#output\_private\_subnet\_cidrs) | List of private subnet CIDR blocks |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | List of private subnet IDs |
| <a name="output_public_route_table_ids"></a> [public\_route\_table\_ids](#output\_public\_route\_table\_ids) | List of public route table IDs |
| <a name="output_public_subnet_cidrs"></a> [public\_subnet\_cidrs](#output\_public\_subnet\_cidrs) | List of public subnet CIDR blocks |
| <a name="output_public_subnet_ids"></a> [public\_subnet\_ids](#output\_public\_subnet\_ids) | List of public subnet IDs |
| <a name="output_security_group_ids"></a> [security\_group\_ids](#output\_security\_group\_ids) | Map of security group IDs |
| <a name="output_transit_gateway_attachment_id"></a> [transit\_gateway\_attachment\_id](#output\_transit\_gateway\_attachment\_id) | The ID of the transit gateway attachment |
| <a name="output_vpc_arn"></a> [vpc\_arn](#output\_vpc\_arn) | The ARN of the VPC |
| <a name="output_vpc_cidr_block"></a> [vpc\_cidr\_block](#output\_vpc\_cidr\_block) | The CIDR block of the VPC |
| <a name="output_vpc_default_security_group_id"></a> [vpc\_default\_security\_group\_id](#output\_vpc\_default\_security\_group\_id) | The ID of the default security group |
| <a name="output_vpc_endpoint_ids"></a> [vpc\_endpoint\_ids](#output\_vpc\_endpoint\_ids) | Map of VPC endpoint IDs |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | The ID of the VPC |
| <a name="output_vpc_peering_connection_ids"></a> [vpc\_peering\_connection\_ids](#output\_vpc\_peering\_connection\_ids) | Map of VPC peering connection IDs |
<!-- END_TF_DOCS -->