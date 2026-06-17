# ECS Service Connect Terraform Module

A flexible, scalable module for the **service discovery phase** of ECS Service Connect: it owns the Cloud Map namespace, the shared Envoy proxy log group, and generates ready-to-consume `service_connect_configuration` objects (the discovery "rules") for any number of services.

It is intentionally decoupled from the ECS module — it produces configuration that any ECS service (this repo's `ecs` module, `landing-ecs`, or your own `aws_ecs_service`) can plug in directly.

## What This Module Does

- Creates a Cloud Map namespace — `http` (recommended for Service Connect) or `dns_private` (also DNS-resolvable) — or references an existing one
- Optionally creates a shared CloudWatch log group for the Service Connect Envoy proxy, and injects an `awslogs` config into every generated service config
- Generates a complete `service_connect_configuration` per service: exposed ports (`port_name`), discovery names, client aliases (`dns_name:port`), `ingress_port_override`, request/idle `timeout`, and Service Connect `tls`
- **Mesh-wide defaults** (`default_timeout`, `enable_tls` + `tls_ca_arn` + `tls_role_arn`) applied to every service unless it overrides — flip on mTLS for the whole mesh in one place
- Emits a human-readable `service_endpoints` map (`<dns_name>:<port>`)
- Validates inputs at plan time, including **cross-service self-consistency**: unique `port_name` per service, unique discovery names, and no colliding `<dns_name>:<port>` endpoints

> **Scope:** this module owns _service discovery_ — the namespace, the generated Service Connect configuration, and the log group that directly supports it. It intentionally does **not** create security groups or IAM roles: task-to-task networking and certificate-issuance IAM are the consumer's concern (pass an existing `tls_role_arn`; manage SGs on your ECS task SG or the `network-security-group` module).

## Usage

> In every example, the task definition's port mapping must have a `name` matching the Service Connect `port_name`. The `ecs` module's `port_mappings` supports `name` for exactly this.

### 1. Minimal — create a namespace and one discoverable service

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name = "app-mesh"   # used as the namespace name too

  services = {
    api = {
      services = [{
        port_name      = "api-http"
        client_aliases = [{ port = 8080 }]   # reachable at api-http:8080
      }]
    }
  }
}
```

### 2. Multiple services, multi-port, and a client-only service

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name           = "app-mesh"
  namespace_name = "prod.internal"

  default_timeout = { per_request_timeout_seconds = 15 }

  services = {
    # Exposes both an HTTP and a gRPC port, each with its own client alias.
    api = {
      services = [
        {
          port_name      = "api-http"
          discovery_name = "api"
          client_aliases = [{ port = 8080, dns_name = "api" }]
        },
        {
          port_name      = "api-grpc"
          discovery_name = "api-grpc"
          client_aliases = [{ port = 9090, dns_name = "api-grpc" }]
        },
      ]
    }

    # Exposes one port.
    payments = {
      services = [{ port_name = "http", client_aliases = [{ port = 8080, dns_name = "payments" }] }]
    }

    # Client-only: reaches api/payments but exposes nothing.
    web = { services = [] }
  }
}
```

### 3. Reference an existing namespace (don't create one)

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name                   = "app-mesh"
  create_namespace       = false
  existing_namespace_arn = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-abc123"

  services = {
    api = { services = [{ port_name = "http", client_aliases = [{ port = 8080, dns_name = "api" }] }] }
  }
}
```

### 4. Private DNS namespace (also resolvable outside Service Connect)

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name           = "app-mesh"
  namespace_name = "prod.internal"
  namespace_type = "dns_private"
  vpc_id         = var.vpc_id            # required for dns_private

  services = {
    api = { services = [{ port_name = "http", client_aliases = [{ port = 8080, dns_name = "api" }] }] }
  }
}
```

### 5. Shared Envoy proxy logging (with a per-service override)

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name = "app-mesh"

  create_log_group      = true   # auto-injects an awslogs config into each service
  log_retention_in_days = 14
  log_kms_key_id        = aws_kms_key.logs.arn

  services = {
    # discovery_name defaults to port_name (AWS behavior) and must be unique
    # across the namespace — set it explicitly when services share a port name.
    api = { services = [{ port_name = "http", discovery_name = "api", client_aliases = [{ port = 8080 }] }] }

    # Override the injected default log config for one service.
    payments = {
      services = [{ port_name = "http", discovery_name = "payments", client_aliases = [{ port = 8081 }] }]
      log_configuration = {
        log_driver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/service-connect/payments"
          "awslogs-region"        = "us-east-1"
          "awslogs-stream-prefix" = "sc"
        }
      }
    }
  }
}
```

### 6. Mesh-wide mTLS

The module generates the `tls` config and applies it mesh-wide, but the IAM role ECS uses to issue certificates is **managed outside this module** (certificate-issuance IAM, not discovery) and passed in via `tls_role_arn`.

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name           = "app-mesh"
  namespace_name = "prod.internal"

  # One switch turns on mTLS for every exposed service.
  enable_tls   = true
  tls_ca_arn   = aws_acmpca_certificate_authority.this.arn
  tls_role_arn = aws_iam_role.sc_tls.arn   # role managed by the caller
  tls_kms_key  = aws_kms_key.sc.arn        # optional

  services = {
    api = { services = [{ port_name = "api-http", client_aliases = [{ port = 8080, dns_name = "api" }] }] }
    web = { services = [] }
  }
}
```

