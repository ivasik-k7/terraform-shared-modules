# Load Balancer

A universal, highly configurable Terraform module for **Elastic Load Balancing** —
Application (ALB) and Network (NLB) load balancers. It is deliberately
**consumer-agnostic**: it builds the load balancer, target groups, listeners,
listener rules, certificates, edge authentication, and an optional security
group, and exposes target-group ARNs by key so *anything* can attach to them —
ECS services, EKS `TargetGroupBinding`s (AWS Load Balancer Controller),
self-managed EC2/Kubernetes NodePorts, Lambda, or static IPs.

> Gateway Load Balancers (GWLB) are intentionally **out of scope** — they have a
> distinct GENEVE/endpoint-service model that is better served by a dedicated
> module than by half-supporting it here.

## Why this module

- **One module, many shapes.** ALB for HTTP(S), NLB for TCP/UDP/TLS — selected
  by `load_balancer_type`.
- **Secure by default, secure at the edge.** Built-in `authenticate-cognito` /
  `authenticate-oidc` actions, mutual TLS (`mutual_authentication`), optional
  WAFv2 association, and TLS/desync hardening attributes.
- **Observable.** Opt-in CloudWatch alarms (unhealthy hosts, 5XX, latency) and
  optional Route 53 alias records.
- **Lambda done right.** `target_type = "lambda"` auto-creates the required
  invoke permission.
- **Everything is a keyed map.** Target groups, listeners, and rules are maps
  keyed by a stable identifier. Listeners and rules reference target groups *by
  key*, so you never hand-wire ARNs.
- **Not tied to any orchestrator.** Expose `target_group_arns` and let ECS/EKS
  attach, or attach static targets directly via each target group's `targets`.
- **Flexible routing.** Forward (single or weighted/blue-green), redirect,
  fixed-response, plus path/host/header/query/source-IP/method rule conditions.
- **Batteries included, optional.** Built-in security group with arbitrary
  ingress/egress rules, SNI certificates, S3 access/connection logs.

## Quick start (ALB in front of an ECS or EKS service)

```hcl
module "alb" {
  source = "../../modules/lb"

  name    = "web"
  vpc_id  = module.network.vpc_id
  subnets = module.network.public_subnet_ids

  security_group_ingress_rules = {
    http  = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
    https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
  }

  target_groups = {
    app = {
      port        = 8080
      protocol    = "HTTP"
      target_type = "ip" # ECS awsvpc / EKS pods via the LB controller
      health_check = { path = "/healthz", matcher = "200" }
    }
  }

  listeners = {
    https = {
      port            = 443
      protocol        = "HTTPS"
      certificate_arn = var.certificate_arn
      default_action  = { type = "forward", target_group_key = "app" }
    }
    http = {
      port = 80
      default_action = {
        type     = "redirect"
        redirect = { status_code = "HTTP_301", port = "443", protocol = "HTTPS" }
      }
    }
  }
}
```

Attach a consumer to the target group ARN:

```hcl
# ECS service
load_balancer {
  target_group_arn = module.alb.target_group_arns["app"]
  container_name   = "app"
  container_port   = 8080
}

# EKS (AWS Load Balancer Controller) — TargetGroupBinding
# spec.targetGroupARN: module.alb.target_group_arns["app"]
```

## Common shapes

### Path/host routing with listener rules

```hcl
target_groups = {
  web = { port = 8080, target_type = "ip" }
  api = { port = 9090, target_type = "ip" }
}

listeners = {
  http = { port = 80, default_action = { type = "forward", target_group_key = "web" } }
}

listener_rules = {
  api = {
    listener_key = "http"
    priority     = 100
    actions      = [{ type = "forward", target_group_key = "api" }]
    conditions   = [{ path_patterns = ["/api/*"] }]
  }
}
```

### Blue/green (weighted forward)

```hcl
listeners = {
  http = {
    port = 80
    default_action = {
      type = "forward"
      target_groups = [
        { target_group_key = "blue", weight = 90 },
        { target_group_key = "green", weight = 10 },
      ]
      stickiness = { duration = 3600 }
    }
  }
}
```

### Network Load Balancer with static IPs and direct attachments

```hcl
module "nlb" {
  source = "../../modules/lb"

  name                  = "ingress"
  load_balancer_type    = "network"
  internal              = true
  create_security_group = false

  subnet_mappings = [
    { subnet_id = "subnet-a", private_ipv4_address = "10.0.1.10" },
    { subnet_id = "subnet-b", private_ipv4_address = "10.0.2.10" },
  ]

  target_groups = {
    tcp = {
      port        = 443
      protocol    = "TCP"
      target_type = "instance"
      vpc_id      = module.network.vpc_id
      targets = {
        node1 = { target_id = "i-aaaa1111" }
        node2 = { target_id = "i-bbbb2222" }
      }
    }
  }

  listeners = {
    tcp = { port = 443, default_action = { type = "forward", target_group_key = "tcp" } }
  }
}
```

### Edge authentication (OIDC / Cognito)

Authenticate users at the load balancer before traffic reaches your service.
Set `authenticate_oidc` or `authenticate_cognito` on the action; the module emits
the auth action ahead of your forward/redirect automatically.

```hcl
listeners = {
  https = {
    port            = 443
    protocol        = "HTTPS"
    certificate_arn = var.certificate_arn
    default_action = {
      type             = "forward"
      target_group_key = "app"
      authenticate_oidc = {
        authorization_endpoint = "https://idp.example.com/authorize"
        client_id              = "my-app"
        client_secret          = var.oidc_client_secret
        issuer                 = "https://idp.example.com"
        token_endpoint         = "https://idp.example.com/oauth/token"
        user_info_endpoint     = "https://idp.example.com/userinfo"
      }
    }
  }
}
```

