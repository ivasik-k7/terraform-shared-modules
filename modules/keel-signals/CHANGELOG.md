# Changelog: keel-signals

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-signals-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- Four severity topics open to Budgets, Cost Anomaly Detection and CloudWatch
  in the account, with e-mail owners by severity.
- Topics to the control plane: SNS to SQS, a pipe per severity to the default
  bus (`keel.<severity>`), and a forwarding rule to the control plane bus.
- Optional forwarding of alarms by name prefix and of Anomaly Detected events.
