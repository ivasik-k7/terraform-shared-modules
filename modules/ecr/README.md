# terraform-aws-ecr

Amazon ECR private repositories for a regulated estate, and the registry they
live in. Repositories from one `repositories` map: immutable tags with
exceptions, your KMS key, scanning, a lifecycle policy that bounds storage
(expiring or archiving), and repository policies for other accounts, AWS
Organizations and Lambda. The registry's own settings, managed from one
workspace per account and Region: enhanced scanning, replication, pull
through caches, creation templates for the repositories ECR creates, the
registry policy, pull-time exclusions and account settings.

**Stage:** 1.0.0 release candidate. Stable once a security review reports no
open Critical or High finding ([GOVERNANCE](../../docs/GOVERNANCE.md)).

```hcl
module "ecr" {
  source  = "app.terraform.io/<org>/ecr/aws"
  version = "~> 1.0"

  name        = "orders"
  kms_key_arn = var.ecr_key_arn # output.kms_key_policy_requirements says what its policy must allow
  tags        = { CostCenter = "cc-1042" }

  repositories = {
    "orders/api" = {
      access = { pull_principals = ["arn:aws:iam::444455556666:root"] } # a workload account
    }
    "orders/worker" = {}
  }
}
```

Hand `push_policy_json` to the CI role and `pull_policy_json` to the roles
that run the images. Re-export the contract outputs, or read them with
`tfe_outputs`: `kms_key_policy_requirements` to the key's owner (or straight
into [`modules/kms`](../kms) as a consumer), `deployer_requirements` to whoever
owns the apply role, `replication_destination_requirements` to the other
accounts, `notification_requirements` to the topic's owner.

## Requirements

| Component | Supported | What a workspace must do |
|---|---|---|
| Terraform | `>= 1.9.0` | Set the workspace's Terraform version to 1.9 or later |
| `hashicorp/aws` | `>= 6.57.1, < 7.0.0` | Commit the `.terraform.lock.hcl`, and run `terraform init -upgrade` if it pins anything older. The same floor as `modules/ecs` and `modules/asg-group`, so they share a workspace |
| Account | The ECR service-linked roles for pull through cache, templates and replication; Amazon Inspector for enhanced scanning | AWS creates them on first use if the apply role may; `output.deployer_requirements` lists the permissions |
| Network | `ecr.api`, `ecr.dkr` and the S3 gateway endpoint where images are pulled privately | The module creates no network resources; `output.network_contract` |

ARNs, principals and keys can come from resources in the same root. Which
resources and statements exist is decided by map keys and lists, never by
whether an ARN is known, so values unknown at plan do not break the plan.

## What the module refuses

These fail at plan, with a message naming the field. Each is a configuration
ECR would refuse at apply, or accept and get wrong.

