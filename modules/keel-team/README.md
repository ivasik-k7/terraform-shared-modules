# keel-team

Keel's per-account block. A team's account gets its limits and their alerts by
severity. It can also get:

- **Platforms.** Several platforms can share the account, each with its own
  limit on its tag.
- **AI cost controls.** Tagged Bedrock inference profiles, a cap per
  application and a burn meter that acts within the hour.
- **Non-production running hours.**
- **A read-only role for the FinOps team.**

It is built on [`keel-limits`](../keel-limits) and [`keel-signals`](../keel-signals).

```hcl
module "lending_payments" {
  source  = "app.terraform.io/<org>/keel-team/aws"
  version = "~> 0.1"

  team        = "lending-payments"
  cost_centre = "CC-4410"
  emails      = { high = ["lending-payments-leads@example.com"] }

  limits = {
    account = { amount = "8500" }
  }
  platforms = {
    payments-api = { amount = "4000", anomaly = {} }
  }
  signals = { control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel" }
}
```

## One account, several Regions

Budgets are global; topics, Bedrock profiles, the burn meter, quotas,
invocation logs and schedules are per Region. Call the module once per Region
the account uses:

| Call | `components` | Creates |
|---|---|---|
| Home Region (London) | default: `{ account = true, region = true }` | Limits, the FinOps role, and London's Region part |
| Each other Region (Ireland) | `{ account = false }` | That Region's topics, profiles, burn meter, logs, schedules |

`examples/multi-region` is that layout. An AI cap counts the application's
spend in every Region, because it filters on tags. A burn meter counts only its
own Region, because the Bedrock metrics are regional.

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Cost allocation tags | `Team`, `Application` and `platform_tag_key` (default `Platform`) active in billing (`keel-billing`). Until then the platform limits and AI caps see no spend |
| Bedrock | The models in `ai.applications` available in each Region |

## What the module refuses

| Refused | Why |
|---|---|
| An account part without a Region part | Its limits notify that Region's topics |
| A limit named `platform-*` or `ai-*` | Those names belong to `platforms` and `ai.applications`; one would replace the other |
| More than five priced models | The burn alarm holds at most ten metrics, two per model |
| `burn_per_hour` without prices | Nothing to price |
| A quota tied to a model with no price | The ceiling cannot be priced |
| A model that is not a foundation model or inference profile ARN | A profile copies one of those |
| Names with double or trailing hyphens, or `<team>-<application>-<alias>` over 64 characters | Bedrock refuses the inference profile at apply |
| Plus everything [`keel-limits`](../keel-limits) refuses | A limit that cannot be a budget |

### Advisory checks

| Check | Fires when |
|---|---|
| `every_account_has_a_limit` | No COST limit with an empty scope: spend outside the platforms has no budget (FC-01) |
| `sandboxes_lock_at_their_limit` | A sandbox account where no limit has an action |
| `somebody_hears_the_team` | No emails and no control plane in this Region |
| `signals_reach_the_control_plane` | No control plane bus: signals are not kept as evidence |
| `ai_burn_is_metered` | AI applications in this Region, no burn meter |
| `ai_invocations_are_logged` | AI applications in this Region, no invocation logs |
| `production_changes_only_by_people`, `every_limit_has_an_owner` | From `keel-limits` |

## Behaviour to know about

- **Limits are passed to `keel-limits` as they are.** Each one is a budget
  whose alerts go to a severity topic. Under 100% of actual spend is WARNING,
  from 100% HIGH, and from the tier's critical mark CRITICAL. A forecast alert
  is WARNING. A limit can also have its own anomaly monitor and an action. The
  fields are in [`keel-limits`](../keel-limits).
- **Platforms share an account by tag.** `platforms.<name>` becomes the limit
  `platform-<name>` on `platform_tag_key = <name>`. Spend without the tag
  counts only against the account limit; `keel-guardrails` can require the tag.
- **AI has four meters.**
  - The burn alarm prices the last hour of tokens from `ai.prices` and pages
    CRITICAL.
  - The caps (`ai-<application>`) are budgets on the `Team` and `Application`
    tags.
  - The invocation logs say who called which model.
  - The bill reconciles all three.
- **Invocation logs are metadata only.** No text, image, embedding or video is
  delivered. Bedrock logging is one configuration per account and Region, so
  this call owns it.
- **Quotas are read, not changed.** Service Quotas raises quotas but does not
  lower them. `ai_ceilings` therefore reports what a quota means in money: the
  most a model can cost in an hour.
- **Schedules stop and start through AWS runbooks.** EC2 instances are picked
  by tag and RDS instances by identifier. Starting starts every tagged
  instance, including one somebody stopped by hand.
- **The FinOps role reads cost and named metadata actions only.** No
  wildcards: `ec2:Describe*` includes user data, `ecs:Describe*` task
  environments, and `lambda:GetFunctionConfiguration` returns environment
  variables, which hold secrets in practice. Lambda is left to Compute
  Optimizer. Its name is the same in every account.
- **The cost gate** is `policies/cost-gate.sentinel`. Its parameter
  `max_monthly_increase` is `plan_gate.max_monthly_increase`: the account
  limit times `cost_gate.max_increase_percent` (10%). No monthly amount (an
  auto-adjusting limit), no gate.
- **Names follow Bedrock's patterns.** Team, application and alias are
  lowercase words joined by single hyphens, and `<team>-<application>-<alias>`
  is at most 64 characters, the inference profile name's limit.
- **Schedules are named `<schedule>.ec2.<action>` and
  `<schedule>.rds.<instance>.<action>`,** so no two collide.

## Contract outputs

| Output | For |
|---|---|
| `inference_profile_arns` | Application teams: the ARNs to call |
| `topic_arns` | The team's own alarms: notify these to reach owners and the control plane |
| `plan_gate` | The HCP Terraform policy set's parameters |
| `controls` | The register: FC-01, FC-04, FC-06 and `LIMIT-<name>` from the account part, `AI-BURN-<region>` from each Region; they merge across calls |
| `ai_ceilings` | Finance and the AI owner: the hourly worst case at today's quotas |
| `finops_read_role_arn` | The FinOps account's tooling |
| `kms_key_policy_requirements` | The key owner, when topics, queue and logs use a customer key |
| `deployer_requirements`, `verify_commands`, `governance` | Platform, operators, reviewers |

## Limits

- **Never applied against real AWS.** The open points are in
  [../keel-billing/docs/RESEARCH.md](../keel-billing/docs/RESEARCH.md). Among them:
  - which `ModelId` profile calls carry in CloudWatch;
  - whether their cost carries the profile's tags;
  - whether Bedrock logs metadata with every data type off;
  - how Systems Manager resolves a tag that non-EC2 resources also carry.
- **Use a tag key only EC2 instances carry for schedules**, until the last of
  those is checked.
- **An AI cap is an alert, not a stop.** Stopping at the cap is a gateway's job,
  not built.
- **The model ARNs in the examples are illustrative.** Use the IDs available in
  your Regions.

## Versioning and support

Semantic versioning; tags `keel-team-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
