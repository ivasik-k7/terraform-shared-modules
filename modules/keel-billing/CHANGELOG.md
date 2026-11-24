# Changelog: keel-billing

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-billing-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- Cost allocation tag activation and cost categories with account, tag and
  inherited-tag rules and split charges.
- Cost Optimization Hub and Compute Optimizer enrollment for the organization.
- Anomaly monitors: the AWS managed monitors by service and by account, and a
  customer managed monitor per cost category value. One immediate alert
  emits the Anomaly Detected event for the control plane; daily or weekly
  digests go by e-mail.
- Organization limits through `keel-limits`.
  - Scoped by cost category, tag, service, accounts, Region or usage type.
  - Alerts by severity; auto-adjusting limits; SCP actions.
- Commitment targets for Savings Plans and RI utilization and coverage.
- Custom billing views by accounts or tag, shared in the organization through
  AWS RAM.
- The AWS FinOps Agent decision: `finops_agent_setup` (console steps,
  delegation, policy, what it reads) and the `finops_agent_is_approved`
  check.
- Severity topics through `keel-signals`, forwarded with the anomaly events to
  the Keel control plane.
- The source side of AWS's Cloud Intelligence Dashboards data pipeline, in
  the destination's Region, from AWS's bucket or the estate's mirror
  (`data_exports.template_url_prefix`), with the reviewed template's sha256.
- `docs/FRAMEWORK.md` and `docs/RESEARCH.md` for Keel as a whole.
