# keel-insights

Keel's insight layer: AWS's Cloud Intelligence Dashboards (CUDOS v5, KPI, Cost
Intelligence, and plugins such as FOCUS and CORA) on Quick Sight, with the
destination side of AWS's own data pipeline: the bucket the management
accounts' exports land in, the Glue tables and the Athena workgroup. Both come
from AWS's published CloudFormation templates, pinned by version, as AWS's own
Terraform deploys them.

```hcl
module "insights" {
  source  = "app.terraform.io/<org>/keel-insights/aws"
  version = "~> 0.1"

  data_exports = { source_account_ids = ["444444444444"] }
  quicksight   = { user = "finops-admin", subscription_ready = true }
}
```

Run it in the FinOps (data) account, in the region the dashboards and the cost
data should live in. Then give each management account's `keel-billing` the
`source_requirements` output as its `data_exports`. The whole framework is in
[../keel-billing/docs/FRAMEWORK.md](../keel-billing/docs/FRAMEWORK.md).

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0` |
| Quick Sight | Enterprise subscription in this account and region, at least 10 GB of SPICE, access to S3 and Athena, and a user |
| Lake Formation | Off, or `data_exports.lake_formation = true` |
| Deployer | Broad: the templates create IAM roles, buckets, Glue, Athena, Lambda and Quick Sight assets (`deployer_requirements`) |

## What the module refuses

| Refused | Why |
|---|---|
| `quicksight.subscription_ready = false` | The dashboards template accepts only "yes" for its prerequisites, so the stack would fail |
| No foundational dashboard | The template needs one of CUDOS v5, KPI, Cost Intelligence |
| An unknown plugin ID | The plugin template would fail |

### Advisory checks

| Check | Fires when |
|---|---|
| `dashboards_have_their_data` | A dashboard is on but the table it reads is not exported (FOCUS, CORA, containers) |

## Behaviour to know about

- **Plugins deploy one after another** in a fixed order, as AWS's own Terraform
  does: in parallel they conflict over shared Quick Sight assets.
- **Template versions are pinned** and must match `keel-billing`'s.
- **Data arrives within a day** of the source side's first apply; history needs
  a backfill request to AWS Data Exports.

## Contract outputs

| Output | For |
|---|---|
| `source_requirements` | Each management account's `keel-billing` `data_exports` |
| `data_bucket` | Owners of bucket-level controls (backup, logging) |
| `dashboard_urls` | People: where the dashboards are |
| `deployer_requirements` | Whoever grants the Terraform role its permissions |
| `verify_commands` | Read-only checks from CloudShell |
| `governance` | Change review |

## Limits

- **Never applied against real AWS.** The templates and their parameters are
  read in source; deployment is not tested.
- Quick Sight seats and the subscription are outside the module.
- The dashboards' contents are AWS's; changing them is done in Quick Sight or
  through the CID tooling, not here.

## Versioning and support

Semantic versioning; tags `keel-insights-vX.Y.Z`. Changes are in
[CHANGELOG.md](CHANGELOG.md); costs in [COSTS.md](COSTS.md).
