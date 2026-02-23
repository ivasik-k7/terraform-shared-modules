# terraform-aws-secrets-manager

Production-grade Terraform module for AWS Secrets Manager. Supports simple single-secret deployments through to multi-account, multi-region architectures with automatic rotation, CMK encryption, and fine-grained resource-based policies.

## Features

- Hierarchical secret naming: `<name_prefix>/<environment>/<key>`
- Three value modes: raw string, JSON key-value map (auto-serialized), base64 binary
- Placeholder secrets (no value) for out-of-band injection by CI/CD or operators
- Per-secret `ignore_secret_changes` to prevent Terraform from overwriting values managed externally
- Customer-managed KMS keys with per-secret or module-wide defaults
- Automatic rotation via Lambda
- Multi-region replication
- Resource-based IAM policies: module-wide and per-secret reader/manager grants, plus raw statement escape hatch
- Full native Terraform test suite (`tests/module.tftest.hcl`)

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| aws | >= 5.0, < 6.0 |

## Usage

### Minimal

```hcl
module "secrets" {
  source = "path/to/terraform-aws-secrets-manager"

  name_prefix = "acme/backend"
  environment = "prod"

  secrets = {
    "database/postgres" = {
      secret_key_value = {
        host     = "db.prod.internal"
        port     = "5432"
        username = "app"
        password = var.db_password
      }
    }
  }
}
```

### With CMK, rotation, and cross-account read access

```hcl
module "secrets" {
  source = "path/to/terraform-aws-secrets-manager"

  name_prefix        = "acme/payments"
  environment        = "prod"
  default_kms_key_id = aws_kms_key.secrets.arn

  reader_arns = [
    "arn:aws:iam::222222222222:root",
  ]

  secrets = {
    "database/postgres" = {
      description = "RDS credentials — auto-rotated every 30 days"
      secret_key_value = {
        host     = aws_db_instance.main.address
        port     = "5432"
        username = "app"
        password = random_password.db.result
      }
      ignore_secret_changes = true
      rotation = {
        lambda_arn               = aws_lambda_function.rotator.arn
        automatically_after_days = 30
      }
      replica_regions = [{ region = "eu-west-1" }]
    }

    "third-party/stripe" = {
      description   = "Stripe secret key"
      secret_string = var.stripe_secret_key
      policy = {
        reader_arns  = [aws_iam_role.payments_service.arn]
        manager_arns = [aws_iam_role.payments_admin.arn]
      }
    }

    "ci/github-token" = {
      description           = "GitHub PAT — injected by CI pipeline post-provisioning"
      ignore_secret_changes = true
    }
  }

  default_tags = {
    owner       = "platform-team"
    cost-center = "shared-infra"
  }
}
```

### Consuming outputs in other modules

```hcl
resource "aws_ecs_task_definition" "app" {
  container_definitions = jsonencode([{
    secrets = [
      {
        name      = "DB_PASSWORD"
        valueFrom = module.secrets.secret_arns["database/postgres"]
      }
    ]
  }])
}

data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = module.secrets.iam_read_arns
  }
}
```

## Secret Naming

The full path is constructed by joining non-empty segments with `/`:

| `name_prefix` | `environment` | key | Result |
|---|---|---|---|
| `acme/backend` | `prod` | `database/postgres` | `acme/backend/prod/database/postgres` |
| `acme/backend` | `` | `database/postgres` | `acme/backend/database/postgres` |
| `` | `prod` | `database/postgres` | `prod/database/postgres` |
| `` | `` | `database/postgres` | `database/postgres` |

## `ignore_secret_changes`

Setting `ignore_secret_changes = true` creates the secret with an initial value (if provided), then instructs Terraform to ignore future value drift. Terraform continues to manage all metadata: description, tags, KMS key, rotation config, and resource policies.

Use this for secrets rotated by Lambda, injected by CI/CD pipelines, or managed by an operator after initial provisioning.

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `name_prefix` | `string` | `""` | Path prefix for all secrets. |
| `environment` | `string` | `""` | Environment segment injected into path and tags. |
| `secrets` | `map(object)` | `{}` | Map of secrets to create. See variables.tf for full schema. |
| `default_kms_key_id` | `string` | `null` | Default KMS key for secrets without an explicit key. |
| `default_recovery_window_in_days` | `number` | `30` | Module-wide recovery window default. |
| `default_tags` | `map(string)` | `{}` | Tags merged into all secrets. |
| `reader_arns` | `list(string)` | `[]` | IAM ARNs granted read access on all secrets. |
| `manager_arns` | `list(string)` | `[]` | IAM ARNs granted management access on all secrets. |

## Outputs

| Name | Description |
|------|-------------|
| `secrets` | Full metadata map: `{ key => { arn, id, name, version_id } }` |
| `secret_arns` | `map(string)` — key → ARN |
| `secret_ids` | `map(string)` — key → Secret ID |
| `secret_names` | `map(string)` — key → full resolved path |
| `secret_version_ids` | `map(string)` — key → current version ID |
| `iam_read_arns` | `list(string)` — all ARNs for use in IAM Resource blocks |
| `resolved_paths` | `map(string)` — computed paths, useful for pre-apply verification |
| `rotation_enabled` | `map(bool)` — whether rotation is configured per secret |

## Running Tests

```bash
terraform init
terraform test
```

Tests run in `plan` mode by default and do not create real AWS resources.
