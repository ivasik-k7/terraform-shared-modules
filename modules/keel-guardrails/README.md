# keel-guardrails

Keel's preventive layer, as organization policies. It sets:

- the mandatory tags, as a tag policy;
- a service control policy that refuses to create resources without them;
- an approved-models list for Amazon Bedrock;
- an AI services opt-out, so AWS AI services (FinOps Agent among them) do not
  keep or learn from the organization's content.

Run it in the management account, or in a delegated policy administrator.

```hcl
module "guardrails" {
  source  = "app.terraform.io/<org>/keel-guardrails/aws"
  version = "~> 0.1"

  targets       = ["ou-ab12-pilotou1"]
  required_tags = { Team = { report_for = ["ec2:instance", "rds:db"] } }
  deny_untagged = { enabled = true, tags = ["Team"], exempt_principals = ["arn:aws:iam::*:role/break-glass"] }
}
```

The whole framework is in
[../keel-billing/docs/FRAMEWORK.md](../keel-billing/docs/FRAMEWORK.md).

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Organization | The `TAG_POLICY` and `SERVICE_CONTROL_POLICY` policy types enabled on the root, and `AISERVICES_OPT_OUT_POLICY` with `ai_services_opt_out` |
| Teams' providers | `tag_policy_compliance = "error"` (`provider_setting`) so a plan fails on a resource missing a tag the policy requires |

## What the module refuses

| Refused | Why |
|---|---|
| A policy longer than AWS Organizations accepts (SCP 10,240, tag policy 10,000, AI opt-out 2,500 characters) | The API would refuse it at apply |
| An enabled list without tags, models or regions | A policy that denies everything or nothing |
| Tag values with more than one `*` | Tag policies allow one wildcard per value |

### Advisory checks

| Check | Fires when |
|---|---|
| `guardrails_are_attached` | Policies exist but `targets` is empty |
| `someone_can_break_glass` | An SCP has no exempt principals, so a mistake in it locks out the people who would fix it |

## Behaviour to know about

- **Three different strengths.** The tag policy reports and, with
  `enforce_for`, refuses non-compliant *tag values*; the provider setting
  fails a plan; the SCP refuses an untagged *create* at the API.
- **Attach to a pilot OU first.** An SCP binds every principal in the accounts
  below its target; a wrong tag key blocks deployments there at once.
- **The model list is an allow-list by ARN.** Inference profiles pass; the
  model they route to is checked too, in every Region it may route to.
- **Maximum ten SCPs per target**, the ones already attached included.
- **The AI opt-out is about content, not access.** It stops AWS keeping the
  organization's content to improve its AI services. It does not stop the
  services being used: FinOps Agent still reads the bill, and its data still
  lives in us-east-1 (`keel-billing`, `finops_agent_data_stays_in_the_us`).

## Contract outputs

| Output | For |
|---|---|
| `provider_setting` | Every team's AWS provider block |
| `controls` | The register: FC-02, the model allow-list, the AI opt-out |
| `deployer_requirements`, `verify_commands`, `governance` | Platform, operators, reviewers |

## Limits

- **Never applied against real AWS.** The policy syntax follows AWS's
  documented examples; the default create actions' support for
  `aws:RequestTag` is not checked one by one
  ([../keel-billing/docs/RESEARCH.md](../keel-billing/docs/RESEARCH.md)).
- The management account is not bound by SCPs.
- Bedrock's own organization policy type is not used; the model list is an SCP.

## Versioning and support

Semantic versioning; tags `keel-guardrails-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
