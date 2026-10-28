# terraform-aws-s3

One S3 general purpose bucket, private and encrypted by default, with
everything that usually ends up bolted on later: a bucket policy that refuses
plaintext and old TLS, lifecycle rules that bound what grows unseen,
replication, Object Lock, access logging, notifications, inventory, and the
contracts every other party needs - key owners, destination owners, readers.

```hcl
module "orders" {
  source  = "app.terraform.io/CTO/s3/aws"
  version = "~> 0.1"

  name           = "orders-data"                # -> orders-data-<account>-<region>
  kms_key_arn    = var.orders_key_arn            # same region
  access_logging = { target_bucket = var.log_bucket }
}
```

Only `name` is required. With nothing else set the bucket is versioned,
encrypted with SSE-S3, private (all four Block Public Access settings, ACLs
disabled), reachable only over TLS 1.2 or later, and expires old versions
after 90 days and abandoned uploads after 7.

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| `hashicorp/aws` | `>= 5.100.0, < 7.0.0`: tested on 5.100.0 and the newest 6.x |
| The deployer | `s3:*` on the bucket's configuration; `iam:CreateRole` and `iam:PutRolePolicy` when the module creates the replication role |

Both provider majors are supported so the module can share a workspace with
the many modules still below 6.0 (one workspace has one provider version).
Two S3 features need provider v6 and are left out until the floor moves:

| Not offered | Why it matters | Meanwhile |
|---|---|---|
| The account regional namespace (`bucket_namespace`, v6.37) | Names no other account can ever create, even after a delete | `name_suffix = "account-region"` makes names unique per account and region, but in the shared namespace |
| Managing SSE-C blocking (`blocked_encryption_types`, v6.40) | Customer-provided keys can be re-enabled per bucket | S3 blocks SSE-C on new buckets by default since April 2026; `verify_commands.encryption` shows the setting |

Keys, buckets, roles, queues and topics can be created in the same root as
the module: what exists is decided by map keys and switches, never by
whether an ARN or a name is empty, so values unknown at plan do not break it.

## What it refuses at plan

Each would fail at apply after the bucket exists, or succeed and do the
wrong thing.

| Refused | Why |
|---|---|
| A name over 63 characters with its suffix; dots; AWS's reserved prefixes and suffixes (`xn--`, `sthree-`, `amzn-s3-demo-`, `-s3alias`, `--ol-s3`, `--x-s3`, `--table-s3`, `-an`) | S3's naming rules; dots break TLS on virtual-hosted addresses |
| A KMS key in another region; DSSE without a key | S3 encrypts only with keys in its region |
| Public access settings turned off without `allow_public_access` | A public bucket is almost always a mistake |
| A policy statement allowing principal `*`, or naming none; a bucket policy over 20 KB | A public bucket; S3 rejects a statement without a principal, after the bucket exists without its denies; S3's limit |
| Replication or Object Lock without versioning | S3 requires it |
| SSE-KMS replication rules without `replica_kms_key_arn` | S3 silently replicates nothing encrypted |
| Duplicate replication priorities | S3 rejects them |
| A log bucket (`access_log_sources`) with SSE-KMS, Object Lock or Requester Pays | S3 cannot deliver access logs to it |
| Logging a bucket into itself | Every delivery would log itself |
| CloudFront access with `ObjectWriter` | CloudFront documents `BucketOwnerEnforced` for Origin Access Control, and `BucketOwnerPreferred` where ACLs are still required |
| Lifecycle rules with no action, unknown storage classes, size filters that exclude everything; tiering archive days out of range | — |
| FIFO queues as notification destinations | S3 does not support them |
| `access_logging` without `target_bucket`; `replication.role_arn` without `create_role = false`, or the reverse | Logging to nowhere; a second role created and yours ignored |

## Advisory checks

Warnings that do not block the plan; name one in `acknowledged_checks` to
accept it, and the decision is listed in `output.governance`.

