# Contributing

How to change this module so that what a caller plans stays predictable.
`make check` runs everything below that needs no credentials; CI runs it on
Terraform 1.9.8 and latest, against aws 5.100.0 and the newest 6.x.

## The workflow

1. Branch from `main`; `main` takes only reviewed pull requests.
2. `pre-commit install` once. It formats, validates, lints and refuses
   secrets before a commit leaves the laptop.
3. Title the pull request as a [Conventional Commit](https://www.conventionalcommits.org):
   `feat:` (minor), `fix:` (patch), `feat!:` or a `BREAKING CHANGE:` footer
   (major). The squash-merge title is what release-please reads.
4. Merge. release-please opens or updates the release pull request; merging
   that tags `vX.Y.Z`, and the HCP Terraform registry publishes the tag.

## Writing Terraform here

**Variables.** `description`, `type`, `nullable = false` and a default unless
the value must be supplied. Empty string, not `null`, means "unset" for
optional strings. Anything that reaches an AWS API gets a `validation`. Put
the price in the description of any knob that costs money.

**The floor evaluates both sides of `||` and `&&`.** Terraform 1.9 does not
short-circuit, so `var.x == "" || regex(...)` crashes on the floor and passes
on current versions. Write a ternary, `can()`, or `alltrue([...])`.
`tests/lint_validations.py` enforces this in conditions and tests.

**Where a rule belongs.**

| Use | When |
|---|---|
| `validation` | The value is wrong on its own terms |
| `precondition` | A combination is certainly wrong, or a data source contradicts it |
| `check` | The posture is defensible but a reviewer should see it; it warns, never blocks |
| an output | A fact a change review, a test or another team acts on |

A hard failure has to be certain: if a real configuration could want it, it
is a check. A guard that can never fire is worse than none, because it reads
as a guarantee. Spend guards on failures that are silent, late or expensive,
in that order.

**Load-bearing patterns.**

- `create = false` plans nothing and leaves every output null.
- Never `count` or `for_each` over a value that may be unknown at plan (an
  ARN from another resource in the caller's root). Key on the caller's
  static keys, or on list position.
- Never index into something a guard is about to reject: `lookup()` or
  `try()` first, so the guard reports instead of an "Invalid index".
- Contracts as data: what the caller must provide (key policy statements,
  network rules, IAM for callers) is an output, known at plan.
- Tags: `merge(var.tags, local.module_tags)`, module keys last.
- `release-please` rewrites every `v<major>.<minor>.<patch>` string in
  `versions.tf`: write versions there without a leading `v`.

**Provider facts are checked, never recalled.** Whether an argument forces
replacement, what a default is, which values an enum takes: confirm it in
`terraform providers schema -json` or the provider source at the pinned
version, and say where in the pull request.

## Tests

`terraform test` against `mock_provider`: no credentials, no cost.

- One `run` per property, named for it in prose
  (`run "a_key_in_another_region_is_refused"`).
- Every validation, precondition and check has a run with the input that
  trips it; `expect_failures` names the exact address.
- Assert the invariant ("the key condition names exactly this group"), not
  the shape ("a requirement exists").
- `tests/examples.tftest.hcl` plans every example: a reader copies them.
- What the mock cannot prove: it does not report replacements, and it
  returns invented values for anything computed. Say so in a comment rather
  than implying coverage.

The Python linters each have `--self-test`, which reintroduces every defect
they catch and confirms they catch it. Add a case with every new rule.

## Releases

Semantic versioning, as the README's "Versioning and support" defines it.
Anything that changes an unchanged caller's plan is **BREAKING**: removed or
renamed inputs and outputs, a changed default, an update turned into a
replacement, a moved address without a `moved` block, a raised floor. A
major release that existing deployments must cross gets
`docs/UPGRADE-<major>.0.md`. `moved` blocks are never deleted.
