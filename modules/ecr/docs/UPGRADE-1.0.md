# Upgrading to 1.0

For workspaces on the untagged `modules/ecr` (one repository per call,
`hashicorp/aws < 6.0.0`). A workspace starting fresh does not need this.

## Before the plan: two decisions

**The lifecycle default.** 1.0 gives every repository a lifecycle policy
unless told otherwise: untagged images older than 14 days and images beyond
the newest 100 are deleted by ECR within 24 hours of the apply. To keep what a
repository holds today, set `lifecycle_policy = { enabled = false }` on it (the
`storage_is_bounded` check then warns), or carry its old `lifecycle_rules` over
(below). Run `verify_commands.lifecycle_preview` after the apply of a policy
you are unsure of; nothing is deleted until ECR evaluates it.

**Registry settings.** If any of the old calls set `enable_replication`,
`enable_registry_scanning`, `enable_registry_policy` or
`pull_through_cache_rules`, choose the one workspace that owns the registry in
that account and Region, and move those settings into its `registry` object.
Every other call drops them.

## One call for many repositories

The old module took one repository per call. 1.0 takes a map, so several calls
can become one. Each repository moves by its key, from whichever call held it:

```hcl
module "ecr" {
  source  = "app.terraform.io/<org>/ecr/aws"
  version = "~> 1.0"

  name = "orders"
  repositories = {
    "orders/api"    = {}
    "orders/worker" = {}
  }
}

moved {
  from = module.ecr_api.aws_ecr_repository.this[0]
  to   = module.ecr.aws_ecr_repository.this["orders/api"]
}

moved {
  from = module.ecr_worker.aws_ecr_repository.this[0]
  to   = module.ecr.aws_ecr_repository.this["orders/worker"]
}
```

Move the lifecycle and repository policies the same way
(`aws_ecr_lifecycle_policy.this[0]`, `aws_ecr_repository_policy.this[0]` to
`this["<name>"]`). A workspace from before the `create` switch has the
repository at `aws_ecr_repository.this`, without `[0]`; write that as the
`from`. Registry resources keep their addresses
(`aws_ecr_registry_scanning_configuration.this[0]`,
`aws_ecr_replication_configuration.this[0]`, `aws_ecr_registry_policy.this[0]`)
when they stay in the same call; pull through cache rules move from their old
map key to their prefix:

```hcl
moved {
  from = module.ecr.aws_ecr_pull_through_cache_rule.this["dockerhub"]
  to   = module.ecr.aws_ecr_pull_through_cache_rule.this["docker-hub"]
}
```

`moved` blocks are never deleted, so a workspace can skip versions.

## Inputs

| Before | Now |
|---|---|
| `repository_name` | The key of `repositories` |
| `image_tag_mutability` | Same name, the default for every repository; or `repositories[*].image_tag_mutability`. `tag_mutability_exclusions` is new |
| `force_delete` | `repositories[*].force_delete` |
| `scan_on_push` | Same name, the default; or `repositories[*].scan_on_push` |
| `encryption_type`, `kms_key_arn` | `kms_key_arn` (module or repository): KMS when set, AES-256 when empty. Keep the same key: a different one replaces the repository |
| `enable_lifecycle_policy`, `lifecycle_rules` | `lifecycle_policy` (module or repository). Old rules map to `rules`: `rule_priority` to `priority`, `tag_prefix_list` to `tag_prefixes`, `tag_pattern_list` to `tag_patterns`, `count_number` to `count`, `action_type` to `action`; `count_unit` is always days. No rules is no longer "no policy": set `enabled = false` for that |
| `repository_access.pull_principals`, `.push_principals` | `repositories[*].access.pull_principals`, `.push_principals` |
| `repository_access.statements` (objects) | `repositories[*].access.statements`, each a JSON statement (`jsonencode({...})`) |
| `repository_access.account_access`, `.enabled`, `create_repository_policy` | Removed: same-account access is IAM's, and no policy is sent without `access` entries |
| `allowed_principals`, `allowed_pull_principals`, `repository_policy_statements` | Removed (deprecated): `access.push_principals`, `access.pull_principals`, `access.statements` |
| `enable_replication`, `replication_rules` | `registry = { enabled = true, replication = [...] }`; `destinations[*].registry_id` is `account_id` (empty for this account), `repository_filters` is `repository_prefixes` |
| `enable_registry_scanning`, `registry_scan_type`, `registry_scanning_rules` | `registry.scanning = { type, rules = [{ frequency, filters }] }` |
| `pull_through_cache_rules` | `registry.pull_through_cache`, keyed by `ecr_repository_prefix`: `upstream` names the registry (docker-hub, ecr-public, ...), `credential_arn` is `credential_secret_arn`; the URL is derived except for Azure and ECR |
| `enable_registry_policy`, `registry_policy_json` | `registry.policy_statements`, a list of statement JSON |
| `enable_logging`, `cloudwatch_log_group_name`, `cloudwatch_log_retention_days`, `cloudwatch_kms_key_id` | Removed: ECR wrote nothing to that group. ECR API activity is in CloudTrail; failures reach `sns_topic_arn` |
| `tags`, `common_tags` | `tags` |
| (new) `name` | Required: the prefix of the template role and the event rules |

## Outputs

| Before | Now |
|---|---|
| `repository_url`, `repository_arn`, `repository_name` | `repository_urls`, `repository_arns`, `repository_names`, keyed by name |
| `registry_id` | Same |
| `kms_key_arn`, `encryption_configuration` | `governance.encryption` |
| `pull_policy_json`, `push_policy_json` | Same names; they cover every repository of the call |
| `image_tag_mutability`, `image_scanning_configuration` | `governance.tag_mutability`, `governance.scan_on_push` |
| `lifecycle_policy_created`, `lifecycle_rules` | `governance.lifecycle_rules`, `governance.unbounded_storage` |
| `replication_enabled`, `replication_configuration` | `governance.replication_destinations` |
| `push_principals`, `pull_principals`, `allowed_push_principals`, `allowed_pull_principals`, `repository_policy_statements` | `governance.cross_account_principals` |
| `log_group_name`, `log_group_arn` | Removed |

## What happens on the first plan

| Resource | What the plan does | Why |
|---|---|---|
| Repositories | Moved by your `moved` blocks; tags updated in place (`ManagedBy`, `Module` added) | Same name, same encryption |
| Lifecycle policies | Created, or replaced where one existed | New default; the policy is ForceNew in the provider |
| Repository policies | Destroyed where only the old account baseline existed; updated where `access` has entries | The `AllowAccountPullPush` statement is gone |
| The log group from `enable_logging` | Destroyed | ECR wrote nothing to it. To keep it, add a `removed` block with `destroy = false` |
| Registry resources | Unchanged, or updated to the new shape | Same addresses |

Search the speculative plan for `aws_ecr_repository` with `must be replaced`:
there should be none. One appears when the encryption differs from what is
running (a different key, or a key where there was none); fix the input
rather than apply it, or the repository and its images are replaced.

## In HCP Terraform

1. Raise the workspace's Terraform version to 1.9 or later, and move the lock
   file to `hashicorp/aws` 6.57.1 or later (`terraform init -upgrade`). A
   workspace on aws 5.x upgrades the provider first, on its own run,
   following the provider's 6.0 upgrade guide.
2. Change the call to the inputs above and add the root `moved` blocks.
3. Open a pull request; read the speculative plan for replacements of
   `aws_ecr_repository` (none) and for the lifecycle policies it creates.
4. Apply. Within 24 hours ECR deletes what the new lifecycle policies select;
   `verify_commands.lifecycle_preview` shows what that is.
