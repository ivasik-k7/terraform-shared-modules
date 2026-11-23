# Changelog: keel-guardrails

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `keel-guardrails-vX.Y.Z`.

## [0.1.0] - unreleased

### Added

- Mandatory tags as an organization tag policy, with report and enforcement
  resource types.
- An SCP refusing to create resources without mandatory tags, with exempt
  principals.
- An SCP allowing only approved Bedrock models in approved Regions.
- `ai_services_opt_out`: an AI services opt-out policy, `default` covering
  every AI service.
