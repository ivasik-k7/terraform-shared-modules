# ECR Module

A Terraform module for creating and managing AWS Elastic Container Registry (ECR) repositories with advanced features including lifecycle policies, replication, encryption, and access control.

## Features

- **Repository Management**: Create ECR repositories with configurable image tag mutability (`create` master toggle, immutable tags by default)
- **Security & least privilege**:
  - Image scanning on push for vulnerability detection
  - KMS encryption for customer-managed encryption keys (validated)
  - Fine-grained IAM repository (resource) policies that fully replace the broad default
  - **Ready-made, repo-scoped identity policies** (`pull_policy_json` / `push_policy_json`) to attach to consumer roles — least privilege without hand-written ECR actions
- **Lifecycle Management**: Automatic image cleanup with prefix **and** pattern matching (no empty-policy footgun)
- **Replication**: Cross-region and cross-registry image replication
- **Access Control**: Multiple principals with different access levels (push/pull vs pull-only)
- **Fleet-friendly outputs**: `repository_url`, `repository_arn`, `kms_key_arn`, scoped policy JSON — plug straight into ECS/EKS/CI modules
- **Tested**: 24 offline `terraform test` checks (plan + mocked apply); backward-compatible via a `moved` block

## Usage

### Basic Example

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  tags = {
    Environment = "production"
    Team        = "platform"
  }
}
```

### With Image Scanning and Lifecycle Policies

```hcl
module "ecr" {
  source = "./ecr"

  repository_name         = "my-app"
  scan_on_push           = true
  image_tag_mutability   = "IMMUTABLE"
  enable_lifecycle_policy = true

