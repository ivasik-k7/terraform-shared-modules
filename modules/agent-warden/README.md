# agent-warden

**The warden lets the agent work — watched, capped, attributable, and killable.**

Governed AWS access for an autonomous AI agent (e.g. Claude Code) on a **shared account**,
where the two hard problems are *attribution* ("who told the AI to do that?") and
*blast radius* ("how far could it get?").

The module gives you one SSO-assumable role whose every session is tied to a human,
capped by a permission boundary that no team grant can breach, and — optionally — a
runtime layer that **watches** that role, **contains** it on a budget breach, and
gives you a **break-glass** path when read-only isn't enough.

Provision it centrally (Terraform Cloud), not per developer.

## Model

```
 SSO user ──assume (SourceIdentity + MFA + IP + not-expired)──▶  AI role
                                                                   │
                              permissions = ReadOnlyAccess         │  ← identity policy (the tier)
                                          ∩ permission boundary     │  ← hard ceiling (deny wins)
                                          + team_grants (still capped)
```

- **Trust** answers *who / when / where / how strongly authenticated* may assume.
- **Boundary** is the hard ceiling: dangerous actions, data exfiltration, and
  cross-region calls are denied and stay denied even if a team grant allows them.
- **Identity policy** is the tier: read-only by default, widened per team in code.

## Quick start — one instance per team (the pattern)

