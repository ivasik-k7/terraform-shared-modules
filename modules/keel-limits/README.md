# keel-limits

Keel's limit engine. Each limit is an AWS budget, whatever it counts: an
account, a platform inside a shared account, a business unit, a service line,
data transfer or a commitment target. Each threshold alerts at a severity, on
the severity topics from [`keel-signals`](../keel-signals). A limit can also
have its own anomaly monitor, and a lock or an SCP that runs at the limit.
[`keel-team`](../keel-team) and [`keel-billing`](../keel-billing) are built on
it; call it directly for anything they do not cover.

```hcl
module "limits" {
  source  = "app.terraform.io/<org>/keel-limits/aws"
  version = "~> 0.1"

  name       = "lending"
  topic_arns = module.signals.topic_arns

  limits = {
    ledger = { amount = "70000", scope = { tags = { Platform = ["ledger"] } }, anomaly = {} }
  }
}
```

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Cost allocation tags | Every tag key in a scope active in billing (`keel-billing`), or the limit sees no spend |
| Topics | `topic_arns` from `keel-signals`, so Budgets and Anomaly Detection may publish |

## What a limit is

| Field | Meaning |
|---|---|
| `type` | `COST` (default), `USAGE`, `SAVINGS_PLANS_COVERAGE`, `SAVINGS_PLANS_UTILIZATION`, `RI_COVERAGE`, `RI_UTILIZATION` |
| `scope` | What it counts, every field ANDed: `tags`, `cost_categories`, `accounts`, `services`, `regions`, `usage_types`, `usage_type_groups`. Empty: everything the account sees |
| `amount`, `unit` | The limit. `auto_adjust_months` makes a COST limit follow the average of past months instead |
| `target_percent` | Commitment types: alert below it |
| `period` | `MONTHLY`, `QUARTERLY` or `ANNUALLY` |
| `tier` | Which defaults it takes from `tiers` |
| `owners` | Up to ten e-mails told directly at every threshold |
| `anomaly` | Its own anomaly monitor, on exactly its scope |
| `action` | At `at_percent` of actual spend: a deny policy on `lock_roles`, or an SCP; `AUTOMATIC` or `MANUAL` |

## Severity

| Signal | Severity |
|---|---|
| A forecast threshold | WARNING |
| Actual spend below 100% | WARNING |
| Actual spend from 100% | HIGH |
| Actual spend from the tier's `critical_at_percent` | CRITICAL |
| A commitment below its target | WARNING |
| The limit's anomaly | The tier's `anomaly_severity` |
| An action waiting for approval or run | CRITICAL |

The default tiers:

| Tier | Forecast | Actual | Critical at | Automatic actions | Anomaly from |
|---|---|---|---|---|---|
| `production` | 80, 100 | 90, 100, 120 | 120% | No | 500, HIGH |
| `non-production` | 80, 100 | 100, 150 | 150% | Yes | 100, WARNING |
| `sandbox` | 100 | 80, 100 | 100% | Yes | 50, WARNING |

## What the module refuses

| Refused | Why |
|---|---|
| More than ten thresholds on a limit | AWS Budgets allows ten notifications per budget |
| An anomaly monitor on more than one filter, or on more than ten values | A monitor watches one tag key, one cost category or one set of accounts |
| A Net metric on an unscoped limit | An unscoped budget takes its basis from cost types, which have no net option |
| A USAGE limit without usage types; an RI limit without exactly one service | AWS Budgets needs them |
| An action or anomaly monitor on a commitment limit; an action with both roles and an SCP | Not meaningful, or not one action |
| A commitment limit scoped by tags, cost categories, Regions or usage types | A commitment budget filters on services and accounts only; the rest would be dropped and the whole account measured |
| A cost category anomaly monitor on more than one value | A customer managed monitor tracks one cost category value |
| A threshold with no owner and no topic; an anomaly monitor or action without its severity's topic | AWS refuses a notification without a subscriber, and an immediate alert or action report without SNS |

### Advisory checks

| Check | Fires when |
|---|---|
| `production_changes_only_by_people` | An `AUTOMATIC` action on a tier without `automatic_actions` |
| `every_limit_has_an_owner` | A limit with no owners and no topics, or a severity used with no topic |

## Behaviour to know about

- **An unscoped limit uses cost types.** The provider accepts `metrics` only
  with a filter. So an unscoped limit sets amortized or blended cost through
  `cost_types`.
- **Platforms in one account are tags.** A platform limit is a tag scope.
  Spend without the tag counts only against an unscoped limit.
- **Actions are global per account.** Budget actions are free for the first
  two per account, then $0.10 a day each.
- **A lock reaches its roles at any IAM path.** `lock_roles` are names; the
  action role may attach the lock to `role/<name>` and `role/*/<name>`.
- **AWS Budgets assumes the action role only for this account's budgets**
  (`aws:SourceAccount` and `aws:SourceArn`, as AWS's example policy).

## Contract outputs

| Output | For |
|---|---|
| `thresholds` | The people subscribing: what alerts at which severity |
| `controls` | The register: `LIMIT-<name>` per limit |
| `lock_policy_arns` | Operators: what to detach to unlock |
| `governance` | Reviewers |

## Limits

- **Never applied against real AWS.** Custom anomaly monitors in member
  accounts and commitment budgets on an organization with no commitments are
  unverified ([../keel-billing/docs/RESEARCH.md](../keel-billing/docs/RESEARCH.md)).
- **Usage type group names in the examples are illustrative.** Take them from
  Cost Explorer.

## Versioning and support

Semantic versioning; tags `keel-limits-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