### Mutual TLS (mTLS)

```hcl
listeners = {
  https = {
    port            = 443
    protocol        = "HTTPS"
    certificate_arn = var.certificate_arn
    mutual_authentication = {
      mode            = "verify"
      trust_store_arn = aws_lb_trust_store.this.arn
    }
    default_action = { type = "forward", target_group_key = "app" }
  }
}
```

### WAF, alarms, and DNS

```hcl
module "alb" {
  source = "../../modules/lb"
  # ...
  web_acl_arn              = aws_wafv2_web_acl.this.arn
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
  route53_records = {
    apex = { zone_id = data.aws_route53_zone.this.zone_id, name = "app.example.com" }
  }
}
```

### Internal ALB for service-to-service traffic

```hcl
module "internal_alb" {
  source = "../../modules/lb"

  name     = "internal"
  internal = true
  vpc_id   = module.network.vpc_id
  subnets  = module.network.private_subnet_ids

  security_group_ingress_rules = {
    mesh = { from_port = 80, to_port = 80, referenced_security_group_id = module.app.security_group_id }
  }

  target_groups = { svc = { port = 8080, target_type = "ip" } }
  listeners     = { http = { port = 80, default_action = { type = "forward", target_group_key = "svc" } } }
}
```

## Key references

Listeners and rules point at target groups by **map key**, not ARN:

- `listeners[*].default_action.target_group_key` → a key in `target_groups`
- `listeners[*].default_action.target_groups[*].target_group_key` → weighted forward
- `listener_rules[*].listener_key` → a key in `listeners`
- `listener_rules[*].actions[*].target_group_key` → a key in `target_groups`

All of these are validated at plan time, so a typo fails fast with a clear
message instead of a confusing runtime error.

## Behaviour notes

- **Security group.** Created by default (`create_security_group = true`) and
  required for an ALB (set it or pass `security_group_ids`). NLBs can optionally
  have one. Ingress/egress are arbitrary maps of rules, using the modern
  `aws_vpc_security_group_*_rule` resources; egress defaults to allow-all.
- **Type-specific attributes** (`idle_timeout`, `enable_http2`, … for ALB;
  `enable_cross_zone_load_balancing` for NLB) are applied only to the relevant
  LB type and omitted otherwise.
- **HTTPS/TLS** is enabled by setting `certificate_arn` on a listener; a modern
  default `ssl_policy` is applied automatically. Extra SNI certificates go in
  `additional_certificate_arns`.
- **Target groups** support `instance`, `ip`, `lambda`, and `alb` types, full
  health-check and stickiness configuration, and optional static `targets`.

## Inputs

| Name | Description | Default |
|------|-------------|---------|
| `name` | Load balancer name (≤32 chars) | n/a (required) |
| `load_balancer_type` | `application` \| `network` | `application` |
| `create` | Master switch; false builds nothing | `true` |
| `internal` | Internal (private) LB | `false` |
| `vpc_id` | VPC ID (required with `create_security_group` / instance·ip target groups) | `null` |
| `subnets` | Subnet IDs (mutually exclusive with `subnet_mappings`) | `[]` |
| `subnet_mappings` | Subnet mappings (NLB static/elastic IPs) | `[]` |
| `ip_address_type` | `ipv4` \| `dualstack` \| `dualstack-without-public-ipv4` | `ipv4` |
| `idle_timeout` | ALB idle timeout (seconds) | `60` |
| `enable_http2` / `drop_invalid_header_fields` / `preserve_host_header` | ALB attributes | `true` / `true` / `false` |
| `desync_mitigation_mode` | ALB desync mode | `defensive` |
| `enable_cross_zone_load_balancing` | NLB cross-zone | `true` |
| `web_acl_arn` | WAFv2 web ACL to associate (ALB) | `null` |
| `route53_records` | Map of alias records → the LB | `{}` |
| `create_cloudwatch_alarms` | Create LB/target-group alarms | `false` |
| `enable_deletion_protection` | Deletion protection | `false` |
| `access_logs` / `connection_logs` | S3 logging config | `null` |
| `create_security_group` | Create an SG for the LB | `true` |
| `security_group_ids` | Additional existing SGs | `[]` |
| `security_group_ingress_rules` / `security_group_egress_rules` | Maps of SG rules | `{}` / allow-all |
| `target_groups` | Map of target groups (see below) | `{}` |
| `listeners` | Map of listeners (see below) | `{}` |
| `listener_rules` | Map of listener rules (see below) | `{}` |
| `tags` | Tags applied to all resources | `{}` |

See [`variables.tf`](./variables.tf) for the full object schemas of
`target_groups`, `listeners`, and `listener_rules`.

## Outputs

| Name | Description |
|------|-------------|
| `arn`, `arn_suffix`, `id`, `name` | Load balancer identifiers |
| `dns_name`, `zone_id` | DNS name and Route 53 zone ID (for alias records) |
| `security_group_id`, `security_group_arn` | Created SG (null if not created) |
| `target_group_arns` | Map of target-group key → ARN (attach consumers here) |
| `target_group_arn_suffixes`, `target_group_names` | For CloudWatch / reference |
| `listener_arns`, `listener_rule_arns` | Maps of key → ARN |

## Testing

Offline `terraform test` suites live in [`tests/`](./tests) (mocked provider, no
AWS account needed):

```bash
cd modules/lb
terraform init -backend=false
terraform test
```
