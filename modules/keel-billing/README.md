# keel-billing

Keel's management-account module: AWS's own cost management, configured as code
for the whole organization. It covers:

- **Allocation.** Allocation tags and cost categories, the owner taxonomy.
- **Recommendations.** The free recommendation services.
- **Anomalies.** Cost Anomaly Detection: AWS managed monitors by service and
  by account, and a monitor per business unit.
- **Limits.** Organization limits and commitment targets, alerting by
  severity, through [`keel-limits`](../keel-limits).
- **Billing views.** Shared billing views for the FinOps account and for teams.
- **FinOps Agent.** The decision to use AWS FinOps Agent, with its setup
  steps and policy as data.
- **Signals.** Severity topics and anomaly events to the Keel control plane,
  through [`keel-signals`](../keel-signals).
- **Dashboards.** The source side of the Cloud Intelligence Dashboards data
  pipeline.

```hcl
module "billing" {
  source  = "app.terraform.io/<org>/keel-billing/aws"
  version = "~> 0.1"

  cost_allocation_tags = ["Team", "CostCentre", "Application", "Platform"]
  cost_categories = {
    Team = { inherit_from_tag = "Team" }
  }
  anomaly_detection = {
    alert = { emails = ["finops@example.com"] }
  }
  limits = {
    total = { amount = "100000", owners = ["finops@example.com"] }
  }
  commitments = { savings_plans_utilization = 95 }
}
```

Keel as a whole is in [docs/FRAMEWORK.md](docs/FRAMEWORK.md): which Region
each module runs in, the order they go in, and the controls each implements.
The facts the design rests on, with sources, are in
[docs/RESEARCH.md](docs/RESEARCH.md).

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Account | The organization's management account, with a **us-east-1** provider. The billing APIs, Cost Anomaly Detection's events and FinOps Agent are there |
| Tags | A tag key must have been seen on a resource before it can be activated |
| Billing views | AWS RAM sharing with the organization enabled, so a view can be shared without invitations |
| FinOps Agent | An approval: organization-wide it reads every account's cost, resource and operational data, runs in us-east-1, and is set up from its console (`finops_agent_setup`) |
| Dashboards | For `data_exports`, `keel-insights` deployed first in the destination account; its `source_requirements` give the account, Region and template mirror |

## What the module refuses

| Refused | Why |
|---|---|
| A cost category rule with both accounts and a tag, or neither | A rule has one expression |
| A digest without emails | Digests go by e-mail; the immediate alert goes to its topic |
| A limit with its own anomaly monitor | The managed monitors cover the organization; its alerts would reach the control plane twice |
| A limit named `sp-*` or `ri-*` | Those names are the commitment targets' |
| A billing view on accounts and a tag, or neither | A view filters on one dimension |
| A delegated FinOps Agent administrator without `enabled` | Delegation needs trusted access |
| More than 500 cost category values to watch | AWS's limit on customer managed monitors per management account |
| `data_exports` without the destination's `region` | The template delivers to the bucket in the stack's own Region |
| Plus everything [`keel-limits`](../keel-limits) refuses | A limit that cannot be a budget |

### Advisory checks

| Check | Fires when |
|---|---|
| `somebody_hears_an_anomaly` | The immediate alert is off with no digests, or has neither emails nor a control plane |
| `every_cost_category_is_watched` | A cost category has no anomaly monitor |
| `spend_is_allocated_by_tags` | A cost category uses a tag key that is not activated here, so its rule matches no spend |
| `anomaly_events_reach_the_control_plane` | Forwarding is on but the provider is not in us-east-1 |
| `commitments_are_watched` | No commitment target |
| `finops_agent_is_approved` | FinOps Agent is chosen: acknowledge once its organization-wide read access is approved |
| `production_changes_only_by_people`, `every_limit_has_an_owner` | From `keel-limits` |

## Behaviour to know about

