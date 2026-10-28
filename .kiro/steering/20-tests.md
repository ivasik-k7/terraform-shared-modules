---
inclusion: fileMatch
fileMatchPattern: "**/tests/**"
---

# Tests and linters

## What `terraform test` can and cannot prove

The suites here run against `mock_provider`, so they prove graph shape, computed
values, IAM policy content, outputs, and every validation, precondition and
check. Two limits that have both bitten this repo:

- **`mock_provider` does not report `RequiresReplace`.** A change that the real
  provider would call "must be replaced" plans as "update in place". Anything
  relying on replacement semantics — immutable versions especially — is
  invisible here. The proxy is to assert the *version moves* when a ForceNew
  input changes, and to say out loud that it is a proxy.
- **`override_data` does not inherit `mock_data` defaults.** Attributes you do
  not name come back as empty lists/sets and random strings. So every guard that
  reads a data source must pass when the value is absent, and runs using
  `override_data` prove less than they look like they do.

Neither of these can be fixed in the test file. Say so in a comment rather than
implying coverage that is not there.

## Conventions

- The baseline `variables` block is a **fully configured** module, not a minimal
  one, because `terraform test` treats a failing `check` as an error — a minimal
  baseline makes the suite fail on the module's own advisory checks.
- One `run` block per property, named for the property in prose
  (`run "a_schedule_on_a_disabled_pipeline_is_rejected"`).
- Regressions are named for the finding and keep a one-line comment saying what
  was wrong. Trap description, not history: what the failure *does*, not who
  found it.
- `expect_failures` targets the exact address: the resource whose precondition
  should fire, `var.x` for a validation, `check.name` for a check.
- Assert the invariant, not the shape. "The tag the policy selects on exists
  where AWS actually looks" beats "a policy resource exists".
- `create = false` gets its own run asserting resources *and* outputs.

## The Python linters

They exist for cross-file and structural properties HCL cannot express:
undeclared AWSTOE parameters, a download piped into a shell, a shell variable
used in a step that never set it, eager-operator hazards. Rules:

- Every linter has a `--self-test` that reintroduces each defect and confirms
  detection, and asserts the shipped files are clean. **A guard nobody proved is
  a guard nobody should trust** — add a self-test case with every new rule.
- Prefer a false positive to a false negative, and say which direction the tool
  fails in.
- `lint_validations.py` is **shared by copy** between modules and CI fails if the
  copies drift. Fix it once, copy it over, run both self-tests.
