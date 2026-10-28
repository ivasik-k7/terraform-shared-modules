# Contributing

This repository is a monorepo of independent, production Terraform modules
for AWS, consumed from an HCP Terraform private registry. Each
`modules/<name>/` is versioned and released on its own. This guide is the
workflow; the conventions themselves are in `.kiro/steering/`, written once
for people and agents alike.

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).

## Contents

- [Set up](#set-up)
- [Layout](#layout)
- [Making a change](#making-a-change)
- [Module standards](#module-standards)
- [Security requirements](#security-requirements)
- [Tests](#tests)
- [Documentation](#documentation)
- [Versioning and releases](#versioning-and-releases)
- [What CI checks](#what-ci-checks)
- [Governance debt](#governance-debt)
- [Working with AI assistants](#working-with-ai-assistants)

## Set up

| Tool | Version | Needed for |
|---|---|---|
| Terraform | 1.9.8 (the floor) and the latest; aurora also 1.7.5 | `validate`, `test` |
| Python | 3.10+ | the repository's linters and the governance check |
| GNU make, bash, git | any recent | the `make` targets and hooks |
| tflint, trivy, shellcheck, actionlint, pre-commit | optional locally | skipped with a note if missing; CI runs them |

Once per clone:

```bash
make hooks          # git config core.hooksPath .githooks
make help           # every target
```

The pre-commit hook refuses staged secrets, state, keys and unformatted
`.tf` files. `pre-commit` cannot install alongside `core.hooksPath`, so run
`make precommit` before committing if you have it.

## Layout

```text
modules/<name>/            the module: versions.tf, variables.tf, locals.tf, data.tf,
                           outputs.tf, one file per resource group
modules/<name>/tests/      *.tftest.hcl plan tests (mocked provider) + Python linters
modules/<name>/examples/   runnable examples (CI validates every one)
examples/<name>/           larger examples that call modules by relative path
templates/terraform-aws-module/   the template new modules start from
scripts/                   repo tooling: tf-modules.sh, check_governance.py, new-module.sh
.kiro/steering/            the conventions
.github/workflows/         CI, governance, security, release, pr-title
```

## Making a change

1. Branch from `main`: `git switch -c feat/<module>-<topic>`.
2. One module per pull request where possible. Each module is tagged on its
   own, so a pull request that spans modules spans releases.
3. Make the change, with tests (below).
4. Verify:

   ```bash
   make check MODULE=<name>     # fmt, validate, test, examples, linters, tflint/trivy if installed
   make check                   # or: every module changed in your tree, plus repo-wide gates
   ```

   If the module has a `<name>-gates` job in
   `.github/workflows/terraform-ci.yaml`, run its steps too.
5. Add a line to the module's `CHANGELOG.md` under its unreleased heading.
6. Open a pull request. The **title** is the squash-commit message and must be
   a conventional commit with the module as scope:

   | Title | Means |
   |---|---|
   | `feat(aurora): add iam database users` | new optional capability, a minor |
   | `fix(kms): scope create grant to aws resources` | wrong behaviour corrected, a patch |
   | `feat(dms)!: require explicit replication instance class` | changes an unchanged caller's plan, a major |
   | `docs(lb): ...`, `test(...)`, `ci: ...`, `refactor(...)`, `chore(...)` | no release on their own |

7. The template asks what an unchanged caller's plan shows and how the change
   was verified. Paste output, not a summary of it.

### Starting a new module

```bash
scripts/new-module.sh <name>       # or: make new-module NAME=<name>
```

This copies the template's module layer: a working log group that passes its
own tests. Replace it piece by piece, keeping it green. Then add the module to
the `validate` matrix in `terraform-ci.yaml`; the governance check fails until
you do.

## Module standards

The full rules and their reasons are in `.kiro/steering/10-terraform-modules.md`.
The ones reviewers check first:

- **Floors.** `required_version = ">= 1.9.0"`; `hashicorp/aws` as a bounded
  range (`">= 5.x.0, < 7.0.0"`). CI tests both ends.
- **Variables.** `type`, `description`, `nullable = false`, a default unless
  it must be supplied, a `validation` for anything that reaches an AWS API.
  The description is the registry's documentation; put the price of a paid
  knob in it.
- **The eager-operator rule.** Terraform 1.9 evaluates both sides of `||` and
  `&&`. Never rely on short-circuit, in validations or locals.
  `tests/lint_validations.py` enforces it.
- **Where a rule belongs.** `validation` when a value is wrong on its own;
  `precondition` when a combination is certainly wrong; `check` when a
  posture is defensible but a reviewer should see it.
- **`create = false`** plans to nothing and leaves every output null or empty.
- **No `provider` blocks** in a module.
- **Tags.** `merge(var.tags, { ManagedBy = "Terraform", Module = "<name>" })`,
  module keys last. Every billable resource is attributable, including
  transient ones.
- **Contracts as data.** What the caller must provide (key policy statements,
  topic policies, endpoints) is a structured output, not README prose. KMS
  requirements use contract v2, which `modules/kms` compiles.
- **Addresses.** Every rename gets a `moved` block, and `moved` blocks are
  never deleted.
- **Comments** state the mechanism or the trap, briefly. History belongs in
  the CHANGELOG.

## Security requirements

- Least privilege. A `*` in an IAM `Action` or `Resource` carries a comment
  saying why the API forces it. Trust policies carry `aws:SourceArn` /
  `aws:SourceAccount`; OIDC trust pins `aud` and `sub`.
- Encryption at rest and in transit on by default, with a complete
  customer-managed key option.
- Nothing public by default: no `0.0.0.0/0` ingress, no public IPs, IMDSv2
  required.
- Nothing secret in state, plans, logs or unmarked outputs. Prefer
  service-managed secrets and references to existing secrets; mark sensitive
  inputs and outputs `sensitive = true`.
- Scripts that run with privilege validate every interpolated input and never
  download without verifying a checksum.
- See [SECURITY.md](SECURITY.md) for reporting and for what CI scans.

## Tests

From `.kiro/steering/20-tests.md`:

- The baseline `variables` block is a **fully configured** module.
- One `run` per property, named in prose for the property it proves.
- Every `validation`, `precondition` and `check` has a run that trips it,
  with `expect_failures` on the exact address.
- `create = false` has its own run asserting resources and outputs.
- Assert the invariant ("the policy grants exactly X to Y"), not existence.
- `mock_provider` cannot show replacement, real data-source values or AWS
  acceptance. Say so in a comment where it matters.
- A Python linter ships with a `--self-test` that reintroduces each defect it
  catches. `lint_validations.py` is shared by copy and must stay identical to
  `modules/ami-builder/tests/lint_validations.py`.

## Documentation

From `.kiro/steering/30-docs.md`. Readers are on the registry page:

- README: a registry usage block first, then requirements, **what the module
  refuses**, advisory checks, at most fifteen most-used inputs, contract
  outputs, limits (including what has never run against real AWS), and
  versioning.
- No hand-written table of every input; the registry generates it from the
  descriptions.
- Links are **relative**. Never write the repository's URL, owner or name.
- `COSTS.md` for anything billable: pricing date, basis, the line that grows.
- `docs/UPGRADE-<major>.0.md` for a major that existing deployments must cross.

## Versioning and releases

Each module follows [SemVer](https://semver.org) independently.

**Breaking** is anything that changes an unchanged caller's plan: a removed
or renamed input or output, a new required input, **a changed default**, an
update that becomes a replacement, an address change, a raised version floor.

To release `modules/<name>` at version `X.Y.Z`:

1. On `main`, turn the module's unreleased CHANGELOG heading into
   `## [X.Y.Z] - YYYY-MM-DD` (through a pull request).
2. `make release-check MODULE=<name> VERSION=X.Y.Z`
3. Tag and push the tag: `git tag -a <name>-vX.Y.Z -m "<name> vX.Y.Z"`.

The `release` workflow refuses a tag whose module, dated CHANGELOG entry or
commit on `main` is missing, and publishes the GitHub release with that
CHANGELOG section. The registry publishes from the tag. The policy behind
this is in [docs/GOVERNANCE.md](docs/GOVERNANCE.md).

## What CI checks

| Workflow | Proves |
|---|---|
| `terraform-ci.yaml` | Secret scan; fmt; validate and test of every module on Terraform 1.9.8 and latest; tflint; every example validates; per-module gates (`<name>-gates`) |
| `governance.yml` | Module conventions against the baseline, with the checker's self-test; linter copies identical; actionlint; shellcheck |
| `security.yml` | trivy on every module the pull request touches, blocking at HIGH/CRITICAL; weekly report on all modules |
| `pr-title.yml` | The title is a conventional commit |
| `release.yml` | A module tag is releasable, then publishes it |

Every path a workflow references must be tracked in git. An untracked script
does not exist on a fresh checkout.

## Governance debt

`scripts/check_governance.py` checks repository-wide conventions
(`python3 scripts/check_governance.py --explain` lists them). Debt that
existed when it was introduced is recorded in
`.github/governance-baseline.json`. The check fails on a **new** violation,
and also on a baseline entry that has been fixed, so the baseline only
shrinks. When you fix one, delete its entry in the same pull request.

## Working with AI assistants

`CLAUDE.md` and `AGENTS.md` point agents at the same steering files. Claude
Code has project skills for creating, reviewing, security-reviewing and
committing modules (`/tf-module-create`, `/tf-module-review`,
`/tf-module-security`, `/tf-module-commit`). Agent output is held to the same
bar as yours: verified in the pull request, not trusted.

## License

Contributions are licensed under the project's [MIT License](LICENSE).
