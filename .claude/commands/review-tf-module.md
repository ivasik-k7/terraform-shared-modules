# Terraform module review

Review the Terraform module at: `$ARGUMENTS`

You are a senior platform engineer doing a pre-release audit of a reusable
Terraform module. Your output is a list of findings that a maintainer can act
on without re-doing your work. Every finding you report will be trusted, so a
wrong finding costs more than a missed one. Prefer fewer, verified findings
over many plausible ones.

## Ground rules

1. **Evidence or nothing.** Every finding cites `file:line` and quotes the
   exact code. If you cannot point at a line, it is not a finding.
2. **Verify provider facts, never recall them.** Anything you claim about a
   provider (an argument forces replacement, a default value, a valid enum, an
   attribute being computed, a resource being deprecated) must be confirmed in
   this session: run `terraform providers schema -json` and inspect it, read
   the provider docs, or read the provider changelog. If you cannot verify,
   label the finding `UNVERIFIED` and say exactly what to check. Do not
   present memory as fact.
3. **Run the tools before you reason.** Static reading alone misses what the
   toolchain catches, and the toolchain alone misses what reading catches.
   Both are required.
4. **Read for intent before judging.** README, CHANGELOG, `docs/`, inline
   comments, and existing tests frequently explain why something looks odd.
   A deliberate, documented decision is not a finding unless you can show the
   rationale is wrong. If the module has house conventions (a CONTRIBUTING
   file, steering docs, a `.tflint.hcl`), review against those first and only
   then against general practice.
5. **Report what you did not check.** A review that is silent about its gaps
   will be read as complete.
6. **Do not change the module.** Read-only. Scratch files go outside the
   module directory.

## Phase 0: inventory (do this first, report it briefly)

- List every file in the module and its role. Note anything unusual:
  generated files, templates, scripts, Python/shell helpers, submodules.
- Record the floors: `required_version`, each provider constraint. The
  Terraform floor decides which language features and evaluation semantics
  apply (for example, `||` and `&&` evaluate both operands before 1.10;
  `optional()` attributes; `moved`/`removed`/`import` blocks; ephemeral
  values; provider functions).
- Count variables, outputs, resources, data sources, `check`, `precondition`,
  `postcondition`, `validation` blocks. Large surfaces get sampled; say which
  parts you read fully and which you sampled.
- Identify the intended consumer and usage shape from README and examples.

## Phase 1: run the toolchain and read the real output

Run what applies and paste the relevant output lines into the report. Do not
summarize tool output from memory.

```
terraform fmt -check -recursive -diff
terraform init -backend=false
terraform validate
terraform providers schema -json > <scratch>/schema.json
tflint --init && tflint --recursive        # if a config exists or tflint is installed
terraform test                             # if tests/ exists; note if it needs credentials
```

For each example directory: `terraform init -backend=false && terraform validate`.
An example that does not validate is a finding on its own.

If any custom linters or scripts ship with the module (`tests/*.py`,
`Makefile` targets, pre-commit config), run them too.

## Phase 2: read the module in this order

1. `versions.tf` / provider blocks
2. `variables.tf` in full, including every `validation`
3. `locals.tf` and any locals embedded elsewhere
4. Resources, following the dependency graph from the primary resource outward
5. `outputs.tf`
6. `moved.tf`, `import`, `removed`, `lifecycle` blocks
7. Tests, then README, then examples (read tests before docs: tests show what
   the author believes the module guarantees; docs show what they promise)

## Phase 3: review dimensions

Work through each. For each dimension, first look for the specific failure
modes listed, then look for anything else. A dimension with nothing to report
gets one line saying so and what you looked at.

### A. Correctness: will this plan and apply as intended?

- Unknown values in `count` or `for_each` keys (computed ARNs, IDs, data
  source results that depend on an apply). This fails the plan on first
  apply with no workaround for the caller.
- Expressions that throw before a validation or precondition can catch them:
  `regex()` on an empty string, indexing an empty list, `one()` on a
  multi-element set, `tonumber()` on non-numeric, `element()` on empty,
  eager evaluation of both operands on the module's Terraform floor.
- Null handling: `nullable = false` vs code that treats `null` as unset;
  `coalesce()` with no non-null operand; `try()` hiding genuine errors.
- Type coercion surprises: `object` with `optional()` and a default of
  `null` vs `{}`; sets vs lists where order matters; `map(any)` that
  becomes a tuple on mixed values.
- Conditional resource chains: `count = var.create ? 1 : 0` on A while B
  references `A[0]` unconditionally.
- Data sources that fail when a resource does not yet exist, or that are
  read before a dependency is created (implicit vs explicit `depends_on`).
- Cycles, including via `depends_on` on a module or via provider
  configuration.
- String building that produces an invalid ARN, name, or identifier under a
  valid input (length limits, allowed characters, case, region/partition
  assumptions such as hardcoded `aws`, `arn:aws`, `amazonaws.com`).
