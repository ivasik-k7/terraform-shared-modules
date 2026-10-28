# Governance

How decisions are made about this repository's modules, what a module's
maturity promises, and which controls are enforced where. The workflow for a
single change is in [CONTRIBUTING.md](../CONTRIBUTING.md).

## Roles

| Role | Who | Decides |
|---|---|---|
| Maintainers | The owners in `.github/CODEOWNERS` for `*` | Repository conventions, CI gates, releases, accepting governance or security debt |
| Module owners | The owners for `/modules/<name>/` in CODEOWNERS (the maintainers if none) | Design and interface of their module; when it is ready to release |
| Contributors | Anyone opening a pull request | Proposals; they own their change until it merges |

A change to the gates (`.github/`, `scripts/`, `.githooks/`, the linters'
canonical copy, agent instructions and permissions) needs a maintainer's
review, because it changes what "tested" means for every module.

## Decisions

- **Small and reversible** (a fix, a new optional input): the pull request is
  the record.
- **Hard to reverse or cross-cutting** (a new convention, a raised floor
  across modules, a provider-major policy, a breaking interface): an
  architecture decision record in [docs/decisions/](decisions/), proposed in a
  pull request, accepted by a maintainer. Superseded records stay, marked
  superseded.
- **Conventions** change in `.kiro/steering/`, in the same pull request as
  the code that first follows the new rule, so the rule is never ahead of or
  behind the code.

## Module lifecycle

The module's README states its stage in its first lines.

| Stage | Promise to callers | Required |
|---|---|---|
| **Experimental** | None. Interface may change in any release | Builds and validates; README says experimental |
| **Beta** (`0.x`) | Breaking changes bump the minor and are listed in the CHANGELOG | Tests for every guard; README with refusals and limits; CHANGELOG; in the CI matrix |
| **Stable** (`>= 1.0`) | SemVer. Breaking only in a major, with an upgrade guide | All of beta, plus examples that validate, COSTS.md for anything billable, a security review (`/tf-module-security`) with no open Critical/High, `moved` blocks for every address change |
| **Deprecated** | Security fixes only, for the window below | README and registry description name the replacement and the end date |
| **Removed** | Nothing | Tags remain, so existing callers keep resolving |

New modules start experimental or beta. Promotion to stable is a pull request
that ticks the stable column, reviewed by a maintainer.

## Change classes

| Class | Examples | Version bump | Extra requirement |
|---|---|---|---|
| Breaking | removed/renamed input or output, new required input, **changed default**, update becomes replacement, address change, raised floor | major (minor before 1.0) | `!` in the PR title; **BREAKING** in the CHANGELOG; `docs/UPGRADE-<major>.0.md` for a stable module |
| Feature | new optional input, output, `check` | minor | Tests for every new guard |
| Fix | wrong behaviour corrected without changing a correct caller's plan | patch | A regression test named for the failure |
| No release | docs, tests, CI, refactors with an identical plan | none | — |

## Support

- The latest minor of each module's current major gets fixes.
- After a new major is tagged, the previous major gets security fixes for
  **6 months**, then is deprecated.
- Supported Terraform: from the module's `required_version` floor (1.9 unless
  the README says otherwise) to the latest. Supported provider: the module's
  constraint, tested at both ends in CI.

## Releases

A release is a tag `<module>-vX.Y.Z` on a commit on `main` whose module
CHANGELOG has a dated `## [X.Y.Z] - YYYY-MM-DD` heading.
`make release-check` verifies this before tagging; `.github/workflows/release.yml`
verifies it again and publishes the GitHub release; the HCP Terraform
registry publishes from the tag. Pushing a tag is a deliberate act by a
maintainer, never a side effect.

## Debt and exceptions

Every accepted exception has a reason, an owner and a review date next to it.
An exception without a reason is a finding.

| Kind | Recorded in | Ratchet |
|---|---|---|
| Convention debt that predates the governance check | `.github/governance-baseline.json` | The check fails on a fixed entry left in place; the file only shrinks |
| Accepted trivy findings | `.trivyignore` | Reason and revisit date above each ID |
| Accepted workflow lint notes | `.github/actionlint.yaml` | Per file; remove when the line is fixed |
| Advisory checks a caller accepts | the module's `acknowledged_checks` input | Visible in `output.governance` |

## Controls, and where each is enforced

Local hooks and agent permissions catch accidents; only the remote enforces.

| Control | Local (accident-catcher) | Remote (enforced) |
|---|---|---|
| Secrets never committed | `.githooks/pre-commit`, pre-commit gitleaks | gitleaks in CI; push protection |
| Formatting, validation, tests | `make check` | `terraform-ci.yaml`, required checks |
| Conventions | `make governance` | `governance.yml`, required check |
| Misconfiguration | `make scan` (if trivy installed) | `security.yml`, required check |
| Review | — | CODEOWNERS + branch protection |
| Releases from `main` only | `make release-check` | `release.yml`, tag protection |
| Agents do not push, apply or read secrets | `.claude/settings.json`, `.vscode/settings.json`, steering guardrails | Branch protection; credentials scoped to read-only by default |

## Repository settings to apply

These live in GitHub, not in files, so they are listed here to be applied and
audited:

- **Branch protection on `main`**: pull requests only; one approving review
  from CODEOWNERS; dismiss stale approvals; no force pushes; no deletion;
  required checks: `Security & Lint`, `Validate Modules`, `Validate Examples`,
  `module conventions`, `actionlint`, `shellcheck`, `trivy config scan`,
  `conventional`.
- **Squash merge only**, with the pull request title as the commit message.
- **Tag protection** (a ruleset) for `*-v*`: only maintainers create them.
- **Private vulnerability reporting** and **secret scanning push protection** on.
- **Dependabot alerts and security updates** on.
- **Actions**: allow only actions pinned to a full commit SHA, where the plan
  supports it; default workflow token permissions read-only.
