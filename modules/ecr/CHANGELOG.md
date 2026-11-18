# Changelog: ecr

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `ecr-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [1.0.0] - unreleased

The first tagged release, a rewrite of the untagged module. Callers of it
follow [docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md).

### Added

- `repositories`: any number of repositories from one call, keyed by name.
- Tag mutability exclusions (`tag_mutability_exclusions`), sent as
  `IMMUTABLE_WITH_EXCLUSION` or `MUTABLE_WITH_EXCLUSION`.
- A lifecycle preset that bounds storage by default (untagged images expire
  after 14 days, the newest 100 images stay), archive storage
  (`archive_unpulled_days`, `archive_expire_days`), and validated custom
  `rules` with `sinceImagePulled`, `sinceImageTransitioned` and `transition`.
- `access`: pull and push principals, AWS Organization pull, the statements
  Lambda needs for container images, and raw statements.
- `registry`: scanning, replication and replication sources, pull through
  cache for every upstream ECR supports (secret, URL and role per upstream),
  cache principals, creation templates with the role ECR creates them with,
  registry policy statements, pull-time update exclusions and account
  settings, managed from one workspace per account and Region.
- EventBridge rules to `sns_topic_arn` for critical basic-scan findings,
  failed replications and failed cache syncs.
- Contract outputs: `governance`, `kms_key_policy_requirements` (contract v2),
  `deployer_requirements`, `replication_destination_requirements`,
  `notification_requirements`, `network_contract`, `verify_commands`,
  `pull_through_cache_policy_json`.
- Seven advisory checks and `acknowledged_checks`; `required_tag_keys`.

### Changed

- **BREAKING** Terraform `>= 1.9.0` (was `>= 1.5.0`), `hashicorp/aws`
  `>= 6.57.1, < 7.0.0` (was `>= 5.30.0, < 6.0.0`), the floor `modules/ecs`
  and `modules/asg-group` use.
- **BREAKING** `repository_name` is the key of `repositories`; the repository
  is `aws_ecr_repository.this["<name>"]` (was `this[0]`). The move is written
  in the calling root.
- **BREAKING** Default: every repository gets a lifecycle policy (was none);
  ECR starts deleting untagged images older than 14 days and images beyond
  the newest 100 within 24 hours of the apply.
- **BREAKING** No repository policy unless `access` asks for one; the
  `AllowAccountPullPush` statement for the own account is gone, because IAM
  policies already govern same-account access.
- **BREAKING** `encryption_type` + `kms_key_arn` are one `kms_key_arn` (KMS
  when set). `name` is a new required input.
- **BREAKING** `pull_policy_json` and `push_policy_json` cover every
  repository of the call; `repository_url`, `repository_arn` and
  `repository_name` are maps.

### Removed

- **BREAKING** `create_repository_policy`, `repository_policy_statements`,
  `allowed_principals`, `allowed_pull_principals`, `common_tags` (deprecated),
  `enable_lifecycle_policy`, `lifecycle_rules`, `repository_access`,
  `enable_replication`, `replication_rules`, `enable_registry_scanning`,
  `registry_scan_type`, `registry_scanning_rules`, `pull_through_cache_rules`,
  `enable_registry_policy`, `registry_policy_json`, and their outputs. The
  mapping is in the upgrade guide.
- **BREAKING** `enable_logging` and its log group: ECR writes nothing to it.
