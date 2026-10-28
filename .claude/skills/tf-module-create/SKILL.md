---
name: tf-module-create
description: Create a new Terraform module in this monorepo, or add a feature, input, output, resource or guard to an existing one, following the house conventions (create switch, eager-operator rule, contracts as data, KMS contract v2, property tests, registry-ready docs, CI wiring). Use when asked to create, scaffold, build, extend or add something to a module under modules/.
argument-hint: <new-module-name | module: feature to add>
---

# Create or extend a module

Target: `$ARGUMENTS`

The conventions are in the steering files CLAUDE.md loads; this skill is the
order of work and the gates. A module here is consumed from a private
registry by teams who will not read its source, so its interface, its
refusals and its documentation are the product.

## 0. Understand before writing

1. Decide which case this is: a **new module**, or a **change** to
   `modules/<name>`. For a change, read the module's README, CHANGELOG,
   `docs/`, tests and the `<name>-gates` job in
   `.github/workflows/terraform-ci.yaml` first: odd-looking code is often a
   documented decision.
2. `scripts/tf-modules.sh list`: does a module already own this concern? Extend
   it rather than fork it, unless its contract would break.
3. Write down, before any HCL, and show the human if anything is a judgement
   call:
   - **Consumer and shape.** Who calls it, from an HCP Terraform workspace,
     with what they already own (BYO VPC, keys, buckets, topics).
   - **Interface.** Required inputs (only what cannot be defaulted), the
     few most-used optional ones, and the outputs a neighbour wires to.
   - **Contracts the caller must fulfil**, as outputs: key policy statements
     (KMS contract v2), topic policies, network endpoints.
   - **Failure modes**, ordered silent > late > expensive, and where each is
     guarded (`validation` / `precondition` / `check` / output field).
   - **What forces replacement** on each stateful resource. Verify it in
     provider source, not the schema: see [provider-facts.md](provider-facts.md).
   - **The growing cost line** and the default that bounds it.
4. A change that alters an unchanged caller's plan is **BREAKING**: removed or
   renamed inputs/outputs, a new required input, a changed default, an update
   that becomes a replacement, an address move, a raised floor. Say so up
   front; the human decides whether it is worth a major.

## 1. Scaffold (new module only)

```bash
scripts/new-module.sh <name>
```

It copies the template's module layer (a working log group that passes its
own tests), sets the `Module` tag and starts `CHANGELOG.md` at an unreleased
0.1.0. Then replace the log group with the real resources, keeping the
`create` switch, the tag merge, `acknowledged_checks`, `governance` and
`verify_commands` patterns. `templates/terraform-aws-module/TEMPLATE.md`
section 2 lists what each file becomes.

## 2. Write the module

Floors: `required_version = ">= 1.9.0"`; `hashicorp/aws` a bounded range
(`">= 5.x.0, < 7.0.0"`, or `< 6.0.0` if a v6 change breaks you, stated in the
README). Raise a floor only with a reason in the CHANGELOG.

Checklist, every item load-bearing:

- [ ] One concern per file: `versions.tf`, `variables.tf`, `locals.tf`,
      `data.tf`, `outputs.tf`, then a file per resource group. No `provider`
      blocks in the module.
- [ ] Every variable: `type`, `description` (the registry's reference doc;
      include the price for paid knobs), `nullable = false`, a default unless
      it truly must be supplied. `""` means unset for optional strings.
- [ ] A `validation` for everything that reaches an AWS API or a document run
      as root. Error messages say what is wrong and what is valid.
- [ ] **No `||` / `&&` relying on short-circuit.** 1.9 evaluates both sides.
      Use a nested ternary, `can()` or `alltrue([for ...])`, in locals too.
- [ ] `var.create` gates everything; `create = false` plans to nothing and
      leaves every output null or empty. Placeholder locals keep ARN strings
      buildable.
- [ ] Never `for_each` over a computed value; iterate the caller's input.
- [ ] `merge(var.tags, { ManagedBy = "Terraform", Module = "<name>" })`,
      module keys last. Transient resources and produced artifacts get their
      own tag variables.
- [ ] Contracts emitted as structured outputs; KMS requirements carry `sid`,
      `principals = { services, arns, roles }`, `actions`,
      `conditions = [{ test, variable, values }]`, `purpose`.
      `kms:ViaService` never on a service-principal entry.
- [ ] Immutable versions derived from a hash of **every** input that forces
      replacement; `create_before_destroy` where a downstream pins the version.
- [ ] Renamed or restructured addresses get a `moved` block, kept forever.
- [ ] IAM least privilege: no `*` action or resource without a comment naming
      why; trust policies with `aws:SourceArn` / `aws:SourceAccount`.
- [ ] Encryption at rest and in transit on by default; nothing secret in
      state, plan or an unmarked output.
- [ ] Comments short: the mechanism or the trap, no history, no file-top
      essays.

## 3. Tests

In `tests/*.tftest.hcl`, against `mock_provider`:

- [ ] Baseline `variables` is a **fully configured** module, so the module's
      own advisory checks pass.
- [ ] One `run` per property, named in prose for the property.
- [ ] Every `validation`, `precondition` and `check`: a run that passes and a
      run that trips it, with `expect_failures` on the exact address.
- [ ] `create = false` asserts resources **and** outputs are empty.
- [ ] Assert invariants (the policy grants exactly X to Y), not existence.
- [ ] Where the mock cannot prove something (replacement, real policy JSON,
      AWS acceptance), a comment says so; see [provider-facts.md](provider-facts.md).
- [ ] If the module has `tests/lint_validations.py`, it is a byte-identical
      copy of `modules/ami-builder/tests/lint_validations.py`. New Python
      linters ship with a `--self-test`.

## 4. Docs and examples

Per `.kiro/steering/30-docs.md`: README leads with a registry usage block,
then requirements, then **what it refuses** and the advisory checks, then
most-used inputs (≤ 15 rows), contract outputs, limits (including what has
never run against real AWS), versioning. COSTS.md with pricing date and
basis. CHANGELOG entry under the unreleased heading, BREAKING marked.
`examples/basic` (smallest call) and `examples/complete` (every input) must
validate. Relative links only.

## 5. Wire it into CI and governance

- [ ] Add the module to the `validate` matrix in
      `.github/workflows/terraform-ci.yaml` (governance rule G009 fails
      otherwise). If it ships Python linters, add a `<name>-gates` job that runs
      each with its self-test, plus the linter drift check, plus the v5 leg.
- [ ] `python3 scripts/check_governance.py` reports nothing new. Never add the
      new module to `.github/governance-baseline.json`; fix the cause.
- [ ] `.github/dependabot.yml` gains the directory if the module ships a
      Dockerfile or requirements file.

## 6. Verify, then hand over

```bash
make check MODULE=<name>
python3 scripts/check_governance.py
```

Run the steps of the module's `<name>-gates` job as well. Paste the tail of
each run. Then report: what was built, the interface, the refusals, what is
proven by tests, what is only proven by reasoning, and what needs a real
apply ("Not checked"). Offer `/tf-module-review <name>` and
`/tf-module-security <name>` as the next step.

Never run `plan`, `apply`, `destroy`, `import` or `state` commands, and never
commit unless asked (`/tf-module-commit`).