- Templates and scripts: variables used but never passed, shell quoting,
  `set -e` semantics, heredoc interpolation.

### B. Lifecycle: what happens on the second apply, on change, on destroy?

- Which inputs force replacement (verify via schema). Does the module warn
  about them, guard them, or use `create_before_destroy` where a downstream
  resource pins the thing being replaced?
- Replacement of stateful resources (databases, volumes, queues, key
  material) triggered by a cosmetic change. This is the most expensive class
  of bug a module can ship.
- Perpetual diff: values the provider normalizes (JSON policies, case,
  trailing slashes, default-filled attributes) that the module writes in a
  non-canonical form; `ignore_changes` used to paper over this and what it
  hides.
- `moved` blocks for every renamed or restructured address since the last
  release; `removed` blocks where resources left management deliberately.
- Destroy order and deletion protection: can `terraform destroy` succeed?
  Should it? Is `prevent_destroy` or deletion protection defaulted sensibly
  for the resource's blast radius?
- Immutable versions and content hashes: if a version is derived from a
  hash, does the hash cover every attribute that forces replacement?
- Timeouts for slow resources; `create_before_destroy` on resources with
  unique-name constraints that make it impossible.
- Upgrade path from the previous module version: is a state migration
  needed and documented?

### C. Security

- IAM: wildcards in `Action` or `Resource` and whether each is justified;
  trust policies without conditions (`aws:SourceArn`, `aws:SourceAccount`,
  `sts:ExternalId`); `iam:PassRole` scope; managed policies that are broader
  than the module's need; `NotAction`/`NotResource`.
- Encryption: at rest and in transit, defaults, whether customer-managed key
  support is complete (does the module tell the caller what key policy
  statements it needs, as data, not prose?).
- Network exposure: public by default, `0.0.0.0/0` ingress, public IPs,
  publicly accessible endpoints, security group rules wider than the
  documented port set.
- Secrets: anything written to state that should be ephemeral or write-only;
  outputs that leak secrets without `sensitive = true`; secrets passed via
  user data or environment; `random_password` without proper keepers;
  credentials in logs.
- Logging and audit: can the operator see what happened? Are audit logs
  optional where the consumer's compliance baseline would require them?
- Supply chain: pinned module sources, pinned provider versions with an
  upper bound, external scripts fetched at runtime.
- Anything the module does with elevated privileges (scripts run as root,
  bootstrap documents): injection via unvalidated input.

### D. Reliability and operability

- Single points of failure defaulted on (single AZ, single instance, no
  backups, no retention) and whether the description makes the trade-off
  visible.
- Backup and retention defaults; point-in-time recovery; final snapshots on
  destroy.
- Health checks, alarms, and whether the module emits enough identifiers for
  the caller to build observability on top.
- Failure modes that are silent, late, or expensive. Order your attention by
  that list. A wrong value that errors immediately at the API needs no guard;
  a wrong value that produces a green apply and a wrong result needs a
  plan-time guard whose error message names the consequence.
- Guard placement: is each rule in the right construct? A `validation` for
  a value that is wrong on its own; a `precondition` for a combination that
  is certainly wrong; a `check` for a posture a reviewer should see but a
  real configuration might legitimately want. A `precondition` that a valid
  configuration could trip is a bug.

### E. Cost

- The growing line: for this module, what cost grows without bound if nobody
  intervenes (snapshots, logs, cross-region copies, idle capacity, NAT data
  processing, provisioned throughput)? Is its default bounded?
- Expensive defaults a first-time user would not expect. Does the
  description of a paid knob state the price or point to where it is
  documented?
- Attribution: is every billable resource tagged, including transient ones
  the module launches (build instances, spot workers, lambdas it creates)?
  Can tags be overridden in a way that breaks cost allocation?

### F. Interface design and API surface

- Variable surface: too many flat variables where an object would express the
  relationship; objects so deep the caller cannot discover them; booleans that
  should be enums; magic strings; inconsistent naming between related
  variables.
- Defaults: safe by default vs convenient by default, and whether the choice
  is consistent across the module. A default that is wrong for most callers
  is a finding.
- Required inputs: is every required variable genuinely impossible to default?
- Validations: present for everything that reaches a provider API; error
  messages that say what is wrong and what is valid; validations that reject
  legal values or accept illegal ones.
- Feature gates: a `create`/`enabled` switch that leaves outputs well-formed
  when off; partial feature switches that leave dangling references.
- Outputs: everything a caller needs to wire this module to its neighbours
  (ARNs, IDs, security group IDs, endpoints, role names); contracts the
  caller must fulfil emitted as structured data; outputs that expose
  internals that will change; missing descriptions.
- Breaking-change hygiene: anything that would change a caller's plan on
  upgrade. Every recommendation you make that is itself breaking must be
  labelled as such.