Instantiate the module **once per team**, not once with pooled `team_grants`.
Grants pooled on a single role leak across teams at runtime (any human who can
assume gets every team's grants); separate instances make permissions, budget,
alerts, digest, and the kill switch **per-team automatically**:

```hcl
module "ai_agent_platform" {
  source = "path/to/modules/agent-warden"

  name                     = "claude-agent-platform"
  sso_permission_set_names = ["PlatformEngineer"]
  allowed_regions          = ["us-east-1"]

  team_grants = [{ sid = "SandboxWrite", actions = ["s3:PutObject"], resources = ["arn:aws:s3:::plat-sandbox/*"] }]

  enable_budget_guardrail = true
  monthly_budget_usd      = 300
  budget_cost_tag         = { key = "Purpose", value = "ai-agent-platform" }
}

module "ai_agent_data" {
  source = "path/to/modules/agent-warden"

  name                     = "claude-agent-data"
  sso_permission_set_names = ["DataEngineer"]
  allowed_regions          = ["us-east-1"]
}
```

Single-team accounts can of course run one instance:

```hcl
module "ai_agent" {
  source = "path/to/modules/agent-warden"

  name                     = "claude-agent"
  sso_permission_set_names = ["Developer"]   # who may assume
  allowed_regions          = ["us-east-1"]
}
```

Point the agent at it (JIT creds, no long-lived keys, human stamped on every call):

```
# terraform output -raw credential_process  →  ~/.aws/config
[profile ai-agent]
region = us-east-1
credential_process = bash -c 'aws sts assume-role --role-arn <arn> \
  --role-session-name "$USER" --source-identity "$USER" ... '
```

## Identity controls (trust layer)

| Variable | Default | Effect |
|---|---|---|
| `sso_permission_set_names` | — (required) | Permission-set names allowed to assume. |
| `require_source_identity` | `true` | Assume is refused unless a `SourceIdentity` (the human) is set — fail-closed attribution. |
| `require_mfa` | `false` | Assume requires MFA in the originating SSO session. |
| `allowed_source_ip_cidrs` | `[]` | Assume only from these CIDRs (TFC / VPN egress). |
| `access_expires_at` | `""` | RFC3339 instant after which the role can no longer be assumed — a **self-expiring identity**, no cleanup job. |
| `max_session_duration` | `3600` | Short sessions; the agent re-assumes. |

## Guardrails (boundary layer)

| Variable | Default | Effect |
|---|---|---|
| `attach_read_only` | `true` | AWS-managed `ReadOnlyAccess` baseline. |
| `deny_data_exfiltration` | `true` | Denies value reads (secrets, SSM params, KMS decrypt, S3 objects, DynamoDB items, SQS/Kinesis, Athena/log results, EC2 password data, Lambda env). AI sees infra *shape*, not *data*. |
| `data_read_exceptions` | `[]` | Resource ARNs the exfil deny skips (via `NotResource`) — grant one secret without dropping the guard. |
| `allowed_regions` | `["us-east-1"]` | Cross-region calls denied (global services exempt). |
| `extra_denied_actions` | `[]` | Extra hard denies. |
| `enforce_cost_tag_on_create` | `false` | Deny listed create actions unless the request carries `budget_cost_tag.key` — untagged creates are invisible to the budget guardrail. Curated action list in `cost_tag_enforced_actions` (only services documenting `aws:RequestTag`). |
| `kill_switch` | `false` | Flip to deny **all** actions instantly (incident response). |
| `exclusive_inline_policies` | `false` | Terraform removes inline policies it doesn't manage (drift, or the emergency deny-all). Trade-off: an apply after a budget breach lifts containment — gate applies during incidents. |

Dangerous actions (IAM escalation/destruction, org/billing, Identity Center,
audit/security-control tampering, KMS deletion, S3 public exposure) are **always**
denied by the boundary.

## Extending per team

```hcl
team_grants = [{
  sid       = "PlatformS3Write"
  actions   = ["s3:PutObject"]
  resources = ["arn:aws:s3:::platform-sandbox/*"]
}]
```

Grants layer on the baseline and are still capped by the boundary. To let a team
read a specific secret, add its ARN to `data_read_exceptions` *and* grant the action.

## Runtime layer (all opt-in)

| Feature | Toggle | What it does |
|---|---|---|
| **Active alerting** | `enable_alerting` | EventBridge → SNS on high-risk AI actions and on every break-glass assumption. Recordable attribution becomes *watched*. |
| **Daily digest** | `enable_daily_digest` | Scheduled Lambda summarises the last 24h (who / what / how often) to SNS. Set `digest_event_data_store_arn` (CloudTrail Lake) for server-side SQL that scales to busy shared accounts; the LookupEvents fallback flags truncated scans instead of under-reporting silently. |
| **Budget guardrail** | `enable_budget_guardrail` | Tracks AI-attributed spend (by cost tag) against `monthly_budget_usd`; alerts on ACTUAL thresholds plus a FORECASTED threshold (`budget_forecasted_threshold_percent`) that fires before the money is gone. |
| **Auto containment** | `enable_budget_killswitch` | On final-threshold breach, a Lambda attaches an emergency deny-all to the role — automatic blast-radius zero. Containment can't fail silently: failed invocations land in a DLQ and page the alerts topic via a CloudWatch alarm. Codify afterward with `kill_switch = true`. |
| **Break-glass** | `enable_break_glass` | Separate elevated role, **always** MFA + SourceIdentity gated, short-lived, and alerted on every use. Trusts `break_glass_sso_permission_set_names` (a smaller senior group). |

## The org-level outer wall (SCP)

The boundary is account-local — anyone with `iam:*` in the account could lift it.
Set `provisioner_principal_arns` (your TFC workspace role) and the module renders
`scp_policy_json`: an SCP denying **everyone else** the ability to touch the AI
role, its trust, its policies, or its boundary. Attach it via your org-management
stack. The killswitch Lambda's role is auto-exempted so containment keeps working.

## Reviewable, lintable policies

`boundary_policy_json`, `trust_policy_json`, `team_grants_policy_json`, and
`scp_policy_json` render even with `create = false` — `tests/render/` uses that to
produce the documents offline (no credentials), and CI lints them with
[parliament](https://github.com/duo-labs/parliament) (`tests/lint_policies.py`).
This gate catches malformed condition operators, unknown action prefixes, and
escalation paths that `terraform validate`/`test` structurally cannot.

Notifications share one SNS topic; bring your own with `alert_sns_topic_arn` or let
the module create one and subscribe `alert_emails`. The auto-containment Lambda hangs
off a **separate, dedicated** topic wired only to the final budget threshold, so a
digest or an ordinary alert can never trip it.

### Prerequisites & sharp edges

- **CloudTrail must be on.** Alerting (EventBridge) and the digest (`LookupEvents`)
  both read CloudTrail management events. Most accounts have this; the module does
  not create a trail.
- **SNS encryption.** The module does not SSE the topics by default: the AWS-managed
  `alias/aws/sns` key cannot grant `events`/`budgets` publish rights, which would
  silently break delivery. Pass a properly-scoped CMK via `alerts_kms_key_id` if you
  need encryption at rest.
- **BYO topic.** If you set `alert_sns_topic_arn`, you own its access policy - grant
  `events.amazonaws.com` and `budgets.amazonaws.com` `sns:Publish` yourself.
- **Break-glass audience.** By default break-glass trusts the same principals as the
  read-only role. Set `break_glass_sso_permission_set_names` to a smaller senior group.
- **The boundary guards escalation/exfil/region, not destruction.** Read-only-ness
  comes from the `ReadOnlyAccess` tier; a `team_grant` you write can permit destructive
  writes (they're capped only against escalation/exfil). Grant narrowly and rely on
  `high_risk_event_names` alerting to watch what you open.
- **CMK-encrypted data needs the key in the exceptions too.** For a secret/parameter
  encrypted with a customer-managed KMS key, `data_read_exceptions` must include the
  key ARN as well (the boundary denies `kms:Decrypt` everywhere else).
- **The emergency deny-all is not removed by `terraform apply`.** The killswitch
  Lambda adds it out-of-band; stand down explicitly with
  `aws iam delete-role-policy --role-name <role> --policy-name ZZZ-EMERGENCY-DENY-ALL`
  after codifying with `kill_switch = true`.
- **Break-glass assume alerts are regional.** Calls to the global STS endpoint land in
  us-east-1's event bus; deploy the module (or at least alerting) there, or ensure
  clients use regional STS endpoints, for the assume alert to fire.
- **Budgets data lags.** Cost data feeds Budgets with up to ~8-24h delay, so the
  budget killswitch is containment for runaway spend, not a real-time circuit breaker.

## Outputs

`role_arn`, `role_name`, `permission_boundary_arn`, `break_glass_role_arn`,
`alert_topic_arn`, `kill_switch_engaged`, `access_expires_at`, `credential_process`
(drop-in `~/.aws/config` profile — works in both attribution modes), plus the
rendered documents: `boundary_policy_json`, `trust_policy_json`,
`team_grants_policy_json`, `scp_policy_json`.

## Testing

`terraform test` runs 30 plan-level checks against a mocked AWS provider — trust
conditions, boundary denies, exceptions, grant-condition shape, and every runtime
feature's resource graph, plus negative validation cases. CI additionally renders
the policy documents offline and lints them with parliament. These prove wiring and
policy content without credentials; a real `assume + apply` in a sandbox is the
final gate that AWS accepts the resources.
