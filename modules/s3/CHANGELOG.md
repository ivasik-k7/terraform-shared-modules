# Changelog: s3

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module
follows [semantic versioning](https://semver.org): see "Versioning and
support" in [README.md](README.md). Releases are tagged `s3-vX.Y.Z`.

## [0.1.0] - unreleased

First release.

### Added

- One S3 general purpose bucket, named `<name>-<account>-<region>` by default,
  versioned, encrypted (SSE-S3, SSE-KMS with an S3 Bucket Key, or DSSE-KMS),
  private (Block Public Access set explicitly, ACLs disabled).
- A bucket policy refusing plaintext and old TLS (AWS services exempt, as S3
  advises), other keys, and optionally access outside VPC endpoints or the
  organization; cross-account grants by prefix; CloudFront Origin Access
  Control; server access log delivery; caller statements.
- Lifecycle: a whole-bucket rule bounding old versions, abandoned uploads and
  orphan delete markers, plus caller rules with prefix, tag and size
  filters; Intelligent-Tiering archive configurations.
- Object Lock, enabled in place.
- Replication (V2 rules, SSE-KMS replicas, Replication Time Control) with a
  scoped role.
- Server access logging with partitioned keys; event notifications;
  inventory; request metrics; CORS; Transfer Acceleration; Requester Pays.
- 7 advisory checks and `acknowledged_checks`.
- `replication.create_role` and `access_logging.enabled`: what exists is
  decided by these switches, not by whether `role_arn` or `target_bucket` is
  empty, so a role or a log bucket created in the same root plans.
- `notification_dependencies`: orders the notification configuration after
  destination policies in the same root, which a module-wide `depends_on`
  cannot do without a cycle.
- Contract outputs: `read_policy_json`, `write_policy_json`,
  `kms_key_policy_requirements` (v2), `replication_destination_requirements`,
  `notification_destination_requirements`,
  `inventory_destination_requirements`, `governance`, `verify_commands`.
