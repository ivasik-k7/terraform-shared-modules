# CLAUDE.md

The conventions for this repository are written once, for every agent, in
`.kiro/steering/`. Claude loads them from there so the two never drift:

@.kiro/steering/00-repo.md
@.kiro/steering/40-guardrails.md
@.kiro/steering/10-terraform-modules.md
@.kiro/steering/20-tests.md
@.kiro/steering/30-docs.md
@.kiro/steering/50-finops.md

Change a convention in the steering file, not here. What follows is specific
to working in Claude Code.

## Skills

| Skill | Use for |
|---|---|
| `/tf-module-create <name or feature>` | A new module, or a feature, input, output or guard on an existing one |
| `/tf-module-review <module>` | Pre-merge or pre-release review; findings proven in-session |
| `/tf-module-security <module>` | IAM, KMS contracts, network, secrets in state, supply chain |
| `/tf-module-commit [module]` | Committing from a tree full of unrelated work; only when asked |

`.claude/commands/review-tf-module.md` is the full review method the review
skill follows.

## Commands

```bash
make check MODULE=<name>     # fmt, validate, test, examples, linters (+ tflint/trivy if installed)
make check                   # the modules changed in the working tree, plus repo-wide gates
make governance              # module conventions against .github/governance-baseline.json
make release-check MODULE=<name> VERSION=<x.y.z>
scripts/new-module.sh <name> # scaffold from templates/terraform-aws-module
```

Module-specific CI gates (Python linters, render-and-lint jobs, provider v5
legs) are the `<module>-gates` jobs in `.github/workflows/terraform-ci.yaml`.
Run the steps of that job too before saying a module is green.

## Working rules

- **Only in-session proof counts.** A claim about provider behaviour, AWS
  behaviour or this code is believed once a command, a quoted line, provider
  source at the pinned version or AWS documentation shows it. Memory, earlier
  conclusions and subagent reports are leads, not evidence. What cannot be
  proven goes under "Not checked" and never drives a fix.
- **Replacement semantics are not in the schema.** `terraform providers schema
  -json` gives types and optional/computed; `ForceNew`, defaults and enums
  come from the provider source at the pinned tag. `mock_provider` cannot show
  a replacement at all.
- **The working tree is the human's.** It usually carries a lot of
  uncommitted work. Stage by explicit path, never `git add -A`, `.` or `-u`;
  never stash, reset, clean or check out over it.
- **Removed comments stay removed.** If a comment you wrote disappears between
  edits, the human deleted it. Do not restore it.
- **Links are relative, always.** Never write the repository's URL, owner or
  name into a tracked file, and ask before writing a registry organization
  name into new docs.
- **Delegate with the right model.** Searches and mechanical code-vs-doc
  comparison: a light model. Analysis and design judgement: the strongest.
  Re-verify a subagent's claims line by line before relaying them.

## Permissions and hooks

`.claude/settings.json` mirrors the allow-list model in `.kiro/README.md`:
reads and offline Terraform run silently; commits, pushes, plans, applies,
state commands and recursive deletes always prompt; secret files cannot be
read. Two hooks: `terraform fmt` after every edit of a `.tf` or `.tftest.hcl`
file, and a prompt before any shell command that names a secret file.
