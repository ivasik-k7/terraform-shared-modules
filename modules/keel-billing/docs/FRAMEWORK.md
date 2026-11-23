# Keel: FinOps controls as code

Keel turns a FinOps practice into Terraform: every pound has an owner, a limit,
a control and evidence. It provisions what AWS already offers for cost
management, configured and governed as code, and adds the controls AWS leaves
unjoined.

This page is the map: which module does what, in which account, in what order,
and what is not built yet. Facts behind the design, with their sources, are in
[RESEARCH.md](RESEARCH.md).

## The two platform options it provisions

| Option | What it is | Keel modules |
|---|---|---|
| A · AWS consoles | Cost Explorer, Budgets, Cost Anomaly Detection, Cost Optimization Hub and Compute Optimizer, used as they come | `keel-billing` configures them for the whole organization; `keel-team` for each team |
| B · AWS native with dashboards | A, plus the Cloud Intelligence Dashboards (CUDOS v5, KPI, Cost Intelligence, FOCUS, CORA) on Quick Sight in the FinOps account's region | A, plus `keel-billing`'s `data_exports` and `keel-insights` |

Both read the same AWS exports (CUR 2.0, FOCUS 1.2, Cost Optimization Hub), so
changing the insight layer later loses no data.

## Layers and modules

| Layer | What it does | Module | Account, Region | Status |
|---|---|---|---|---|
| L1 Foundation | Exports, cost categories, allocation tags, optimisation hubs, billing views | `keel-billing` | Management, us-east-1 | Built |
| Insight | Cloud Intelligence Dashboards, Glue, Athena | `keel-insights` | FinOps, home Region | Built |
| L2 Guardrails | Tag policy, SCPs (untagged creation, model allow-list), AI services opt-out | `keel-guardrails` | Management | Built |
| L2 Cost gate | Plan-time cost check in HCP Terraform | `keel-team/policies/cost-gate.sentinel` | HCP Terraform | Built (policy file) |
| L3 Meters | Limits by any scope, commitment targets, anomaly monitors, token meters, quota ceilings, invocation logs | `keel-limits` (engine), `keel-billing` (organization), `keel-team` (account) | Management, team | Built |
| L3 Signals | Severity topics per account and Region, forwarded to the control plane | `keel-signals` | Every account and Region with signals | Built |
| L4 Control plane | Event bus, severity routing, evidence store | `keel-control-plane` | FinOps, home Region | Built |
| L5 Actuators | Locks and SCPs at a limit, running hours for non-production | `keel-limits` (actions), `keel-team` (schedules) | Team, management | Built |
| Assistant | AWS FinOps Agent, organization-wide | `keel-billing` (`finops_agent`) | Management, delegated to FinOps; us-east-1 | Built (preview service) |

Every alert travels the same way: a threshold publishes to a severity topic
(`keel-signals`), the topic's pipe puts it on the account's default bus as
`keel.<severity>`, and a rule forwards it to the control plane's bus, which
routes it to that severity's topic and keeps it as evidence. Anomaly Detected
events from the management account go the same way and are banded by impact
there. Every module reports its controls as data (`output.controls`).

## Limits: one engine

`keel-limits` turns a limit into a budget, wherever it sits:

| Need | Limit |
|---|---|
| A team's account | An unscoped COST limit in `keel-team` (FC-01) |
| Several platforms in one account | `keel-team`'s `platforms`: one limit each on `Platform = <name>` (the key is `platform_tag_key`) |
| A platform across accounts | A `keel-billing` limit with `scope.tags` |
| A business unit | A `keel-billing` limit with `scope.cost_categories` |
| A service line (Bedrock), a Region, data transfer | `scope.services`, `scope.regions`, `scope.usage_type_groups` |
| Unusual spend on exactly that scope | `anomaly = {}` on a team limit |
| Commitments bought and idle, or not bought | `keel-billing`'s `commitments`: SP and RI utilization and coverage |
| Stop at the limit | `action`: a deny policy on roles (sandbox, non-production) or an SCP (management account) |

Tiers decide severity and automation: production alerts HIGH at 100% and
CRITICAL at 120% and never acts without a person (`MANUAL`); non-production
and sandboxes may lock automatically.

## Regions

| Module | Region | Why |
|---|---|---|
| `keel-billing` | **us-east-1** | Billing, Budgets, Cost Explorer and Data Exports APIs, Cost Anomaly Detection's events, and FinOps Agent are there |
| `keel-guardrails` | Any (Organizations is global); run it with `keel-billing` | |
| `keel-control-plane`, `keel-insights` | The FinOps account's home Region, **London (eu-west-2)** | Evidence, dashboards and the people reading them stay in the UK |
| `keel-team` | Once per account in its home Region (`components` default), then once per other Region with `{ account = false }`: **London and Ireland (eu-west-1)** | Budgets are global; topics, alarms, Bedrock profiles, quotas, invocation logs and schedules are regional |
| `keel-signals` | Wherever something publishes: inside `keel-team` and `keel-billing` | A topic receives only its own Region's alarms |

