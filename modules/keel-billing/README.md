# keel-billing

Keel's management-account module: AWS's own cost management, configured as code
for the whole organization. It covers:

- **Allocation.** Allocation tags and cost categories, the owner taxonomy.
- **Recommendations.** The free recommendation services.
- **Anomalies.** Cost Anomaly Detection with AWS managed monitors.
- **Limits.** Organization limits and commitment targets, alerting by
  severity, through [`keel-limits`](../keel-limits).
- **Billing views.** Shared billing views for the FinOps account and for teams.
- **FinOps Agent.** Organization access for AWS FinOps Agent.
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
    cost_categories = ["Team"]
    alert           = { emails = ["finops@example.com"] }
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
| FinOps Agent | A data-residency decision: it stores data in us-east-1 and infers in the US. The organization's `aws_service_access_principals`, if managed in Terraform elsewhere, must ignore it (below) |
| Dashboards | For `data_exports`, `keel-insights` deployed first in the destination account |

## What the module refuses

| Refused | Why |
|---|---|
| A cost category rule with both accounts and a tag, or neither | A rule has one expression |
| A digest without emails | Digests go by e-mail; the immediate alert goes to its topic |
| A limit with its own anomaly monitor | The managed monitors cover the organization; its alerts would reach the control plane twice |
| A limit named `sp-*` or `ri-*` | Those names are the commitment targets' |
| A billing view on accounts and a tag, or neither | A view filters on one dimension |
| A delegated FinOps Agent administrator without `enabled` | Delegation needs trusted access |
| Plus everything [`keel-limits`](../keel-limits) refuses | A limit that cannot be a budget |

### Advisory checks

| Check | Fires when |
|---|---|
| `somebody_hears_an_anomaly` | The immediate alert is off with no digests, or has neither emails nor a control plane |
| `every_cost_category_is_watched` | A cost category has no anomaly monitor |
| `spend_is_allocated_by_tags` | A cost category uses a tag key that is not activated here, so its rule matches no spend |
| `anomaly_events_reach_the_control_plane` | Forwarding is on but the provider is not in us-east-1 |
| `commitments_are_watched` | No commitment target |
| `finops_agent_data_stays_in_the_us` | FinOps Agent is on: acknowledge once the data-residency approval exists |
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
- **FinOps Agent** is enabled through Organizations trusted access, and
  administered from `delegated_admin_account_id`. AWS recommends enabling
  trusted access through the service's own console, which may do more setup.
  If the agent's console asks to finish setup after the apply, let it. If the
  organization resource is managed in Terraform with
  `aws_service_access_principals`, add `finops-agent.amazonaws.com` there, or
  ignore changes to it. The two otherwise undo each other.
- **Cost categories apply from the current month.** Closed months keep the
  allocation they had.
- **Managed monitors follow the organization.** New accounts and category
  values are monitored without a change here.
- **The data pipeline is AWS's own template.** Its version is pinned
  (`data_exports.version`) and must equal `keel-insights`'.

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
  - FinOps Agent trusted access by API;
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
