# network-hub

Terraform module for AWS VPC networking. Creates or adopts a VPC, lays out
subnets across availability zones, wires the usual gateways and route tables,
and exposes a consistent set of outputs that downstream modules can key off.

Designed for hub-and-spoke topologies and on-prem-to-AWS migrations where a
Transit Gateway or Cloud WAN sits in the middle.

## What you get

- New VPC or adoption of an existing one (`create_vpc` vs `vpc_id`).
- Five subnet tiers, each optional: `public`, `private`, `database`, `intra`,
  `transit`.
- NAT gateways (one per AZ, one shared, or none).
- Internet gateway, with the public route table pointed at it.
- Per-tier route tables and associations.
- VPC endpoints (interface and gateway).
- Custom security groups and optional management of the VPC default SG/NACL.
- VPC flow logs (caller supplies the destination).
- Route 53 Resolver endpoints for hybrid DNS.
- VPC peering connections with per-route-table propagation.
- Transit Gateway VPC attachment with TGW-side routes.

## Subnet tiers

| Tier | Default route | Typical residents |
|---|---|---|
| `public` | IGW | ALBs, NAT gateways, bastions |
| `private` | NAT | Workloads (EKS nodes, EC2, ECS tasks) |
| `database` | none | RDS, ElastiCache, MemoryDB |
| `intra` | none | VPC endpoint ENIs, internal LBs, EKS control-plane ENIs |
| `transit` | none | TGW / Cloud WAN attachment ENIs |

Each tier is enabled by providing one CIDR per AZ. Passing an empty list
disables the tier.

### Why `transit` subnets matter for hybrid

When you attach a VPC to a Transit Gateway (or Cloud WAN), AWS places ENIs
in the subnets you nominate. AWS' recommendation (and common production
practice) is to keep those ENIs in a dedicated tier:

- Keeps on-prem routing decisions off workload route tables.
- Lets you scope NACLs / SGs tightly to TGW traffic patterns.
- A `/28` per AZ is enough; AWS reserves 5 addresses and the attachment uses
  one ENI per AZ.

When `transit_subnets` is populated, the module wires the TGW attachment into
them automatically. If left empty, it falls back to private subnets so
simple deployments still work.

## Quick start

```hcl
module "hub" {
  source = "git::https://github.com/your-org/tf-modules.git//modules/network-hub"

  name       = "hub-prod"
  create_vpc = true

  environment = "prod"
  tags = {
    Project    = "platform"
    Team       = "network"
    CostCenter = "NET-001"
  }

  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  public_subnets   = ["10.0.0.0/24",  "10.0.1.0/24",  "10.0.2.0/24"]
  private_subnets  = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  database_subnets = ["10.0.64.0/24", "10.0.65.0/24", "10.0.66.0/24"]
  intra_subnets    = ["10.0.80.0/24", "10.0.81.0/24", "10.0.82.0/24"]
  transit_subnets  = ["10.0.96.0/28", "10.0.96.16/28", "10.0.96.32/28"]

  enable_nat_gateway     = true
  one_nat_gateway_per_az = true

  enable_flow_logs          = true
  flow_log_destination_arn  = aws_s3_bucket.flow_logs.arn
  flow_log_destination_type = "s3"
}
```

## Hybrid connectivity (TGW / Cloud WAN)

```hcl
module "hub" {
  source = "git::https://github.com/your-org/tf-modules.git//modules/network-hub"

  name       = "hub-prod"
  create_vpc = true

  vpc_cidr_block     = "10.0.0.0/16"
  availability_zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]

  private_subnets = ["10.0.16.0/20", "10.0.32.0/20", "10.0.48.0/20"]
  intra_subnets   = ["10.0.80.0/24", "10.0.81.0/24", "10.0.82.0/24"]
  transit_subnets = ["10.0.96.0/28", "10.0.96.16/28", "10.0.96.32/28"]

  transit_gateway_id = "tgw-0123456789abcdef0"

  # Route the on-prem corp CIDR from private + intra RTs toward the TGW.
  # The module expands this across every listed route table.
  transit_gateway_routes = [
    {
      destination_cidr_block = "172.16.0.0/12"
      route_table_ids        = concat(
        module.hub.private_route_table_ids,
        [module.hub.intra_route_table_id],
      )
    },
  ]
}
```

## Adopting an existing VPC