  lifecycle_rules = [
    {
      rule_priority = 1
      description   = "Expire untagged images after 7 days"
      tag_status    = "untagged"
      count_type    = "sinceImagePushed"
      count_unit    = "days"
      count_number  = 7
    },
    {
      rule_priority = 2
      description   = "Keep only last 50 tagged images"
      tag_status    = "tagged"
      count_type    = "imageCountMoreThan"
      count_number  = 50
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

### With Encryption and Access Control

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  # KMS Encryption
  encryption_type = "KMS"
  kms_key_arn     = aws_kms_key.ecr.arn

  # Access Control
  create_repository_policy = true
  allowed_principals       = ["arn:aws:iam::123456789012:role/eks-node-role"]
  allowed_pull_principals  = ["arn:aws:iam::123456789012:role/lambda-role"]

  tags = {
    Environment = "production"
  }
}
```

### With Cross-Region Replication

```hcl
module "ecr" {
  source = "./ecr"

  repository_name = "my-app"

  enable_replication = true

  replication_rules = [
    {
      destinations = [
        {
          region      = "eu-west-1"
          registry_id = "123456789012"
        }
      ]
      repository_filters = [
        {
          filter_type = "PREFIX_MATCH"
          filter      = "prod-"
        }
      ]
    }
  ]

  tags = {
    Environment = "production"
  }
}
```

## Inputs

### General

| Name     | Description                                              | Type   | Default | Required |
| -------- | ------------------------------------------------------- | ------ | ------- | :------: |
| `create` | Master switch. When `false` the module creates nothing. | `bool` | `true`  |    no    |

### Repository Configuration

| Name                   | Description                                   | Type     | Default       | Required |
| ---------------------- | --------------------------------------------- | -------- | ------------- | :------: |
| `repository_name`      | Repo name (2–256 chars, lowercase pattern)    | `string` | -             |   yes    |
| `image_tag_mutability` | Tag mutability setting (IMMUTABLE or MUTABLE) | `string` | `"IMMUTABLE"` |    no    |
| `force_delete`         | Delete repo even if it still holds images     | `bool`   | `false`       |    no    |

### Image Scanning

| Name           | Description                           | Type   | Default | Required |
| -------------- | ------------------------------------- | ------ | ------- | :------: |
| `scan_on_push` | Enable vulnerability scanning on push | `bool` | `true`  |    no    |

### Encryption

| Name              | Description                                        | Type     | Default    | Required |
| ----------------- | -------------------------------------------------- | -------- | ---------- | :------: |
| `encryption_type` | Encryption type (AES256 or KMS)                    | `string` | `"AES256"` |    no    |
| `kms_key_arn`     | KMS key ARN (required when encryption_type is KMS) | `string` | `null`     |    no    |

### Lifecycle Management

| Name                      | Description                                 | Type                | Default           | Required |
| ------------------------- | ------------------------------------------- | ------------------- | ----------------- | :------: |
| `enable_lifecycle_policy` | Enable lifecycle policy (only takes effect when rules are supplied) | `bool`     | `true` |    no    |
| `lifecycle_rules`         | Lifecycle rules for image retention (none by default)              | `list(object(...))` | `[]`   |    no    |

### Repository Access Control

| Name                           | Description                                      | Type                | Default             | Required |
| ------------------------------ | ------------------------------------------------ | ------------------- | ------------------- | :------: |
| `create_repository_policy`                | Whether to create and attach a repository policy   | `bool`              | `true`                       |    no    |
| `repository_policy_statements`            | Resource-policy base (secure default: account pull/push, no destructive actions) | `list(object(...))` | Account pull/push baseline |    no    |
| `additional_repository_policy_statements` | Extra statements layered **on top** of the base    | `list(object(...))` | `[]`                         |    no    |
| `allowed_principals`                      | Principals with push/pull access                   | `list(string)`      | `[]`                         |    no    |
| `allowed_pull_principals`                 | Principals with pull-only access                   | `list(string)`      | `[]`                         |    no    |

### Replication

| Name                 | Description                                      | Type                | Default | Required |
| -------------------- | ------------------------------------------------ | ------------------- | ------- | :------: |
| `enable_replication` | Enable repository replication                    | `bool`              | `false` |    no    |
| `replication_rules`  | Replication rules for cross-region/registry sync | `list(object(...))` | `[]`    |    no    |

### Logging

| Name                            | Description                               | Type     | Default                      | Required |
| ------------------------------- | ----------------------------------------- | -------- | ---------------------------- | :------: |
| `enable_logging`                | Enable CloudWatch logging for ECR actions | `bool`   | `false`                      |    no    |
| `cloudwatch_log_group_name`     | CloudWatch log group name                 | `string` | `/aws/ecr/{repository_name}` |    no    |
| `cloudwatch_log_retention_days` | Log retention period in days              | `number` | `30`                         |    no    |

### Tags

| Name          | Description                                                          | Type          | Default | Required |
| ------------- | ------------------------------------------------------------------- | ------------- | ------- | :------: |
| `tags`        | **Canonical** tag input for all resources                           | `map(string)` | `{}`    |    no    |
| `common_tags` | **Deprecated** alias, merged underneath `tags` (back-compat only)   | `map(string)` | `{}`    |    no    |

> **Tags are unified**: the module applies `merge(common_tags, tags)` everywhere —
> `tags` is canonical and wins on conflicts. `common_tags` is kept only for
> backward compatibility and will be removed in a future major version; migrate to
> `tags`.

## Outputs

| Name                           | Description                                                                        |
| ------------------------------ | ---------------------------------------------------------------------------------- |
| `repository_url`               | Repository URL (`<acct>.dkr.ecr.<region>.amazonaws.com/<name>`) — use as image ref |
| `repository_arn`               | The ARN of the repository                                                          |
| `repository_name`              | The name of the repository                                                         |
| `registry_id`                  | The AWS account ID (registry ID)                                                   |
| `kms_key_arn`                  | KMS key ARN protecting the repo (null for AES256) — for `kms:Decrypt` grants       |
| `pull_policy_json`             | **Least-privilege** IAM policy JSON for PULL — attach to consumer roles            |
| `push_policy_json`             | **Least-privilege** IAM policy JSON for PULL+PUSH — attach to CI/build roles       |
| `image_tag_mutability`         | The tag mutability setting                                                         |
| `image_scanning_configuration` | The image scanning configuration                                                   |
| `encryption_configuration`     | The encryption configuration (sensitive)                                           |
| `repository_policy_statements` | The combined resource-policy statements (sensitive; null when none)                |
| `lifecycle_policy_created`     | Whether a lifecycle policy was actually created (true only when enabled AND rules) |
| `lifecycle_rules`              | The applied lifecycle rules                                                         |
| `replication_enabled`          | Whether replication is enabled                                                     |
| `replication_configuration`    | The replication configuration                                                      |
| `log_group_name` / `log_group_arn` | CloudWatch log group name / ARN                                                |
| `allowed_push_principals`      | Principals with push/pull access (resource policy)                                 |
| `allowed_pull_principals`      | Principals with read-only access (resource policy)                                 |

All resource-derived outputs return `null` when `create = false`.

## Lifecycle Rules

There are **no default rules** — `lifecycle_rules` defaults to `[]`. A lifecycle
policy is created only when you supply rules (so the default config never emits an
empty, invalid policy). Each rule's `action_type` is always `"expire"` (ECR's only
action). A `tagged` rule must scope itself with `tag_prefix_list` **or**
`tag_pattern_list`.

```hcl
lifecycle_rules = [
  {
    rule_priority = 1
    description   = "expire untagged after 14 days"
    tag_status    = "untagged"            # untagged | tagged | any
    count_type    = "sinceImagePushed"    # sinceImagePushed | imageCountMoreThan
    count_unit    = "days"                # only for sinceImagePushed
    count_number  = 14
    action_type   = "expire"
  },
  {
    rule_priority    = 2
    description      = "keep last 10 release images"
    tag_status       = "tagged"
    tag_pattern_list = ["v*"]             # wildcard match (or tag_prefix_list)
    count_type       = "imageCountMoreThan"
    count_number     = 10
    action_type      = "expire"
  },
]
```

## Repository policy & least privilege

There are **two complementary** ways to control access — use the second for
least privilege across a fleet of modules.

**1. Resource policy (on the repo) — secure baseline + additional.** By default
the module attaches a **least-privilege baseline**: the owning account gets
pull/push + read, but **no** destructive or policy-rewriting actions
(`DeleteRepository`, `BatchDeleteImage`, `Set`/`DeleteRepositoryPolicy`). You then
layer extra grants **on top** without touching the base:

```hcl
# add scoped grants on top of the secure baseline
additional_repository_policy_statements = [{
  sid    = "PullOnlyForBuildAccount"
  effect = "Allow"
  principals = { type = "AWS", identifiers = ["arn:aws:iam::444444444444:role/deployer"] }
  actions = ["ecr:GetDownloadUrlForLayer", "ecr:BatchGetImage", "ecr:BatchCheckLayerAvailability"]
}]
```

Layering order: `repository_policy_statements` (secure base, has a default) →
`additional_repository_policy_statements` → `allowed_principals` /
`allowed_pull_principals`. To go even tighter, **replace** the base by setting
`repository_policy_statements` yourself, or set it to `[]` (and disable with
`create_repository_policy = false`) to rely solely on identity policies.

**2. Identity policies (on the consumer's role) — recommended.** The module
emits ready-made, repo-scoped policy JSON. Each consuming module attaches exactly
the access it needs to its **own** role — no hand-written ECR permissions, no
over-broad grants:

```hcl
module "ecr" { source = "../../modules/ecr"  repository_name = "platform/api" }

# the ECS task execution role gets PULL only, scoped to this one repo
resource "aws_iam_role_policy" "ecr_pull" {
  role   = module.ecs.task_execution_role_name
  policy = module.ecr.pull_policy_json
}

# the CI role gets PULL+PUSH
resource "aws_iam_role_policy" "ecr_push" {
  role   = aws_iam_role.ci.name
  policy = module.ecr.push_policy_json
}
```

## Fleet integration

Outputs are designed to plug straight into the rest of the platform:

| You need… | Use |
|---|---|
| Image reference for ECS/Fargate/EKS | `repository_url` (e.g. `"${module.ecr.repository_url}:1.2.3"`) |
| Grant a role pull/push | `pull_policy_json` / `push_policy_json` |
| Grant `kms:Decrypt` to pullers (KMS repos) | `kms_key_arn` |
| Reference the repo in other policies | `repository_arn` |

## Encryption

Choose between:

- **AES256**: AWS-managed encryption (default, no additional cost)
- **KMS**: Customer-managed encryption with `kms_key_arn`

## Requirements

- Terraform >= 1.5.0
- AWS Provider >= 5.30.0, < 6.0.0

## Notes & gotchas

- **Registry-level singletons → prefer the [`ecr-registry`](../ecr-registry) module.**
  `enable_replication`, `enable_registry_scanning`, and `enable_registry_policy`
  configure **account-/region-wide** settings, not the repository. They remain here
  for backward compatibility but are **deprecated** — enabling them in more than one
  repo instance makes the instances fight over the shared config (perpetual drift).
  Manage them once, per account/region, via the dedicated `ecr-registry` module.
- **Lifecycle policy needs rules.** `enable_lifecycle_policy = true` with an empty
  `lifecycle_rules` creates **nothing** (an empty policy is invalid in ECR). Supply
  rules to get a policy; `lifecycle_policy_created` reflects the real outcome.
- **KMS requires a key.** `encryption_type = "KMS"` without `kms_key_arn` fails fast
  at plan (precondition), not with an opaque apply error.
- **`scan_on_push` vs registry ENHANCED scanning.** They are different scanning
  modes. If you enable ENHANCED scanning at the registry (`ecr-registry` module),
  per-repo basic `scan_on_push` is superseded — don't rely on both.
- **CloudWatch logging is BYO/no-op.** `enable_logging` creates a log group, but ECR
  does **not** write API activity to it (that goes to CloudTrail). Treat the group
  as one for your own tooling, and set `cloudwatch_kms_key_id` if you need it
  encrypted (it is unencrypted by default even when the repo is KMS-encrypted).
- **No `prevent_destroy`.** `force_delete = false` (default) stops deletion of a repo
  that still holds images, but `terraform destroy` will remove an empty repo.
- **Encryption & tag mutability are immutable** after creation — changing them
  forces repository replacement (which deletes images).
- Repository names must be 2–256 chars, lowercase, `[a-z0-9-_/]`.

## Backward compatibility

- A `create` toggle was added (default `true`); a `moved` block rebinds the
  existing `aws_ecr_repository.this` to `…this[0]`, so upgrading does **not**
  destroy/recreate the repository (which would delete its images). `terraform plan`
  shows a *move*, not a replacement.
- **Security hardening (default change):** the default `repository_policy_statements`
  no longer grants the account `DeleteRepository` / `BatchDeleteImage` /
  `Set`/`DeleteRepositoryPolicy`. Same-account identities are unaffected in practice
  (IAM still governs those), but if you relied on the resource policy for those
  grants, add them via `additional_repository_policy_statements`. The Sid changed
  from `AllowFullAccessToAccount` to `AllowAccountPullPush`.
- All input **names** and signatures are unchanged; `common_tags` still works
  (deprecated).

## Testing

Two offline suites — fully mocked, no AWS credentials, no billable resources:

```bash
cd modules/ecr
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test                                  # all suites (24 checks)
terraform test -filter=tests/ecr.tftest.hcl     # plan-level + validations
terraform test -filter=tests/apply.tftest.hcl   # mocked-provider apply + outputs
```

`tests/ecr.tftest.hcl` covers secure defaults, lifecycle (with rules, `tagPatternList`,
and the empty-rules no-op), KMS, mutability, cross-account principals, least-privilege
resource policies, replication, pull-through cache, `create = false`, and every
validation/precondition failure. `tests/apply.tftest.hcl` applies against a mock
provider and asserts the integration outputs (`pull_policy_json`, `push_policy_json`,
`kms_key_arn`).
