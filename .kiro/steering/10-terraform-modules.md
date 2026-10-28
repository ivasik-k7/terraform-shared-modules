---
inclusion: fileMatch
fileMatchPattern: "modules/**/*.tf"
---

# Writing Terraform in this repo

## Variables

- Every variable gets `type`, `description`, `nullable = false`, and a default
  unless it genuinely must be supplied.
- Anything that reaches an AWS API, or a document that runs as root, gets a
  `validation`.
- **The eager-operator rule.** The declared floor is Terraform 1.9, which
  evaluates *both* operands of `||` and `&&`. So never write
  `var.x == "" || regex(...)` — it crashes on the floor and passes on current.
  Use a nested ternary, `can()`, or `alltrue([for ...])`. This applies to
  `locals` too, where a throw happens before any check can report it.
  `tests/lint_validations.py` enforces it; run it after touching a condition.
- Empty string is the "unset" convention for optional strings, not `null`.

## Where a rule belongs

| Use | When |
|---|---|
| `validation` | The value is wrong on its own terms. No other input needed |
| `precondition` | The combination is wrong, or a data source contradicts it. Fails the plan |
| `check` | The posture is defensible but a reviewer should see it. Warns, never blocks |
| an output field | A fact a change review or a test needs. Emit it as data |

A hard failure has to be *certain*. If a real configuration could legitimately
want it, it is a `check`, not a `precondition`.

## Patterns that are load bearing here

- **`create` switch.** `var.create` gates everything, and `create = false` must
  plan to nothing *and* leave every output null or empty. Placeholder locals
  (`coalesce(one(data.x[*].y), "fallback")`) exist so ARN strings still build.
- **Immutable versions → content hashing.** Where an API rejects a reused
  version (Image Builder components, recipes, workflows), derive the version
  from a hash of the inputs. Every attribute that forces replacement on the
  resource **must** be in the hash input — miss one and a change replaces the
  resource without moving the version, which then fails unrecoverably.
- **Never `for_each` over a computed ARN.** Iterate the caller's list; put the
  computed value inside. An unknown in a `for_each` key cannot be planned.
- **`create_before_destroy`** wherever a downstream resource pins an exact
  version of the thing being replaced.
- **Contracts as data.** The module cannot set a key policy, a topic policy or a
  VPC endpoint, so it emits what the caller must provide as a structured output
  (`network_contract`, `kms_key_policy_requirements`,
  `sns_topic_policy_requirement`). Prose in a README is not a contract.
- **KMS requirements are compiled, so emit contract v2.** Every entry of
  `kms_key_policy_requirements` carries, besides its prose fields, `sid`
  (unique in the module), `principals = { services, arns, roles }` (all three
  lists, `[]` when empty), `actions`, `conditions = [{ test, variable,
  values }]` and `purpose`. A principal the module cannot know is a symbolic
  role: `deployer` for whoever runs Terraform, snake_case otherwise.
  `modules/kms` compiles these into key policies and reports any entry
  without them. `kms:ViaService` never goes on a service-principal entry.
- **Tags.** `merge(var.tags, { ManagedBy = "Terraform", Module = "<name>" })`,
  with module-controlled keys last so they cannot be overridden. Distinguish
  tags on the module's resources, on the produced artifact, and on transient
  build infrastructure — they are different variables for a reason.

## Failure-mode priority

Optimise guards for failures that are **silent, late, or expensive**, in that
order. A wrong value that errors immediately at the API needs no guard. A wrong
value that produces a green apply and an unencrypted artifact needs one at plan
time, and the error message should name what would have happened.