```hcl
module "hub" {
  source = "git::https://github.com/your-org/tf-modules.git//modules/network-hub"

  name   = "hub-existing"
  vpc_id = "vpc-0abc123def456789"

  public_subnet_ids   = ["subnet-a1", "subnet-a2", "subnet-a3"]
  private_subnet_ids  = ["subnet-b1", "subnet-b2", "subnet-b3"]
  database_subnet_ids = ["subnet-c1", "subnet-c2", "subnet-c3"]

  # No IGW / NAT creation; the module won't try to create route tables for
  # tiers you didn't pass subnet IDs for.
  create_internet_gateway     = false
  enable_nat_gateway          = false
  create_public_route_table   = false
  create_private_route_tables = false
}
```

## Inputs reference

### Identity

| Name | Type | Default | Notes |
|---|---|---|---|
| `name` | `string` | *(required)* | Prefix for every resource. |
| `environment` | `string` | `"dev"` | Emitted as `Environment` tag. |
| `tags` | `map(string)` | `{}` | Merged onto every resource. |

### VPC

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_id` | `string` | `null` | Adopt an existing VPC instead of creating one. |
| `create_vpc` | `bool` | `false` | Required when `vpc_id = null`. |
| `vpc_cidr_block` | `string` | `"10.0.0.0/16"` | Primary CIDR. |
| `secondary_cidr_blocks` | `list(string)` | `[]` | Extra IPv4 blocks. |
| `enable_ipv6` | `bool` | `false` | Requests an Amazon-provided /56. |
| `instance_tenancy` | `string` | `"default"` | `default` or `dedicated`. |
| `enable_dns_support` | `bool` | `true` | |
| `enable_dns_hostnames` | `bool` | `true` | |
| `enable_network_address_usage_metrics` | `bool` | `false` | |

### Subnets

| Name | Type | Default | Notes |
|---|---|---|---|
| `availability_zones` | `list(string)` | 3 in us-east-1 | One CIDR per AZ per tier. |
| `create_subnets` | `bool` | `true` | Disable to keep subnets outside the module. |
| `public_subnets` / `private_subnets` / `database_subnets` / `intra_subnets` / `transit_subnets` | `list(string)` | various / `[]` | Per-tier CIDRs. |
| `*_subnet_ids` | `list(string)` | `[]` | Existing subnet ids when adopting a VPC. |
| `*_subnet_tags` | `map(string)` | `{}` | Extra per-tier tags. |
| `map_public_ip_on_launch` | `bool` | `true` | Applies to public subnets. |

### NAT

| Name | Type | Default | Notes |
|---|---|---|---|
| `enable_nat_gateway` | `bool` | `true` | |
| `single_nat_gateway` | `bool` | `false` | Cheaper, no HA. |
| `one_nat_gateway_per_az` | `bool` | `true` | Default HA layout. |
| `nat_gateway_subnet_ids` | `list(string)` | `[]` | Override which subnets host NATs. |
| `nat_gateway_eip_ids` | `list(string)` | `[]` | Reuse pre-allocated EIPs. |
| `nat_gateway_destination_cidr_block` | `string` | `"0.0.0.0/0"` | Private RT default route destination. |

### Internet gateway

| Name | Type | Default | Notes |
|---|---|---|---|
| `internet_gateway_id` | `string` | `null` | Adopt an existing IGW. |
| `create_internet_gateway` | `bool` | `true` | |

### Route tables

| Name | Type | Default | Notes |
|---|---|---|---|
| `create_public_route_table` | `bool` | `true` | |
| `create_private_route_tables` | `bool` | `true` | One per AZ. |
| `create_database_route_table` | `bool` | `true` | Shared, no default route. |
| `create_intra_route_table` | `bool` | `true` | Shared, no default route. |
| `create_transit_route_table` | `bool` | `true` | Shared, no default route. |
| `public_routes` / `private_routes` | list of objects | `[]` | Extra routes to install. |

### VPC endpoints

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_endpoints` | `map(object(...))` | `{}` | Interface endpoints. |
| `gateway_vpc_endpoints` | `map(object(...))` | `{}` | Gateway endpoints (S3/DDB). |

### Security groups

| Name | Type | Default | Notes |
|---|---|---|---|
| `security_groups` | `map(object(...))` | `{}` | Custom SGs. |
| `manage_default_security_group` | `bool` | `false` | Adopt + restrict the default SG. |
| `default_security_group_ingress` / `default_security_group_egress` | list of objects | `[]` | Rules applied when managed. |

### Flow logs

