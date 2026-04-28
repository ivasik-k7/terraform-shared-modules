# aws-lending-vpc

Opinionated VPC module for the migration factory. Built around fully isolated
landing-zone VPCs that connect outwards through a Transit Gateway and inwards
through VPC endpoints. Same module powers greenfield landing zones and
"adopt-an-existing-VPC" wraparounds.

This is the successor to the previous `network-hub` module. Renamed because
the use case is no longer a centralised hub — it's a per-application VPC that
is *lent* to a workload during migration, with TGW + endpoints providing the
connectivity.

## Why this module exists

Migration factories need to produce VPCs at speed. Every wave brings the same
boilerplate:

- Carve a /16 into 4-5 tiers across 3 AZs.
- Wire IGW + per-AZ NAT.
- Glue S3 + DynamoDB gateway endpoints onto private route tables.
- Add the standard SSM / ECR / Secrets Manager interface endpoint set.
- Attach to the central TGW.
- Push on-prem CIDR routes from the right tiers.
- Apply FinOps tags so cost reporting works.

Doing all of that with raw `aws_*` resources turns into 400 lines of YAML or
HCL per VPC and gets copy-pasted across waves. This module collapses it to
~30 lines and removes the most common foot-guns.

## What you get

| Surface | Behaviour |
|---|---|
| **VPC** | Create or adopt. Adoption skips VPC/subnet creation and only adds the things you ask for (endpoints, flow logs, TGW attachment, ...). |
| **Subnets** | Five tiers — `public`, `private`, `database`, `intra`, `transit`. Each tier optional. Auto-carved from the VPC CIDR if you opt in. |
| **NAT** | One per AZ by default. Can collapse to one shared NAT (cheap, no HA) or be skipped entirely (central-egress topologies). |
| **IGW + Route tables** | Per-AZ private RTs, shared public/database/intra/transit RTs. Database/intra/transit get no default route. |
| **VPC endpoints** | Region-aware: pass `"ssm"` and the module produces `com.amazonaws.<region>.ssm`. Built-in default 443-from-VPC SG. Endpoint presets (`interface_endpoint_services = ["ssm","ssmmessages","ec2messages"]`) for one-line common bundles. |
| **Security groups** | Custom SG map + inter-tier rule helper for the recurring "app talks to db on 5432" pattern. |
| **Default SG / NACL** | Optional adoption + lockdown. Loud warnings about destructive replacement. |
| **Flow logs** | Caller owns destination + role. CW Logs / S3 / Firehose. |
| **Hybrid DNS** | Inbound + outbound Route 53 Resolver endpoints. Auto-picks subnets from intra/private. |
| **Peering** | Requester-side connections + return routes. Cross-account/region accepter is your job. |
| **Transit Gateway** | VPC attachment lives in the dedicated `transit` tier when present. Falls back to private. Routes expand across multiple route tables in one input. |
| **FinOps tags** | Optional plan-time enforcement of `Project / Team / CostCenter / Owner`. |

## Quick start — landing zone with auto-carve

```hcl
module "vpc" {
  source = "git::https://github.com/your-org/tf-modules.git//modules/aws-lending-vpc"

  name        = "wave3-payments"
  environment = "prod"
  create_vpc  = true

  vpc_cidr_block      = "10.40.0.0/16"
  auto_carve_subnets  = true   # public/private/db/intra/transit auto-sliced
  enforce_finops_tags = true

  tags = {
    Project    = "migration-wave-3"
    Team       = "payments"
    CostCenter = "PAY-001"
    Owner      = "payments-platform@acme.io"
  }

  # Common SSM + ECR endpoint set, one-liner.
  interface_endpoint_services = ["ssm", "ssmmessages", "ec2messages", "ecr.api", "ecr.dkr", "logs", "secretsmanager"]
  gateway_endpoint_services   = ["s3", "dynamodb"]

  # On-prem connectivity via the central TGW.
  transit_gateway_id = "tgw-0abc...."
  transit_gateway_routes = [{
    destination_cidr_block = "172.16.0.0/12"
    route_table_ids        = concat(module.vpc.private_route_table_ids, [module.vpc.intra_route_table_id])
  }]

  # Lock the default SG.
  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}
```

That's it. You get a 3-AZ /16, per-AZ NAT, /20 subnets per tier, /28 transit
subnets, an IGW, the standard SSM/ECR endpoint set, S3 + DDB gateway endpoints
on private + intra RTs, a default endpoint SG with 443-from-VPC, the TGW
attachment, on-prem routes from private + intra RTs, and a stripped default SG.

## Subnet tiers

| Tier | Default route | What lives here |
|---|---|---|
| `public` | IGW | ALBs, NAT gateways, bastions |
| `private` | NAT | EKS nodes, ECS tasks, EC2 workloads |
| `database` | none | RDS, ElastiCache, MemoryDB |
| `intra` | none | VPC endpoint ENIs, EKS control-plane ENIs, internal LBs |
| `transit` | none | TGW / Cloud WAN attachment ENIs |

Each tier is enabled by giving it CIDRs (or by setting `auto_carve_subnets = true`).
Empty list disables the tier and the route table for it.

### Why a dedicated `transit` tier matters

Putting the TGW attachment on workload subnets works, but mixes on-prem routing
decisions into the workload route tables. Keep them separate:

- The transit RT stays empty — TGW propagation lives at the TGW route table itself.
- Workload RTs only carry `0.0.0.0/0 -> NAT` and the on-prem routes you explicitly install.
- NACLs scoped to TGW traffic don't have to allow workload patterns.
- A `/28` per AZ is enough — AWS reserves 5 IPs and the attachment uses one ENI per AZ.

If `transit_subnets` (or auto-carve) is empty, the module quietly falls back to
private subnets so the simple case still works. But for hybrid prod, give it
the dedicated tier.

