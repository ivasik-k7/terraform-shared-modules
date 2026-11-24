# Changelog: keel-insights

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-insights-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [0.1.0] - unreleased

### Added

- The destination side of AWS's Cloud Intelligence Dashboards data pipeline and
  the dashboards (CUDOS v5, KPI, Cost Intelligence, plugins) from AWS's
  published templates, pinned by version.
- `templates`: the templates and the dashboards' Lambda layer from a mirror the
  estate controls, with the reviewed sha256 of each default template as data
  (`templates` output) and a check command per template.
- `verify_commands.export_data_size`: the export bucket's size by day.
