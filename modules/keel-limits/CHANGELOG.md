# Changelog: keel-limits

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-limits-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- Limits as AWS budgets.
  - Types: COST, USAGE, and Savings Plans and RI coverage and utilization.
  - Scoped by tags, cost categories, accounts, services, Regions and usage
    types; periods monthly, quarterly or annual; auto-adjusting COST limits.
- Thresholds that alert by severity on keel-signals' topics, with defaults by
  tier.
- A per-limit anomaly monitor on the limit's scope.
- Per-limit actions: a deny policy on roles, or an SCP, automatic or manual.
- `thresholds`, `controls` and `governance` as data.