## Hidden gotchas this module already handles

| Gotcha | What the module does |
|---|---|
| Cross-AZ NAT data charges | Per-AZ private route tables and per-AZ NATs by default; modulo math collapses correctly when you flip `single_nat_gateway = true`. |
| Interface endpoint with no SG | Auto-creates a default SG (443/tcp from VPC CIDR + extras). Endpoints without a caller-supplied SG attach to it. |
| Region-prefix typos in `service_name` | Pass short names (`"ssm"`); the module prefixes them with `com.amazonaws.<region>`. Full names also pass through. |
| Private DNS needs DNS support + hostnames | Both are on by default. If you turn either off the endpoint will silently lose private DNS. |
| Multiple endpoints for one service in one VPC with private DNS on | AWS rejects the second. Set `private_dns_enabled = false` on the duplicate. |
| Flow logs to CW Logs without an IAM role | Plan-time check fails with a readable message. Same for missing destination ARN. |
| TGW attachment race on first apply | Routes pointing at the TGW depend on the attachment explicitly. |
| TGW attachment subnet count | Plan-time check requires at least one subnet; in practice you want one per AZ. |
| DNS resolver endpoint AZ count | AWS requires 2; module picks intra/private subnets when you don't pass any, and the check{} block fails fast if neither has 2. |
| FinOps tag drift | Optional `enforce_finops_tags = true` blocks the plan if `Project/Team/CostCenter/Owner` are missing. |
| `manage_default_security_group` is destructive | Documented loudly; no surprise overrides — explicit opt-in only. |
| `manage_default_network_acl` with empty rules locks the VPC | Documented loudly; intentional behavior for "deny everything" use case. |
| Skipping NAT default route | `skip_private_nat_default_route = true` for central-egress topologies. |
| AZ list non-determinism | The module sorts AZ names so plans stay stable. |

## Auto-carve details

When `auto_carve_subnets = true`, the module slices the VPC CIDR via
`cidrsubnet`:

```
VPC = 10.0.0.0/16, subnet_newbits = 4 (default)

public[0]   = 10.0.0.0/20   (offset 0)
public[1]   = 10.0.16.0/20
public[2]   = 10.0.32.0/20
private[0]  = 10.0.64.0/20  (offset 4)
private[1]  = 10.0.80.0/20
private[2]  = 10.0.96.0/20
database[0] = 10.0.128.0/20 (offset 8)
intra[0]    = 10.0.192.0/20 (offset 12)
transit[0]  = 10.0.240.0/28 (last /20 sliced to /28; offset 15)
transit[1]  = 10.0.240.16/28
transit[2]  = 10.0.240.32/28
```

Cap of 4 AZs in auto-carve mode. Need 5+ AZs? Pass explicit CIDR lists.

## Common recipes

### One-liner endpoint sets

```hcl
interface_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]   # Session Manager
interface_endpoint_services = ["ecr.api", "ecr.dkr", "logs"]           # ECS image pulls
interface_endpoint_services = ["sts", "secretsmanager", "kms"]         # IAM-heavy
gateway_endpoint_services   = ["s3", "dynamodb"]                       # Cost-saver
```

### Tier-to-tier SG rules without writing rule objects

```hcl
security_groups = {
  app = { description = "App tier" }
  db  = { description = "DB tier" }
  alb = { description = "ALB"     }
}

inter_tier_rules = [
  { from = "alb", to = "app", from_port = 8080, to_port = 8080 },
  { from = "app", to = "db",  from_port = 5432, to_port = 5432 },
]
```

### Adopt an existing VPC and just add endpoints

```hcl
module "vpc" {
  source = "git::...//modules/aws-lending-vpc"

  name   = "legacy-app"
  vpc_id = "vpc-0abc...."

  create_subnets              = false
  create_internet_gateway     = false
  enable_nat_gateway          = false
  create_public_route_table   = false
  create_private_route_tables = false
  create_database_route_table = false
  create_intra_route_table    = false
  create_transit_route_table  = false

  intra_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]

  interface_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]
}
```

### Central-egress topology (no NAT here, egress via TGW)

```hcl
enable_nat_gateway              = false
skip_private_nat_default_route  = true
transit_gateway_id              = "tgw-0abc...."
transit_gateway_routes = [{
  destination_cidr_block = "0.0.0.0/0"
  route_table_ids        = module.vpc.private_route_table_ids
}]
```

## Outputs that downstream modules actually want

```hcl
module "ecs_workload" {
  source = ".../landing-ecs"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
  network    = module.vpc.network            # all-in-one for richer wiring
}
```

`module.vpc.subnets_by_az["eu-west-1a"].private` is also exposed for callers
that need AZ-specific subnet ids without index math.

## Inputs reference

See `variables.tf` — every input has a description that calls out the gotcha
where there is one. Highlights:

- `auto_carve_subnets` — flip on for migration factory speed
- `interface_endpoint_services` / `gateway_endpoint_services` — short bundles
- `inter_tier_rules` — declarative SG-to-SG allow rules
- `enforce_finops_tags` — plan fails if Project/Team/CostCenter/Owner missing
- `skip_private_nat_default_route` — central-egress mode
- `single_nat_gateway` — dev/test only; never prod

## Outputs reference

See `outputs.tf`. Highlights:

- `network` — single consolidated object for downstream module wiring
- `subnets_by_az` — `{ az => { tier => subnet_id } }`
- `nat_public_ips` — for on-prem firewall allowlists
- `endpoint_security_group_id` — when you want to add extra rules to the default
- `summary` — DEPRECATED, kept for callers migrating from the old module

## Requirements

- Terraform `>= 1.5.0` (uses `check{}` blocks and `optional()` with defaults)
- AWS provider `~> 5.0`