Per-service TLS overrides the mesh default (e.g. a different CA or its own role):

```hcl
services = {
  api = {
    services = [{
      port_name      = "api-http"
      client_aliases = [{ port = 8080, dns_name = "api" }]
      tls = {
        aws_pca_authority_arn = aws_acmpca_certificate_authority.api.arn
        role_arn              = aws_iam_role.api_sc_tls.arn
      }
    }]
  }
}
```

### 7. End-to-end with the `ecs` module

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name           = "app-mesh"
  namespace_name = "prod.internal"

  services = {
    api = { services = [{ port_name = "api-http", client_aliases = [{ port = 8080, dns_name = "api" }] }] }
    web = { services = [] }
  }
}

module "ecs" {
  source = "../../modules/ecs"

  cluster_name = "app-cluster"

  # Optional cluster-wide default namespace.
  service_connect_defaults = { namespace = module.service_connect.namespace_arn }

  services = {
    api = {
      task_definition_family = "api"
      network_configuration  = { subnets = var.subnet_ids }

      container_definitions = [{
        name  = "api"
        image = "public.ecr.aws/nginx/nginx:alpine"
        # NAMED port mapping matching the Service Connect port_name:
        port_mappings = [{ name = "api-http", container_port = 8080, app_protocol = "http" }]
      }]

      # Drop the generated config straight in:
      service_connect_configuration = module.service_connect.service_connect_configurations["api"]
    }
  }
}
```

## Inputs

| Name                               | Description                                                       | Default |
| ---------------------------------- | ----------------------------------------------------------------- | ------- |
| `name`                             | Resource name prefix                                              | —       |
| `create_namespace`                 | Create a Cloud Map namespace                                      | `true`  |
| `namespace_name`                   | Namespace name (defaults to `name`)                               | `null`  |
| `namespace_type`                   | `http` or `dns_private`                                           | `http`  |
| `vpc_id`                           | Required for `dns_private`                                        | `null`  |
| `existing_namespace_arn`           | Reference an existing namespace (when `create_namespace = false`) | `null`  |
| `create_log_group`                 | Create a shared Service Connect log group                         | `false` |
| `inject_default_log_configuration` | Inject `awslogs` config into generated service configs            | `true`  |
| `services`                         | Map of service name → Service Connect rules                       | `{}`    |
| `default_timeout`                  | Default timeout for services that don't set their own             | `null`  |
| `enable_tls`                       | Enable mesh-wide mTLS (requires `tls_ca_arn` + `tls_role_arn`)    | `false` |
| `tls_ca_arn`                       | AWS Private CA ARN for Service Connect TLS                        | `null`  |
| `tls_kms_key`                      | KMS key injected into the mesh-wide TLS config                    | `null`  |
| `tls_role_arn`                     | IAM role ECS assumes to issue certs (managed outside this module) | `null`  |
| `tags`                             | Tags applied to all resources                                     | `{}`    |

See [variables.tf](variables.tf) for the full `services` object schema.

### Mesh-wide mTLS

The module generates the `tls` config and applies it mesh-wide, but the IAM role
ECS uses to issue certificates is **managed outside this module** (it's
certificate-issuance IAM, not service discovery) and passed in via `tls_role_arn`.

```hcl
module "service_connect" {
  source = "../../modules/ecs-service-connect"

  name           = "app-mesh"
  namespace_name = "prod.internal"

  # One switch turns on mTLS for every exposed service.
  enable_tls   = true
  tls_ca_arn   = aws_acmpca_certificate_authority.this.arn
  tls_role_arn = aws_iam_role.sc_tls.arn   # role managed by the caller

  default_timeout = { per_request_timeout_seconds = 30 }

  services = {
    api = { services = [{ port_name = "api-http", client_aliases = [{ port = 8080, dns_name = "api" }] }] }
    web = { services = [] }
  }
}
```

## Outputs

| Name                                                | Description                                                                |
| --------------------------------------------------- | -------------------------------------------------------------------------- |
| `namespace_arn` / `namespace_id` / `namespace_name` | The namespace (created or referenced)                                      |
| `namespace_hosted_zone`                             | Route 53 hosted zone for a `dns_private` namespace                         |
| `log_group_name` / `log_group_arn`                  | The shared Service Connect log group                                       |
| `service_connect_configurations`                    | Map of service name → full config object for ECS services                  |
| `service_endpoints`                                 | Map of service name → list of `<dns_name>:<port>` client endpoints         |
| `tls_role_arn`                                      | The externally-managed TLS role ARN passed through to TLS-enabled services |

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| aws       | ~> 5.0   |

## Tests

A native `terraform test` suite (plan generation + mocked-provider apply) lives in [tests/](tests/). Run `terraform test` in this directory.
