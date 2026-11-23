# Changelog: keel-control-plane

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-control-plane-vX.Y.Z`.

## [0.1.0] - unreleased

### Added

- An event bus for the organization's cost signals, with an archive.
- Routing to INFO, WARNING, HIGH and CRITICAL topics: anomalies by impact,
  alarms by name, Keel events by their declared severity.
- Evidence: every event to an Object Lock bucket through Data Firehose.
- Alarms on undelivered signals and failed evidence delivery.
