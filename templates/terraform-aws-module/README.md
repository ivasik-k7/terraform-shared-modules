# terraform-aws-log-group

A CloudWatch Logs log group with bounded retention and an optional customer
managed key, and the key policy statement that key needs, emitted as data.

> This repository is also the **module template**. The log group is a small
> working example of every convention; [TEMPLATE.md](TEMPLATE.md) says how to
> start a new module from it.

```hcl
module "logs" {
  source  = "app.terraform.io/CTO/log-group/aws"
  version = "~> 0.1" # release-please keeps this line at the current major.minor

  name        = "/app/orders"
  kms_key_arn = var.logs_key_arn # same region; see kms_key_policy_requirements
}
```

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` (HCP Terraform workspace: Terraform version setting) |
| `hashicorp/aws` | `>= 5.90.0, < 7.0.0`: tested on 5.100.0 and the newest 6.x |
| The key owner | The statement in `output.kms_key_policy_requirements`, before the first apply |

## What it refuses at plan

| Refused | Why |
|---|---|
| A name under `aws/` | Reserved for AWS services |
| A retention CloudWatch Logs does not offer | The API would reject it after the plan looked fine |
| A key in another region | CloudWatch Logs uses keys in its own region only; the apply would fail |

## Advisory checks

Warnings that do not block the plan. HCP Terraform health assessments
re-evaluate them, so drift into a warned state is reported. Name a check in
`acknowledged_checks` to accept it; the decision is listed in
`output.governance.acknowledged_checks`.

| Check | Warns when |
|---|---|
| `log_retention_is_bounded` | `retention_days = 0`: logs are kept, and billed, forever |
| `logs_use_a_customer_key` | No `kms_key_arn`: access cannot be revoked by key policy |

## Most-used inputs

The registry's Inputs tab is the reference; this is the short list.

| Input | Default | What it does |
|---|---|---|
| `name` | — | Log group name; changing it replaces the group |
| `retention_days` | `30` | `0` keeps logs forever |
| `kms_key_arn` | `""` | Customer managed key, same region |
| `log_group_class` | `STANDARD` | `INFREQUENT_ACCESS` lowers ingestion cost and drops features |
| `skip_destroy` | `false` | Keep the logs when the module is destroyed |

## Contract outputs

What other teams act on. Each is null when `create = false`.

| Output | For |
|---|---|
| `kms_key_policy_requirements` | The key owner: the statement CloudWatch Logs needs, in contract v2 |
| `governance` | Change reviews and tests: the posture as data |
| `verify_commands` | CloudShell, after an apply |

## What replaces what

| Change | Effect |
|---|---|
| `name`, `log_group_class` | Replaces the log group: its logs are deleted unless `skip_destroy` |
| `retention_days`, `kms_key_arn`, tags | In place |

## Limits

- **Never applied against real AWS** in this repository's CI: the tests run
  against a mocked provider. Run `verify_commands` after the first apply.
- **The key policy is not managed here.** The module cannot write another
  team's key policy; it emits what that policy needs.

## Versioning and support

Semantic versioning, tagged `vX.Y.Z`, which the HCP Terraform private
registry publishes. A major release is anything that changes what an
unchanged configuration plans: a removed or renamed input or output, a new
required input, a changed default, an update turned into a replacement, a
changed resource address, or a raised Terraform or provider floor. Minor
releases add optional inputs, outputs and checks; patches change no plan.
While at 0.x, a minor release may change a default and says so under
**BREAKING** in the [CHANGELOG](CHANGELOG.md).

| Document | Question |
|---|---|
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |
| [COSTS.md](COSTS.md) | What it costs, and which line has no ceiling |
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to change it, and what CI proves |
| [SECURITY.md](SECURITY.md) | How to report a vulnerability |
| [examples/basic](examples/basic) | The smallest call |
| [examples/complete](examples/complete) | Every input |
