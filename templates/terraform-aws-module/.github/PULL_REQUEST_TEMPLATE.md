<!--
The title is the commit message on main and decides the next version:
  feat: ...   a minor (new optional input, output, check)
  fix: ...    a patch
  feat!: ...  a major - anything that changes an unchanged caller's plan
-->

## What and why

<!-- One paragraph: the change, and the failure or need behind it. -->

## What a caller's plan shows

- [ ] Nothing changes for an unchanged configuration
- [ ] It changes, and the CHANGELOG entry says how (**BREAKING** if it removes, renames, changes a default, or turns an update into a replacement)

<!-- If a resource address moved: the moved block, and the plan line showing "has moved to". -->

## How it was verified

- [ ] `make check` passes (fmt, validate, tests, examples, linters with self-tests)
- [ ] A test asserts the new behaviour - its invariant, not that a resource exists
- [ ] Every new validation, precondition and check has a run with the input that trips it
- [ ] Provider facts this relies on (replacement, defaults, enums) were checked in the schema or source, not recalled

## Docs

- [ ] README: new refusals, checks or contract outputs; limits still true
- [ ] COSTS.md, if this adds or moves a billable line
