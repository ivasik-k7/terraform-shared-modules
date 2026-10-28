---
inclusion: always
---

# What this repo is

A monorepo of production Terraform modules for AWS, aimed at a regulated,
often network-isolated estate (banking-style). Each `modules/<name>/` is an
independent, BYO-everything module: it creates its own resources and expects the
caller to own VPCs, KMS keys, buckets and topics.

Layout that matters:

- `modules/<name>/` — the module. One concern per file: `variables.tf`,
  `locals.tf`, `data.tf`, `outputs.tf`, `versions.tf`, then one file per
  resource group (`recipe.tf`, `distribution.tf`, `iam.tf`, …).
- `modules/<name>/tests/` — `*.tftest.hcl` plan tests, plus Python linters for
  properties Terraform cannot express.
- `modules/<name>/examples/` — runnable examples. CI validates every one of
  them, so an example that cannot plan is a broken build.
- `.github/workflows/terraform-ci.yaml` — the gate. Read it before adding a
  check; most things are already wired.

## How to verify work here

Never claim something works without running these. From the module directory:

```bash
terraform fmt -check -recursive .
terraform validate
terraform test                                  # plan tests, mocked provider
python3 tests/lint_validations.py .             # if present
python3 tests/lint_components.py components --tf-dir examples   # if present
```

CI additionally runs `terraform validate` and `terraform test` on **both**
Terraform 1.9.8 and latest, and `tflint` per module. The dual version matters —
see the eager-operator rule in the module steering.

## House style

- **Comments are short and human.** State the mechanism or the trap, then stop.
  No changelog voice in comments ("this used to be broken", "an earlier version
  claimed…"), no essays, no shouting in capitals. If a comment is longer than
  the code it explains, it belongs in the README.
- **Names say what the thing is**, not what it was. Same for a variable whose
  meaning changed: rename it, don't annotate it.
- Never leave a control that cannot fire. A `check` whose condition is always
  true, or a branch on a required variable, reads as a guarantee and is not one.
  Delete it or make it real.
- Prefer emitting facts as data (an output a test can assert on) over prose in a
  README that drifts.
