<!--
The title becomes the squash-commit message: type(module): subject
  feat(aurora): ...     new optional input, output or check      -> minor
  fix(kms): ...         wrong behaviour corrected                -> patch
  feat(dms)!: ...       anything that changes an unchanged caller's plan -> major
One module per pull request where possible: each module is versioned and tagged on its own.
-->

## What and why

<!-- One paragraph: the change, and the failure or need behind it. -->

**Module(s):** `modules/...`

## What an unchanged caller's plan shows

- [ ] Nothing changes
- [ ] It changes, and the module's CHANGELOG says how. **BREAKING** if it removes or renames an input or output, adds a required input, changes a default, turns an update into a replacement, moves an address, or raises a version floor

<!-- If an address moved: the moved block, and the plan line showing "has moved to". -->

## How it was verified

<!-- Paste the tail of the run, not a summary of it. -->

- [ ] `make check MODULE=<name>`: fmt, validate, tests, examples, linters with their self-tests
- [ ] A test asserts the new behaviour's invariant, not that a resource exists
- [ ] Every new `validation`, `precondition` and `check` has a run with the input that trips it
- [ ] Provider facts this relies on (replacement, defaults, enums) were checked in `terraform providers schema -json` or the provider source, not recalled
- [ ] Not verified, and why (needs an apply, credentials, a real account):

## Security

- [ ] IAM: no new `*` action or resource without a stated reason; trust policies carry source conditions
- [ ] Nothing secret reaches state, plan or an output unmarked
- [ ] KMS requirements emitted as contract v2 data, if the module uses a customer key

## Docs and cost

- [ ] README: new refusals, checks or contract outputs; the limits section is still true
- [ ] COSTS.md, if this adds or moves a billable line; the cost-bearing input's description states the price
- [ ] Governance baseline only shrank (`.github/governance-baseline.json`)