| Refused | Because |
|---|---|
| A repository name ECR does not accept; more than five tag exclusions, or one with more than two `*` | `CreateRepository` and `PutImageTagMutability` reject them |
| A key alias instead of a key ARN; a key in another Region | The encryption is fixed at creation and ECR uses only a key in the repository's Region; a wrong one fails part way through the apply |
| A `*` principal in `pull_principals` or `push_principals` | Every AWS account could pull or push. Use `pull_organization_ids` |
| A lifecycle preset with both `keep_last` and `archive_unpulled_days` | Both select every image in standard storage; the module offers them as alternatives. Write `rules` for anything else |
| `archive_expire_days` below 90; a rule deleting archived images sooner | ECR cannot delete an archived image by lifecycle before 90 days |
| A rule ECR would refuse: `tagged` without exactly one of `tag_patterns` and `tag_prefixes`, patterns on `untagged` or `any`, more than four `*`, an `any` rule that is not the last of its storage class, duplicate priorities, `sinceImageTransitioned` without `archive` and `expire`, `archive` with another count type | The lifecycle policy is refused at apply ([properties](https://docs.aws.amazon.com/AmazonECR/latest/userguide/lifecycle_policy_parameters.html)) |
| A pull through cache for Docker Hub, GitHub, GitLab, Azure or Chainguard without a secret, or a secret not named `ecr-pullthroughcache/...` | ECR reads credentials only from such a secret |
| An ECR upstream in another account without `role_arn`; `url` or `role_arn` on an upstream that does not take one | ECR assumes that role to pull from another account; the others have a fixed URL |
| BASIC registry scanning with `CONTINUOUS_SCAN` | Continuous rescans are Inspector's (ENHANCED) |
| A `required_tag_keys` key missing from `tags` | Storage would be unattributable in Cost Explorer |

### Advisory checks

Seven `check` blocks warn without refusing. Each is silenced by naming it in
`acknowledged_checks`, and the decision is then listed in `output.governance`.
All are silent when `create = false`.

| Check | Warns when |
|---|---|
| `tags_are_immutable` | a repository has mutable tags: a push can move a tag to other code |
| `repositories_use_a_customer_key` | a repository has no KMS key: access cannot be revoked by key policy, and adding a key later replaces the repository |
| `storage_is_bounded` | a repository's lifecycle policy never deletes an image (disabled, or archive-only) |
| `images_are_scanned` | a repository has `scan_on_push = false` and this module does not manage registry scanning |
| `ecr_created_repositories_follow_a_template` | a pull through cache prefix, or replicas arriving from `replication_source_accounts`, have no creation template: ECR then creates mutable, AES-256 repositories with no lifecycle policy |
| `cached_images_can_refresh` | a pull through cache's template makes tags immutable, so the cache cannot follow its upstream |
| `repositories_are_not_open_to_every_account` | a repository policy statement has `Principal "*"` and no `Condition` |

## Repositories

Every entry of `repositories` is a repository named by its key. Its settings
default to the module-level inputs:

| Field | Default | Effect |
|---|---|---|
| `image_tag_mutability` | `image_tag_mutability` (`IMMUTABLE`) | `MUTABLE` lets a push move a tag (warned) |
| `tag_mutability_exclusions` | `[]` | Up to five wildcard patterns that are the exception: mutable tags in an immutable repository (`latest`), or immutable ones in a mutable one (`v*`). Sent as `IMMUTABLE_WITH_EXCLUSION` or `MUTABLE_WITH_EXCLUSION` |
| `kms_key_arn` | `kms_key_arn` | Empty everywhere: AES-256. Fixed at creation |
| `scan_on_push` | `scan_on_push` (`true`) | Basic scanning; a registry scanning configuration overrides it |
| `force_delete` | `false` | Destroy the repository even with images in it |
| `lifecycle_policy` | `lifecycle_policy` | Replaces the module's for this repository |
| `access` | none | The repository policy (below) |
| `tags` | `{}` | Added to the repository's tags; `ManagedBy` and `Module` stay the module's |

**Lifecycle.** The policy bounds what the repository costs. The preset:

| Field | Default | Rule |
|---|---|---|
| `untagged_expire_days` | `14` | Delete untagged images this many days after push |
| `keep_last` | `100` | Keep the newest N images of any tag, delete the rest |
| `archive_unpulled_days` | `0` | Instead of `keep_last`: move images not pulled for N days to archive storage ($0.04 against $0.10 per GB-month, billed for at least 90 days, $0.03 per GB to restore) |
| `archive_expire_days` | `0` | Delete archived images N days after archiving (90 or more) |

`rules` replaces the preset with your own (`priority`, `tag_status`,
`tag_patterns` or `tag_prefixes`, `storage_class`, `count_type`, `count`,
`action`); `enabled = false` sends no policy. ECR applies a new policy within
24 hours: run `verify_commands.lifecycle_preview` before tightening one on a
repository with images.

**Access.** Same-account access is IAM's: a repository with no `access`
entries has no repository policy, and the roles that use it attach
`pull_policy_json` or `push_policy_json`. `access` adds statements for:

| Entry | Statement |
|---|---|
| `pull_principals`, `push_principals` | Pull (or pull and push) for IAM role, user or account root ARNs, typically other accounts |
| `pull_organization_ids` | Pull for every principal in these AWS Organizations (`aws:PrincipalOrgID`) |
| `lambda_accounts` | The two statements Lambda needs to use the images in functions of these accounts. Without them, Lambda adds its own statement when a function is created, and the next apply removes it |
| `statements` | Your own statements, as JSON |

## The registry

An account has one registry per Region, and its settings are singletons:
`registry.enabled = true` in exactly one workspace per account and Region, or
two workspaces overwrite each other on every apply. A workspace that only owns
repositories leaves `registry` alone.

| Field | Does |
|---|---|
| `scanning` | `type` ENHANCED (Amazon Inspector: OS and language packages, continuous rescans, billed by Inspector) or BASIC; `rules` of `frequency` and repository filters. `scanning = {}` rescans every repository continuously |
| `replication` | Rules of destinations (`region`, and `account_id` for another account) and repository prefixes. Another account's owner must allow it: `output.replication_destination_requirements` |
| `replication_source_accounts` | Accounts allowed to replicate into this registry (a registry policy statement) |
| `pull_through_cache` | Keyed by the local prefix: `upstream` (docker-hub, ecr-public, quay, k8s, github-container-registry, gitlab-container-registry, azure-container-registry, chainguard, ecr), its secret, URL or role. Images are pulled as `<registry_url>/<prefix>/<upstream image>` |
| `pull_through_cache_principals` | Principals allowed to create cache repositories and import images (a registry policy statement); or attach `pull_through_cache_policy_json` to them |
| `creation_templates` | Keyed by prefix or `ROOT`: mutability, key, lifecycle policy, repository policy and tags for repositories ECR creates for a pull through cache, replication or a push to a missing repository (`CREATE_ON_PUSH`). The module creates the role ECR creates them with |
| `policy_statements` | Your own registry policy statements, as JSON |
| `pull_time_update_exclusions` | Roles (a third-party scanner) whose pulls do not update an image's last pull time, so `sinceImagePulled` rules and archiving see real use |
| `account_settings` | `basic_scan_type_version`, `registry_policy_scope`, `blob_mounting` (layers shared across repositories with the same encryption) |

## Behaviour to know about

**The encryption of a repository is fixed.** `encryption_type` and the key are
ForceNew (provider source at v6.57.1, `internal/service/ecr/repository.go`):
adding, changing or removing a key replaces the repository. With
`force_delete = false` the replacement fails while images exist; with `true`,
the images are deleted. Choose the key before the first push.

**A lifecycle policy change is a replacement of the policy**, not of the
repository: the policy is ForceNew, so the apply deletes it and puts the new
one. Images are untouched.

**Templates apply at creation only.** Changing a creation template does not
touch repositories ECR already created from it.

**Account settings are not reset.** Removing one from `account_settings` stops
managing it; ECR keeps its value (the provider's delete does nothing).

**Pull through cache needs the internet once.** The first pull of an upstream
image needs a NAT path even with VPC endpoints; later pulls do not
([VPC endpoints](https://docs.aws.amazon.com/AmazonECR/latest/userguide/vpc-endpoints.html)).
ECR refreshes a cached tag from upstream at least once every 24 hours.

**Silent failures are routed.** With `sns_topic_arn`, EventBridge rules publish
basic scans with CRITICAL findings in the module's repositories, and (with the
registry) replications and cache syncs that did not succeed. Enhanced scanning
findings are Amazon Inspector's; route them from Inspector or Security Hub.

## Examples

| Example | Shows |
|---|---|
| [`basic`](examples/basic) | Two repositories with the defaults and a customer key |
| [`complete`](examples/complete) | Every input: cross-account, organization and Lambda access, an archiving repository, and the registry with enhanced scanning, replication to a DR Region and another account, three pull through caches and creation templates |

## Most-used inputs

The registry's Inputs tab is the reference; descriptions in `variables.tf` are
written to be read there.

| Name | Default | Notes |
|---|---|---|
| `name` | required | Prefix of the template role and event rules |
| `repositories` | `{}` | The repositories, keyed by name; see [Repositories](#repositories) |
| `kms_key_arn` | `""` | Key for every repository that does not set its own; empty: AES-256 |
| `image_tag_mutability` | `"IMMUTABLE"` | Default for every repository |
| `lifecycle_policy` | expire untagged after 14 days, keep 100 | Default for every repository |
| `scan_on_push` | `true` | Default for every repository |
| `registry` | not managed | The registry's singletons; see [The registry](#the-registry) |
| `sns_topic_arn` | `""` | Where the event rules publish |
| `tags`, `required_tag_keys` | `{}`, `[]` | Cost allocation tags, and the keys that must be in them |
| `acknowledged_checks` | `[]` | Advisory checks you have decided to live with |

## Contract outputs

| Output | For |
|---|---|
| `repository_urls`, `repository_arns`, `registry_url` | Image references, policies, `docker login` |
| `pull_policy_json`, `push_policy_json`, `pull_through_cache_policy_json` | Identity policies for the roles that pull, push, or pull through the cache, scoped to exactly these repositories |
| `governance` | The posture as data: mutability and exclusions, encryption, scanning, lifecycle rules, unbounded repositories, cross-account principals, registry settings, which template each cache gets, acknowledged checks |
| `kms_key_policy_requirements` | Contract v2 entries: the deployer creating grants through ECR on the repository keys, the template role on the template keys. Feed them to `modules/kms` as a consumer |
| `deployer_requirements` | `kms:RetireGrant` on the repository keys (ECR requires it in the caller's own policy), `iam:PassRole` on the template role, the service-linked roles, the Inspector actions for enhanced scanning |
| `replication_destination_requirements` | The registry policy statement each destination account must add |
| `notification_requirements` | The topic policy statement the event rules need |
| `network_contract` | The endpoints pulls need, and the NAT note for pull through cache |
| `verify_commands` | CloudShell checks: repositories, recent images, lifecycle preview, scan findings, login, registry, cache rules |

## Limits

- **Never applied against real AWS in this repository.** Plans are tested in
  CI against a mocked provider on the newest 6.x; the 6.57.1 floor is not a CI
  leg. Not checked against AWS in particular: that the template role works
  scoped to its prefixes and keys (AWS's example uses `*`); that the template
  role's trust needs no `aws:SourceAccount` condition (AWS's example has none);
  and the `sinceImagePulled` archive rule beside an `untagged` rule in one
  policy (AWS shows each with an `untagged` or `any` rule, not this pair).
- **Not offered:** dual-layer KMS encryption (GovCloud only), ECR managed
  signing and replication of deletes (not in provider 6.57.1), ECR Public,
  enhanced scanning findings to the topic (Inspector's), and a role for
  cross-account ECR-to-ECR pull through cache (bring `role_arn`).
- **Registry settings are not merged.** The registry policy, replication and
  scanning configurations are each one document per Region; this module
  writes all of it.

## Versioning and support

Semantic versioning, tags `ecr-vX.Y.Z`. Breaking: removed or renamed inputs and
outputs, new required inputs, changed defaults, an update that becomes a
replacement, an address change, a raised Terraform or provider floor. A
deprecated input keeps working, with a warning in its description, for at
least one minor release before a major removes it. The previous major gets
security fixes for six months after a new major. `moved` blocks are never
deleted, so a workspace can skip versions.
Supported: Terraform 1.9 to latest; `hashicorp/aws` 6.57.1 to the newest 6.x.
[CHANGELOG.md](CHANGELOG.md), [COSTS.md](COSTS.md),
[docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) for callers of the untagged module.
