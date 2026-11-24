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
- Topics to the control plane: a queue and an unfiltered pipe per severity to
  the default bus (`keel.<severity>`, the SNS envelope in `detail.sns`, the
  queue in `resources`), and a forwarding rule to the control plane bus that
  takes this instance's events only.
- A dead-letter queue, and alarms on parked and stalled signals.
- Optional forwarding of alarms entering ALARM by name prefix, and of Anomaly
  Detected events.