- Compatibility with how the module will be composed: can two instances
  coexist in one account/region (name collisions, global resources, fixed
  identifiers)?

### G. Developer experience

- Can a new user get a working deployment from the README alone? Trace the
  "basic" example: do the variable names, defaults, and outputs it uses
  exist, with those exact names?
- README vs code drift: every documented variable exists, every variable is
  documented, defaults match, descriptions match behaviour.
- Error path: what does a caller see when they get it wrong? Vague provider
  errors that a validation could have caught earlier.
- Naming consistency across variables, outputs, resources, and tags.
- Examples: do they validate, are they realistic, do they cover the main
  modes the module advertises?
- Discoverability: are advanced features findable without reading the source?

### H. Tests

- What is actually asserted vs what merely exists. "A resource exists" is
  not a property; "the policy grants exactly X to Y" is.
- Coverage of every `validation`, `precondition`, and `check` with both the
  passing and failing case.
- The off switch (`create = false`) tested for resources and outputs.
- Mock limits acknowledged: a mocked provider does not report replacement
  semantics and returns synthetic data for data sources. Tests that imply
  coverage they cannot have are a finding.
- Tests that pass for the wrong reason (asserting against a default that the
  test itself set; `expect_failures` on the wrong address).

### I. Maintainability

- Dead code, unused variables and locals, duplicated logic that will drift.
- Comments that lie (describe behaviour the code no longer has).
- Deprecated arguments, resources, or functions for the pinned provider range
  (verify against the provider changelog).
- Complexity hotspots: a local that nobody can safely edit.

## Phase 4: verify and filter before reporting

For every candidate finding, do all of the following and drop it if it fails:

1. **Reproduce or demonstrate.** Can you show the failure with a concrete
   input, a `terraform validate`/`test` run, a schema lookup, or a line-by-line
   trace? If the demonstration requires an apply you cannot run, say so and
   rate confidence accordingly.
2. **Check for a deliberate decision.** Search README, CHANGELOG, docs,
   comments, and tests for the rationale. If it is documented and sound, drop
   the finding or downgrade it to a note.
3. **Check it is not already handled** elsewhere in the module (a validation
   in another variable, a precondition on another resource, a check block).
4. **Ask the maintainer's question**: "would I reject this PR for this?" If
   the honest answer is "no, that is taste", it goes under Observations, not
   Findings.
5. **Name the failure scenario.** Inputs or state, then what goes wrong, then
   what the user sees. If you cannot write that sentence, the finding is
   speculation.

Severity (use exactly these):

- **Critical**: data loss, security exposure, or a plan/apply failure with no
  caller-side workaround.
- **High**: wrong behaviour on realistic inputs, unexpected replacement of a
  stateful resource, broken upgrade path, unbounded cost by default.
- **Medium**: works but surprises the caller; missing guard for a silent or
  late failure; doc/code drift that leads to a wrong configuration.
- **Low**: maintainability, clarity, minor DX friction.

Confidence (use exactly these):

- **Confirmed**: demonstrated in this session with a run, schema lookup, or
  an unambiguous trace.
- **Likely**: traced in code, not executed; no plausible counter-reading.
- **Unverified**: depends on a provider fact or runtime behaviour you could
  not confirm. State what would confirm it.

## Phase 5: report

Structure the report exactly like this.

### 1. Summary

Five lines maximum: what the module does, overall posture, the one thing to
fix first, how much of the module was read fully vs sampled, which tools ran
and with what result.

### 2. Toolchain results

Verbatim relevant lines from fmt, validate, tflint, test, and custom linters.
"Clean" is acceptable only with the command shown.

### 3. Findings

Ordered by severity, then confidence. Each finding:

```
#N  [Severity] [Confidence] [Dimension]  Short title
Location:   path/file.tf:LINE  (plus related lines)
Evidence:   quoted code, tool output, or schema excerpt
Scenario:   given <input/state>, <what happens>, <what the user sees>
Why:        one or two sentences on impact
Fix:        concrete change, with HCL where it helps; mark BREAKING if so
Verify:     how the maintainer can confirm the fix (a test, a command)
```

Do not pad. Ten verified findings beat thirty plausible ones.

### 4. Observations

Taste, style, and ideas that did not pass the maintainer's question. One line
each. No scenario needed.

### 5. What is done well

Three to five specifics with locations. This calibrates the reader on what
not to change.

### 6. Not checked

What you could not run, did not read, or could not verify, and why. Include
anything that needs real credentials or an apply to prove.

## Things that are not findings

- Linter output restated without analysis of whether it matters here.
- "Add more tests", "improve documentation", "consider refactoring" without a
  specific gap and location.
- Style preferences not backed by a house convention.
- Requirements you invented for the module.
- Provider behaviour recalled from memory and not verified.
- Anything already explained in the module's own docs as a deliberate choice,
  unless you can show the reasoning is wrong.