- **One immediate anomaly alert.** Each immediate subscription an anomaly
  matches emits its own Anomaly Detected event. So the module keeps one, from
  `alert.min_impact_absolute`, and the control plane routes the event by
  impact. Its SNS copy goes to `<name>-anomaly-alerts`, for people only.
  Digests are e-mail.
- **Limits alert by severity.** Each limit's thresholds publish to the severity
  topics, and those reach the control plane as `keel.<severity>`. The tiers and
  fields are [`keel-limits`](../keel-limits)'. A limit's action may apply an SCP
  (`action.scp`).
- **Commitment targets** become budgets on Savings Plans and RI utilization
  and coverage. Each alerts WARNING below its target.
- **Billing views** are slices of the primary view, by accounts or by one
  tag. The accounts they are shared with read them in Cost Explorer without
  management account access.
- **FinOps Agent is set up from its console, not by Terraform.** Turning on
  trusted access in AWS Organizations alone does not complete the agent's
  organization setup, so the module creates nothing for it. With
  `finops_agent.enabled` it emits `finops_agent_setup`: the console steps in
  us-east-1, the delegation to `delegated_admin_account_id`, the IAM policy
  the person needs, and what the agent then reads.
- **The CID source stack runs in the destination's Region**
  (`data_exports.region`), even though this module's provider is us-east-1:
  the template delivers each export to the bucket in its own Region.
- **Two managed monitors, and one per business unit.** The AWS managed
  monitors watch services and accounts, the two a management account may hold
  and the only two the provider can declare: it takes no key with a
  dimension, which TAG and COST_CATEGORY managed monitors need. A business
  unit is a cost category value with its own customer managed monitor
  (`cost_category_values`); a new value needs adding there. A team's own scope
  is watched by its limit's anomaly monitor in `keel-team`.
- **Cost categories apply from the current month.** Closed months keep the
  allocation they had.
- **The account monitor follows the organization.** New accounts are
  monitored without a change here; new business units are not.
- **The data pipeline is AWS's own template,** run here with
  `CAPABILITY_NAMED_IAM`. Its version is pinned (`data_exports.version`) and
  must equal `keel-insights`'. In production it comes from the estate's mirror
  (`data_exports.template_url_prefix`). `data_exports_stack.reviewed_sha256`
  and `verify_commands.template` compare the file with the reviewed copy.

## Contract outputs

| Output | For |
|---|---|
| `topic_arns` | Owners, chat or paging subscribing to the organization's limits |
| `anomaly_alert_topic_arn` | People who want the immediate anomaly alert directly |
| `billing_view_arns` | The accounts the views are shared with |
| `controls` | The controls register: FC-04, FC-05, allocation, `LIMIT-<name>` |
| `kms_key_policy_requirements` | The key owner, when the topics use a customer key |
| `deployer_requirements` | Whoever grants the Terraform role its permissions |
| `verify_commands` | Read-only checks from CloudShell after an apply |
| `governance` | Change review: categories, monitors, alerts, limits, views, agent, exports |

## Limits

- **Never applied against real AWS.** Checked against the provider at 6.57.1,
  AWS documentation and the CID templates. The open points are in
  [docs/RESEARCH.md](docs/RESEARCH.md), marked Unverified. Among them:
  - billing views shared through RAM;
  - cross-Region forwarding to the control plane.
- **FinOps Agent is a preview.** Its scope, Regions and price can change.
- **Usage type group names in the examples are illustrative.** Take them from
  Cost Explorer.
- Guardrails (tag policies, SCPs, the model allow-list, the AI opt-out) are in
  `keel-guardrails`; routing and evidence in `keel-control-plane`.

## Versioning and support

Semantic versioning; tags `keel-billing-vX.Y.Z`. Breaking: removed or renamed
inputs and outputs, new required inputs, changed defaults, replaced resources,
raised version floors. Changes are in [CHANGELOG.md](CHANGELOG.md); costs in
[COSTS.md](COSTS.md).