| Name | Type | Default | Notes |
|---|---|---|---|
| `enable_flow_logs` | `bool` | `false` | |
| `flow_log_destination_type` | `string` | `"cloud-watch-logs"` | `cloud-watch-logs`, `s3`, or `kinesis-data-firehose`. |
| `flow_log_destination_arn` | `string` | `null` | Caller-owned destination. |
| `flow_log_iam_role_arn` | `string` | `null` | Required for CW Logs destination. |
| `flow_log_traffic_type` | `string` | `"ALL"` | `ALL`, `ACCEPT`, `REJECT`. |
| `flow_log_log_format` | `string` | `null` | Custom format; null uses AWS default. |
| `flow_log_max_aggregation_interval` | `number` | `600` | 60 or 600. |

### DNS resolver

| Name | Type | Default | Notes |
|---|---|---|---|
| `enable_dns_resolver_endpoints` | `bool` | `false` | |
| `dns_resolver_subnet_ids` | `list(string)` | `[]` | At least two AZs. |
| `dns_resolver_security_group_ids` | `list(string)` | `[]` | Module builds a permissive demo SG when empty. |

### Default NACL

| Name | Type | Default | Notes |
|---|---|---|---|
| `manage_default_network_acl` | `bool` | `false` | |
| `default_network_acl_ingress` / `default_network_acl_egress` | list of objects | `[]` | |

### VPC peering

| Name | Type | Default | Notes |
|---|---|---|---|
| `vpc_peerings` | `map(object(...))` | `{}` | Key is used in the resource name. |

### Transit Gateway

| Name | Type | Default | Notes |
|---|---|---|---|
| `transit_gateway_id` | `string` | `null` | Null disables the attachment. |
| `transit_gateway_attachment_subnet_ids` | `list(string)` | `null` | Explicit override. Defaults to transit subnets, then private. |
| `transit_gateway_appliance_mode` | `string` | `"disable"` | Enable for stateful inspection appliances. |
| `transit_gateway_dns_support` | `string` | `"enable"` | |
| `transit_gateway_ipv6_support` | `string` | `"disable"` | |
| `transit_gateway_routes` | list of objects | `[]` | Each entry expands across `route_table_ids`. |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` / `vpc_cidr_block` / `vpc_arn` | The VPC |
| `vpc_default_security_group_id` | Default SG (when managed or created) |
| `public_subnet_ids` / `*_subnet_ids` | Per-tier subnet ids |
| `public_subnet_cidrs` / `*_subnet_cidrs` | Per-tier CIDR blocks |
| `internet_gateway_id` | IGW id |
| `nat_gateway_ids` / `nat_eip_ids` | NAT resources |
| `public_route_table_ids` / `private_route_table_ids` | Route tables |
| `database_route_table_id` / `intra_route_table_id` / `transit_route_table_id` | Single-entry RTs |
| `security_group_ids` | Map of custom SG ids |
| `vpc_endpoint_ids` / `gateway_vpc_endpoint_ids` | Endpoint ids |
| `flow_log_id` | Flow log id |
| `dns_resolver_endpoint_ids` | Inbound / outbound resolver ids |
| `vpc_peering_connection_ids` | Peering ids |
| `transit_gateway_attachment_id` | TGW attachment id |
| `transit_gateway_attachment_subnet_ids` | Subnets the TGW attachment landed in |
| `availability_zones` | AZ list actually used |
| `summary` | Flattened object suitable for downstream modules |

## Design notes

**Why two existing-VPC paths?** The module supports both creating a VPC and
adopting one. Adoption is common in migrations where the VPC was provisioned
by CloudFormation / a previous Terraform state and the network team now
wants to add things like route tables and endpoints around it without
re-creating the VPC itself.

**Why five subnet tiers?** Four is the common pattern (public / private /
database / intra). The fifth tier, `transit`, carries the TGW or Cloud WAN
attachment ENIs. Isolating them simplifies NACLs, makes route tables easier
to reason about, and avoids mistakes where someone adds a workload route to
the attachment's subnet.

**Why per-AZ private route tables?** So you can route each private subnet's
NAT traffic to the NAT gateway that lives in the same AZ. Cross-AZ NAT adds
real money at scale (AWS charges for inter-AZ data transfer twice - once
from the source AZ and once back from NAT's AZ).

**Why `check` blocks instead of a `null_resource`?** Modern Terraform
supports top-level `check` blocks for module-wide preconditions. They run at
plan time, don't create state, and produce cleaner error output than the
null_resource trick.

**Custom SGs use inline rules.** The AWS provider supports both inline
ingress/egress on `aws_security_group` and separate
`aws_vpc_security_group_{ingress,egress}_rule` resources. Inline rules keep
the module interface compact; for very large rule sets that change
frequently, manage them as separate resources outside the module to avoid
destructive rule replacement on updates.

## Requirements

- Terraform `>= 1.5.0` (needs `check` blocks)
- AWS provider `~> 5.0`