What crosses Regions, and what it carries:

| Path | Carries |
|---|---|
| us-east-1 (management) → London (control plane) | Budget and anomaly signals: amounts, account IDs, tag values |
| Ireland → London | The same for Ireland's alarms |
| AWS billing metadata | Processed in us-east-1 for every customer, whatever Keel does |
| FinOps Agent | The organization's cost and resource data, stored in us-east-1, inference in the US |

## AWS FinOps Agent

FinOps Agent is in preview in **us-east-1 only**. It answers cost questions and
investigates anomalies across the organization. It reads through a
service-linked role (`AWSServiceRoleForFinOpsAgent`) that SCPs do not restrict,
keeps its data in us-east-1 and runs inference within the US geography. Keel
does not change any of that. It gives three decisions their place in code:

| Decision | Where |
|---|---|
| Turn it on, administered from the FinOps account | `keel-billing`'s `finops_agent` (trusted access, delegated administrator) |
| Accept that its data leaves the UK and EU | `finops_agent_data_stays_in_the_us`: warns until acknowledged, so the approval is in the configuration |
| Keep AWS from using the organization's content to improve the service | `keel-guardrails`' `ai_services_opt_out` |

London and Ireland workloads need nothing else. The agent reads the
organization's billing data, which is already in us-east-1, and creates its own
EventBridge rule for anomaly events. Until the data-residency approval exists,
Keel without the agent covers the same ground, more slowly: CID dashboards in
London and anomalies on the control plane.

## Accounts and order

```
Management account, us-east-1                FinOps account, London               Team accounts, London (+ Ireland)
┌──────────────────────────────┐   exports   ┌───────────────────────────┐        ┌──────────────────────────────┐
│ keel-billing                 │────────────▶│ keel-insights             │        │ keel-team (per account,      │
│  tags, categories, hubs      │             │  CID pipeline (dest.)     │        │            per Region)       │
│  anomaly monitors            │             │  dashboards, Quick Sight  │        │  limits, platforms, AI caps  │
│  org limits, commitments     │  signals    │ keel-control-plane        │signals │  topics, burn meter, logs    │
│  billing views, FinOps Agent │────────────▶│  bus, severity, evidence  │◀───────│  schedules, FinOps role      │
│ keel-guardrails              │             └───────────────────────────┘        └──────────────────────────────┘
└──────────────────────────────┘
```

1. **FinOps account, London, `keel-control-plane`.** The bus and the severity
   topics; subscribe chat and paging to the topics. Its `event_bus_arn` goes to
   every other module.
2. **FinOps account, London, `keel-insights`.** Needs Quick Sight Enterprise
   and a user first. Creates the bucket the exports land in. Its
   `source_requirements` output is what step 3 sets.
3. **Management account, us-east-1, `keel-billing`.** `data_exports` from step
   2's output. Exports start within a day; AWS backfills history on request.
   Activate `Team`, `Application` and `Platform` here before step 5, or the
   platform limits and AI caps see no spend.
4. **Management account, `keel-guardrails`.** On a pilot OU first, with a
   break-glass role exempt; teams' providers get `tag_policy_compliance`.
5. **Team accounts, `keel-team`.** In London with the defaults, then in
   Ireland with `components = { account = false }`.
6. **HCP Terraform.** Turn on cost estimation, add `cost-gate.sentinel` to a
   policy set as soft-mandatory, with each team's limit from `plan_gate`.
7. **FinOps Agent**, once the data-residency approval exists:
   `finops_agent.enabled` in step 3, acknowledged.

## The controls register

Each module reports the controls it implements in `output.controls`, keyed by
register ID. Merged across modules, that is the register's evidence column.