| Check | Warns when |
|---|---|
| `versioning_is_on` | Versioning is off: an overwrite or delete is permanent |
| `old_versions_expire` | Versioning is on and nothing expires noncurrent versions: the hidden size grows forever |
| `access_is_logged` | No server access logging (log buckets are exempt) |
| `data_uses_a_customer_key` | SSE-S3 instead of a customer managed key (log buckets are exempt) |
| `the_bucket_survives_a_destroy` | `force_destroy` is on |
| `acls_are_disabled` | `object_ownership` re-enables ACLs |
| `replication_is_monitored` | A replication rule without Replication Time Control has no metrics |

## Most-used inputs

The registry's Inputs tab is the reference; each variable's description
documents its fields.

| Input | Default | What it does |
|---|---|---|
| `name`, `name_suffix` | —, `account-region` | The bucket name |
| `kms_key_arn` | `""` (SSE-S3) | SSE-KMS with an S3 Bucket Key |
| `encryption` | bucket key, enforce key | DSSE, bucket key, deny other keys |
| `versioning` | `true` | |
| `object_lock` | off | WORM retention, enabled in place |
| `default_lifecycle` | 90 / 7 days | Old versions, abandoned uploads, orphan delete markers |
| `lifecycle_rules` | `{}` | Transitions and expirations by prefix, tags, size |
| `grants` | `{}` | Cross-account read, write or both, by prefix |
| `cloudfront_distribution_arns` | `[]` | Origin Access Control |
| `vpc_endpoint_ids`, `organization_id` | none | Data perimeter for object access |
| `access_logging` | off | This bucket's server access logs; setting `target_bucket` turns them on |
| `access_log_sources` | `[]` | Make this bucket a log bucket |
| `replication` | none | Rules to other regions or accounts, with RTC; `create_role = false` and `role_arn` to bring the role |
| `notifications` | none | EventBridge, SNS, SQS, Lambda |
| `inventory`, `request_metrics`, `intelligent_tiering`, `cors_rules` | none | |

## Contract outputs

| Output | For |
|---|---|
| `read_policy_json`, `write_policy_json` | IAM policies for principals in this account, with the key through S3 |
| `kms_key_policy_requirements` | Key owners: writers, readers, grants, CloudFront, replication. Contract v2, compiled by [modules/kms](../kms) |
| `replication_destination_requirements` | Each destination owner: the bucket policy statements and settings it needs |
| `notification_destination_requirements` | Each topic, queue and function owner: the statement S3 needs before the apply. In the same root, pass the policies' IDs in `notification_dependencies` so the notification waits for them |
| `inventory_destination_requirements` | Each inventory destination owner |
| `governance` | Change reviews and tests: the posture as data |
| `verify_commands` | CloudShell, after an apply |

## How it works

**The bucket policy** is the module's statements, then `policy_statements`.

| Statement | Effect |
|---|---|
| `DenyInsecureTransport`, `DenyOldTls` | Plaintext and TLS below `minimum_tls_version` are denied - except for AWS services acting for the account, whose requests S3 strips of network context (as the S3 documentation advises) |
| `DenyOtherEncryption`, `DenyOtherKmsKeys`, `DenyAwsManagedKey` | With `kms_key_arn`: a PutObject naming another algorithm or key is denied, and so is one asking for `aws:kms` without naming a key, which S3 encrypts under `aws/s3`. One sending no encryption header takes the default key |
| `DenyObjectAccessOutsideVpcEndpoints` | Object reads and writes only through those endpoints. Bucket configuration is never restricted, so the module cannot lock out its deployer. Requests a service makes with the caller's credentials (Athena, Glue: forward access sessions) carry no endpoint and are exempt through `aws:ViaAWSService`, as IAM documents |
| `DenyObjectAccessOutsideOrganization` | Object access only from the organization; this account and AWS services exempt |
| `<grant>List`, `<grant>Objects` | Each grant, scoped to its prefixes |
| `CloudFrontOriginAccessControl` | `s3:GetObject` for the named distributions only |
| `ServerAccessLogDelivery` | The logging service, for the named sources in this account |

