# Changelog: keel-team

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-team-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- Limits through `keel-limits`: any number per account, by tag, cost category,
  account, service, Region or usage type, each with alerts by severity, an
  optional anomaly monitor and an optional lock or SCP action.
- `platforms`: several platforms in one account, each with a limit on
  `platform_tag_key` (default `Platform`).
- Severity topics through `keel-signals`, forwarded to the control plane bus.
- `components`: one account part (limits, FinOps role) and one Region part
  per Region.
- Bedrock application inference profiles per application and model, tagged
  with the platform; a cap per application; a burn meter priced from the
  rate card; metadata-only invocation logs; quota ceilings priced as
  `ai_ceilings`.
- Running-hours schedules: EventBridge Scheduler and Systems Manager
  Automation stop and start EC2 instances by tag and RDS instances by
  identifier.
- A FinOps read-only role trusted by the FinOps account.
- `policies/cost-gate.sentinel` for an HCP Terraform policy set.