| ID | Control | Type | Module |
|---|---|---|---|
| FC-01 | Every account is created with an owner and a budget | Prevent | `keel-team` (account limit) |
| FC-02 | Resources missing mandatory tags are denied | Prevent | `keel-guardrails` |
| FC-03 | A plan above budget headroom needs approval | Prevent | `cost-gate.sentinel` |
| FC-04 | A forecast overrun alerts the owner | Detect | `keel-limits` through `keel-billing` and `keel-team` |
| FC-05 | A cost anomaly reaches an owner within a day | Detect | `keel-billing` (detection), `keel-control-plane` (routing) |
| FC-06 | AI spend per application stays under its cap | Detect | `keel-team` (caps and burn meter; the hard stop is a gateway, not built) |
| FC-07 | Idle resources are removed or justified | Correct | Cost Optimization Hub findings (`keel-billing`), the CORA dashboard (`keel-insights`) |
| FC-08 | Every alert and action is recorded, immutably | Prove | `keel-signals` (delivery), `keel-control-plane` (testing each control monthly is a practice, not code) |
| LIMIT-* | Each limit stays within its amount or target | Detect, Correct | `keel-limits` |
| AI-MODELS, AI-OPT-OUT | Approved models only; AWS keeps no AI content | Prevent | `keel-guardrails` |

## The KPI scorecard

| KPI | Where it is measured |
|---|---|
| Spend allocated to an owner | Cost categories' default value (`keel-billing`) in the KPI and CUDOS dashboards |
| Forecast variance | Budgets' forecasts against actuals |
| Commitment coverage and utilisation | Commitment targets (`keel-billing`); KPI dashboard; Cost Optimization Hub |
| Anomaly to acknowledgement | Anomaly history; the control plane's evidence |
| Idle and orphaned spend | CORA dashboard; Cost Optimization Hub |
| AI spend attributed to an application | CUR 2.0 IAM principal data and inference-profile tags (`keel-team`) |
| Unit cost | Not from AWS data alone: needs business volumes |
| Controls tested and passing | The register from `output.controls`, with the evidence bucket |

## Where token costs are covered

AI spend is measured three ways, from the minute to the invoice, and limited
in five.

| What | How | Module |
|---|---|---|
| **Every minute: the burn meter** | Bedrock's token counts per model, priced from the rate card (`ai.prices`), alarm above `burn_per_hour` to the CRITICAL topic. Acts within the hour, before the bill. One per Region | `keel-team` |
| **The ceiling: quotas priced** | Each tokens-per-minute quota at the model's higher price is the most an hour can cost (`ai_ceilings`) | `keel-team` |
| **Every request: invocation logs** | Who called which model with what token counts; no prompt, response, image, embedding or video | `keel-team` (`ai.invocation_logs`) |
| **Every day: the bill by application** | Calls through each application's inference profile carry `Team`, `Application` and the platform tag into the bill | `keel-team` (profiles), `keel-billing` (tags activated) |
| **The bill by calling role** | CUR 2.0 `line_item_iam_principal` (IAM principal data, Bedrock only, from April 2026) | `keel-billing` (`data_exports.iam_principal`) |
| **A cap per application** | A limit on the `Team` and `Application` tags, alerts at 50, 80, 90 and 100%, every Region | `keel-team` |
| **The whole AI line** | An organization limit on `scope.services = ["Amazon Bedrock"]`; spikes caught by the per-service anomaly monitor | `keel-billing` (`limits`, `anomaly_detection`) |
| **Approved models only** | SCP denying calls to other models or Regions | `keel-guardrails` |
| **A runaway sandbox stops** | The lock's deny list includes `bedrock:InvokeModel*` | `keel-limits` (action) |
| **Seeing it** | CUDOS v5, FOCUS and Cost Intelligence break Bedrock cost down by tag and account | `keel-insights` |
| **Asking about it** | FinOps Agent, once approved | `keel-billing` (`finops_agent`) |
| **Cost gate** | Not for tokens: plan-time estimates price provisioned resources, not usage | |

Not covered yet:

| Gap | Why | What would close it |
|---|---|---|
| A hard stop at an application's cap | Budgets alert hours late; Bedrock has no quota per application, and Service Quotas cannot lower one | An AI gateway (AgentCore Gateway or a proxy) that throttles per key |
| Other providers' tokens (direct model APIs) | Not on the AWS bill | Their usage reports loaded into the FOCUS tables |
| Seats (Kiro, Amazon Q) | On the AWS bill per user; no per-team cap | Not designed: allocating seat lines by user to a team |
| Unit economics, owner workflow, dependency graph, an analyst on Keel's own data | Deferred to the month-6 gate | The practice plan's canopy phase |

## Rules that hold everywhere

- **Tags hold no customer or personal data.** AWS processes billing metadata
  in us-east-1 for every customer.
- **Production is never changed automatically.** The production tier has
  `automatic_actions = false`; an automatic action there warns
  (`production_changes_only_by_people`).
- **Thresholds scale by tier.** Severity marks, anomaly floors and automation
  come from the limit's tier, so a small team is not paged for a large team's
  noise.
- **One path per signal.** A signal reaches the control plane once: through a
  severity topic, or as the Anomaly Detected event, never both.
