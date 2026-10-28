---
name: tf-module-review
description: Pre-merge or pre-release review of one Terraform module in this monorepo (modules/<name>), or of the uncommitted change to it - correctness, lifecycle, security, reliability, cost, interface, docs and tests - against the house conventions, reporting only findings proven in this session. Use when asked to review, audit, assess or sign off a module or a module change.
argument-hint: <module name or path> [focus, e.g. "lifecycle" or "the diff only"]
---

# Review a module

Target: `$ARGUMENTS`

Read-only. Scratch files go in the session scratchpad, never in the module.

The method, dimensions, severity and report format are in
[`.claude/commands/review-tf-module.md`](../../commands/review-tf-module.md).
**Read it now and follow it**; this skill adds what is specific to this
repository and to the way findings are proven here.

## Scope

- A bare name means `modules/<name>`. A path means that directory.
- "The diff", "my change" or a dirty working tree: review the change
  (`git diff -- modules/<name>` plus untracked files there) **and** its blast
  radius: every caller of a changed variable, output or address, the tests
  that cover it, and the examples that call it
  (`scripts/tf-modules.sh examples <name>`).
- A large module is sampled: say which files were read fully.

## Evidence rules for this repository

1. **A finding is proven or it is not a finding.** Proof is a command run in
   this session, a quoted line, provider source at the pinned tag, AWS
   documentation quoted with its page, or an offline experiment. Anything
   short of that goes under **Not checked**, with what would prove it, and
   must not drive a fix. "Likely" items are not findings here.
2. **Where facts come from:** [provider-facts.md](../tf-module-create/provider-facts.md).
   In particular, replacement semantics are not in `providers schema -json`.
3. **Read for intent first:** README, CHANGELOG, `docs/` (including
   `UPGRADE-*.md`), test comments, the steering files. A documented decision
   is a finding only if you can show its reasoning is wrong.
4. **Subagent claims are leads.** Re-verify every one, line by line, before
   it reaches the report.

## Toolchain (Phase 1 of the method)

```bash
scripts/tf-modules.sh check <name>          # fmt, validate, test, examples, lint_validations, tflint/trivy if installed
python3 scripts/check_governance.py --all | grep -E " <name>( |$)"   # accepted debt for this module
terraform -chdir=modules/<name> providers schema -json > <scratch>/schema.json
```

Then run every step of the `<name>-gates` job in
`.github/workflows/terraform-ci.yaml`, if it exists: render-and-lint steps,
Python linters with `--self-test`, the provider v5 leg. A render step that
runs `terraform apply` on a `tests/render` config is offline only if the
config uses mock credentials, `skip_*` flags and `create = false`; check
that before running it, and ask if in doubt.

## House conventions to review against (in addition to the method's dimensions)

| Convention | What a violation looks like |
|---|---|
| Eager operators on the 1.9 floor | `var.x == "" \|\| regex(...)` in a validation or a local |
| `create = false` | A resource or output not gated; an output that errors instead of null |
| Guard placement | A `precondition` a valid configuration can trip; a `check` that can never fire |
| Contracts as data | A key/topic/network requirement only in README prose; KMS entries missing v2 fields |
| Content-hashed versions | A ForceNew input missing from the hash input |
| Tags | Caller tags able to override `ManagedBy`/`Module`; transient resources untagged |
| CI wiring | Module with tests absent from the validate matrix; drifted `lint_validations.py` |
| Docs | Absolute repo links; README inputs table that duplicates the registry; limits section dropped; CHANGELOG missing BREAKING |
| Cost | Unbounded retention/snapshots/idle capacity by default; paid knob without a price in its description |

## Delegating

For a large module, split by dimension. Use a light model for mechanical
work (README vs `variables.tf`, examples vs inputs, test coverage tables) and
the strongest model for correctness, lifecycle and security analysis. Give
each the module path, the dimension, and these evidence rules. Re-verify
whatever comes back.

## Report

Exactly the format in the method's Phase 5, with these adjustments:

- Findings carry confidence **Confirmed** only. Anything else is under
  **Not checked**.
- For each finding mark whether the fix is **BREAKING** for an unchanged
  caller.
- End with the commands that were run and their result lines.
- Security gets one dimension here; for a module that grants access, holds
  data or opens network paths, recommend `/tf-module-security <name>`.

Do not edit the module. If the human asks for fixes afterwards, fix one
finding at a time, each with the test that proves it.
