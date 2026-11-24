# keel-signals

Keel's per-account, per-Region signal layer. It creates four severity topics:
INFO, WARNING, HIGH and CRITICAL. Budgets, Cost Anomaly Detection and
CloudWatch may publish to them. Owners subscribe by severity.

With a control plane bus, everything published also reaches the
[`keel-control-plane`](../keel-control-plane) bus as `keel.<severity>`, where it
is routed and kept as evidence. [`keel-team`](../keel-team) and
[`keel-billing`](../keel-billing) are built on it.

```hcl
module "signals" {
  source  = "app.terraform.io/<org>/keel-signals/aws"
  version = "~> 0.1"

  name                  = "lending"
  emails                = { high = ["lending-leads@example.com"] }
  control_plane_bus_arn = "arn:aws:events:eu-west-2:333333333333:event-bus/keel"
}
```

## How a signal travels

1. A budget threshold publishes to the severity topic.
2. The topic delivers to its own SQS queue.
3. That queue's pipe puts the message on the account's default bus: source
   `keel.<severity>`, detail type `Keel Signal`, the SNS envelope in
   `detail.sns`, the queue in `resources`.
4. A rule on the default bus forwards this instance's `keel.*` events (matched
   on `resources`) to the control plane bus, in this or another account and
   Region.

Each severity has its own queue because a pipe deletes the SQS messages its
filter does not match; pipes sharing a queue lose each other's signals. The
detour through the default bus exists because a pipe can target only the
default bus of its own account and Region. Alarms entering ALARM and Anomaly
Detected events can be forwarded as they are too (`forward`).

A message the pipe fails five times moves to `<name>-signals-undelivered`;
`<name>-signals-undelivered` and `<name>-signals-stalled` (a signal waiting
over 15 minutes) alarm on the HIGH topic, which reaches the owners by e-mail
even when the pipes cannot.

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Control plane | Its bus policy allows this account (`keel-control-plane`, `sources`) |
| Region | One call per account and Region that has signals; anomaly events exist only in us-east-1 |

## What the module refuses

| Refused | Why |
|---|---|
| E-mails on a severity other than info, warning, high or critical | There is no such topic |

## Behaviour to know about

- **Topics are per Region.** An alarm notifies a topic in its own Region, so
  every Region with alarms needs its own call. Budgets are global; `keel-team`
  points them at the topics of its home Region.
- **Each subscription confirms.** E-mail subscribers must confirm before they
  receive anything.
- **Forwarded alarms and topic signals are two paths.** An alarm that
  notifies a severity topic *and* matches `forward.alarm_name_prefixes`
  reaches the control plane twice. Use one or the other per alarm.
- **Several instances per account and Region are fine.** Each forwards only
  its own queues' events; `name` must differ.

## Contract outputs

| Output | For |
|---|---|
| `topic_arns` | `keel-limits`, and every alarm that should reach owners |
| `forwarding` | Reviewers: what leaves the account |
| `kms_key_policy_requirements` | The key owner: the publishing services, SNS to the queues, and the pipes' role |
| `verify_commands` | Operators |

## Limits

- **Never applied against real AWS.** The open points are in
  [../keel-billing/docs/RESEARCH.md](../keel-billing/docs/RESEARCH.md). Among
  them:
  - the pipe's input template carrying the parsed SNS envelope into
    `detail.sns` (documented for SQS bodies, never observed);
  - cross-account and cross-Region forwarding.

## Versioning and support

Semantic versioning; tags `keel-signals-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
