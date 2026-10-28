# Changelog

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module
follows [semantic versioning](https://semver.org); see "Versioning and
support" in [README.md](README.md). release-please writes the entries from
the merged pull request titles; edit the release pull request to add what a
caller must do.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- A CloudWatch Logs log group with retention, class, a customer managed key
  and `skip_destroy`.
- `kms_key_policy_requirements` (contract v2), `governance`,
  `verify_commands`.
- Advisory checks `log_retention_is_bounded` and `logs_use_a_customer_key`,
  and `acknowledged_checks`.
