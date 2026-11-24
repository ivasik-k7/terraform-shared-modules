# keel-control-plane

Keel's control plane, in the FinOps account: one event bus every account sends
its cost signals to, routing by severity to four topics (INFO, WARNING, HIGH,
CRITICAL), and every signal kept as evidence in an Object Lock bucket. No code:
EventBridge patterns route, Data Firehose records.

```hcl
module "control_plane" {
  source  = "app.terraform.io/<org>/keel-control-plane/aws"
  version = "~> 0.1"

  sources  = { organization_id = "o-abcdefghij" }
  severity = { emails = { high = ["finops@example.com"], critical = ["finops-oncall@example.com"] } }
}
```

Give `event_bus_arn` to `keel-billing` and every `keel-team` as
`signals.control_plane_bus_arn`. The whole framework is in
[../keel-billing/docs/FRAMEWORK.md](../keel-billing/docs/FRAMEWORK.md).

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Account | The FinOps account, in the region evidence should live in |

## How signals are routed

| Signal | From | Severity |
|---|---|---|
| Cost anomaly | `keel-billing` (Anomaly Detected events) | By total impact: below `anomaly_warning` INFO, then WARNING, HIGH, CRITICAL |
| Alarm entering ALARM | `keel-team` (and any forwarded alarm) | CRITICAL if the name ends `critical_alarm_suffix` (the AI burn meter), else HIGH |
| Keel event | anything that puts `source = "keel"` | Its `detail.severity` |
| Signal from an account's severity topic | `keel-signals` (budgets, limit anomalies, alarms), source `keel.<severity>` | The topic's severity; the message is `detail.sns.Message` |

Every message carries context: the anomaly's dimension, account, impact and
console link, or the alarm's name, account and reason.

## What the module refuses

| Refused | Why |
|---|---|
| Impact bands out of order | WARNING < HIGH < CRITICAL |
| No organization and no accounts | Nobody could send |
| A name over 19 characters | The Firehose role's name prefix, `<name>-evidence-firehose-`, may be 38 |

### Advisory checks

| Check | Fires when |
|---|---|
| `evidence_is_immutable` | The evidence bucket is in GOVERNANCE mode: removable by anyone with bypass rights |
| `every_severity_reaches_someone` | WARNING, HIGH or CRITICAL has no e-mail subscriber |

## Behaviour to know about

- **Only `keel-signals`' forwarding roles may put events** from other
  accounts (`sources.principal_arn_patterns`, by default
  `arn:*:iam::*:role/*-signal-forward-*`). Without it any role in the
  organization could page CRITICAL and write a record the evidence lock keeps.
  The FinOps account's own identities need only their IAM permissions.
- **Evidence is everything on the bus**, compressed, under
  `events/yyyy/MM/dd/`, locked for `retention_days`, deleted after. The bus
  also archives events for `archive_days` for replay.
- **COMPLIANCE cannot be undone.** Start in GOVERNANCE; switch when the
  pipeline is accepted.
- **The control plane watches itself:** an alarm on undelivered signals (the
  dead-letter queue) and on failed evidence delivery, both to HIGH.
- **Test it** with `verify_commands.test_signal`, then find the event with
  `verify_commands.evidence`.

## Contract outputs

| Output | For |
|---|---|
| `event_bus_arn` | `keel-billing` and `keel-team` |
| `topic_arns` | Chat, ticketing and paging tools |
| `routing` | The register and on-call: what is which severity |
| `controls` | The register: FC-05, FC-08 |
| `kms_key_policy_requirements` | The key owner |
| `deployer_requirements`, `verify_commands`, `governance` | Platform, operators, reviewers |

## Limits

- **Never applied against real AWS.** That Data Firehose writes to a bucket
  with default Object Lock retention (which needs an integrity header on every
  upload) is not proven; the failed-delivery alarm says so if it does not
  ([../keel-billing/docs/RESEARCH.md](../keel-billing/docs/RESEARCH.md)).
- No de-duplication across sources beyond routing each signal once.
- Ticketing and paging integrations subscribe to the topics outside the module.

## Versioning and support

Semantic versioning; tags `keel-control-plane-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