**Lifecycle.** A `module-defaults` rule covers the whole bucket: old
versions expire after 90 days, incomplete multipart uploads after 7, and
delete markers with nothing behind them go. Caller rules come after it;
objects under 128 KB are not transitioned (S3's default since 2024).

**Object Lock** is enabled through `aws_s3_bucket_object_lock_configuration`,
never through the bucket's `object_lock_enabled`, which forces a
replacement. S3 allows enabling it on an existing bucket, so turning it on
later is an update. It cannot be turned off.

**Replication** uses a role `<name>-<region>-s3-replication` (or yours, with
`create_role = false`) with the
permissions the S3 documentation lists: read this bucket's versions, write
the destinations, decrypt here and encrypt there through S3, with
`kms:EncryptionContext:aws:s3:arn` naming both the bucket and its objects
(S3 Bucket Keys use the bucket ARN). Rules are V2, with a filter, a
priority and delete marker replication (off for tag-filtered rules, which
S3 does not support). Replication Time Control sets both of its parts to 15
minutes, the only value S3 accepts.

## What replaces what

From the provider source (v5.100.0): `name`, `name_suffix` (they change the
bucket name) replace the bucket - with `force_destroy` off the replace
fails on a non-empty bucket, which is the point. Everything else, including
turning Object Lock on, is an update.

## Limits

- **Never applied against real AWS.** Verified with `terraform test` against
  a mocked provider on aws 5.100.0 and 6.x, the provider schema and source,
  and the AWS documentation. The mock does not evaluate the bucket policy.
- **UNVERIFIED: that a v5 write of the encryption configuration keeps S3's
  SSE-C block.** Provider 6.40 changed the field to computed to avoid diffs
  after S3 started blocking by default, which suggests it does. Check
  `verify_commands.encryption` after the first apply.
- **The replication role name** is `name`, the region and 16 more
  characters, and IAM allows 64; the provider refuses a longer one at plan.
  Bring a role with `replication.create_role = false` for a long name.
- **The TLS denies exempt service principals but not forward access
  sessions.** Whether S3 carries `aws:SecureTransport` into a request
  Athena or Glue makes with the caller's credentials is not documented;
  confirm a query on the first rehearsal.
- **No website hosting**: serve through CloudFront with
  `cloudfront_distribution_arns`.
- **No directory buckets, access points, Multi-Region Access Points or
  Object Lambda.**
- **Cross-account replication ownership** relies on the destination's
  Object Ownership being bucket owner enforced, as AWS recommends, rather
  than owner override.
- **The VPC endpoint and organization perimeters** also apply to people:
  console users outside the endpoint cannot read objects.

## Versioning and support

Semantic versioning, tagged `s3-vX.Y.Z`, published by the HCP Terraform private
registry as `app.terraform.io/CTO/s3/aws`. The module stays at 0.x until its
first live apply confirms the items under "Limits"; while it is, a minor
release may change a default and says so under **BREAKING**. Raising the
provider floor to v6 (for the account regional namespace and SSE-C) will be
a major release.

Tests: `tests/core.tftest.hcl` (name, encryption, access, policy, Object
Lock, switches), `tests/integrations.tftest.hcl` (lifecycle, replication,
logging, notifications, inventory, features), `tests/same_root.tftest.hcl`
(keys, buckets and topics created next to the module),
`tests/guards.tftest.hcl` (each input validation and refusal) and
`tests/examples.tftest.hcl`, 90 runs; `tests/lint_validations.py`.

| Document | Question |
|---|---|
| [COSTS.md](COSTS.md) | What it costs, and which line has no ceiling |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each version |
| [examples/basic](examples/basic) | The smallest call |
| [examples/log-bucket](examples/log-bucket) | The account's server access log bucket |
| [examples/data-lake](examples/data-lake) | Customer key, tiers, cross-account read, DR replication, inventory, organization perimeter |
| [examples/cloudfront-origin](examples/cloudfront-origin) | A private origin for CloudFront |
