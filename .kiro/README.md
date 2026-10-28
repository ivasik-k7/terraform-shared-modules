# Kiro configuration for this repo

Two separate things live here: **context** that makes the agent write code the
way this repo writes code, and **permissions** that keep it away from the small
set of actions nobody wants done on their behalf.

## Steering — the context

`.kiro/steering/*.md`, loaded by front matter:

| File | Loads | Carries |
|---|---|---|
| `00-repo.md` | always | What the repo is, the verification battery, comment and naming style |
| `40-guardrails.md` | always | What never happens without being asked, and what to do when blocked |
| `10-terraform-modules.md` | `modules/**/*.tf` | Variable rules, the 1.9 eager-operator rule, validation vs precondition vs check, the patterns that are load bearing |
| `20-tests.md` | `**/tests/**` | What `mock_provider` cannot prove, test naming, the linter self-test rule |
| `30-docs.md` | `**/*.md` | README / COSTS / ROLLOUT conventions, pricing-basis discipline |
| `50-finops.md` | `modules/**` | Tag attribution and naming the unbounded cost line |

If your Kiro build ignores the front matter, everything loads as always-on
context — the files are written to be readable in that mode too, just noisier.
Check what actually loaded in the context panel, or reference one explicitly
with `#00-repo`.

## Permissions — the model, and why it is an allow-list

`.vscode/settings.json` holds `kiroAgent.trustedCommands`. A command matching an
entry runs without asking; **everything else prompts.** So the posture comes
from what is deliberately *missing* from that list, not from a deny-list — which
matters, because a deny-list is trivially stepped around (`git push` vs
`git -C . push`, `rm -rf` vs `find -delete`) and gives false confidence.

| Runs silently | Always prompts |
|---|---|
| Reading anything: `cat`, `grep`, `find`, `sed -n`, `jq` | `git push`, `git commit`, tags, anything touching a remote |
| Git reads: `status`, `diff`, `log`, `show`, `blame` | `git reset --hard`, `clean`, `rebase`, `stash drop` |
| `terraform fmt`, `validate`, `test`, `init -backend=false` | `terraform apply`, `destroy`, `import`, `state *`, `plan` |
| `tflint`, `terraform-docs`, the repo's Python linters | `rm`, `mv`, `dd`, `truncate`, `chmod -R`, `shred` |
| `shellcheck`, `bash -n`, `yamllint` | Every mutating `aws` call |
| `aws sts get-caller-identity` | `curl`/`wget`, package installs |

`terraform plan` is deliberately in the right-hand column: it is read-only
against your infrastructure but it still uses live credentials, and it writes
provider caches. `git commit` is there because commits are cheap to make and
annoying to unpick from someone else's history — move it left if the prompting
gets in the way, it is a taste call rather than a safety one.

**Adding to the list:** only if the worst case of running it unattended is a
wasted second. That is the whole test.

## Hard blocks — git hooks

Installed with:

```bash
git config core.hooksPath .githooks     # already set in this clone
git config --unset core.hooksPath       # to undo
```

| Hook | Refuses |
|---|---|
| `pre-push` | Any push without `ALLOW_PUSH=1`; direct pushes to `main`/`master`; remote branch deletion; non-fast-forward pushes (these three even with the opt-in) |
| `pre-commit` | Staged `.env`, `*.pem`, `*.tfvars`, `terraform.tfstate*`, keys; AWS key ids, GitLab runner tokens or private keys in the diff; unformatted `.tf` (the same gate CI runs) |

To push deliberately:

```bash
ALLOW_PUSH=1 git push origin feat/your-branch
```

AWS's documentation key (`AKIAIOSFODNN7EXAMPLE`) is exempted, because it appears
in this repo's own linter self-tests and would otherwise make them
uncommittable.

## Agent hooks

`.kiro/hooks/terraform-gate.kiro.hook` re-runs the CI gates after a module file
changes. The JSON schema for these differs between Kiro versions — if it does
not appear under Agent Hooks, create one through the UI, compare the file it
writes, and adjust this one.

## What this does not do

Be clear about the boundary, because a config file is not a sandbox:

- `--no-verify` skips both hooks, and anything with shell access can call git
  another way. The hooks catch **accidents**, from any tool, including you at
  2am. They are not a control against a determined agent.
- **The real boundary is on the remote.** Branch protection on `main` (required
  PR, no force push, no deletion) is the only version of "cannot push to main"
  that actually holds.
- **The other real boundary is credentials.** The agent's terminal inherits your
  AWS profile, so nothing here prevents an `apply` that you approve at a prompt.
  Point the default profile at read-only, and assume a deploy role explicitly
  when you mean to change something.
- **Move `key.pem` and `.env` out of the workspace.** They are gitignored, so
  they will not be committed — but they are still readable by anything with
  workspace access, and the safest secret is the one that is not there.
