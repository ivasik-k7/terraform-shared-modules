---
name: tf-module-commit
description: Commit module work from a working tree full of unrelated uncommitted changes - stage by explicit path, one module per commit, conventional message type(module) subject, BREAKING detection, CHANGELOG and checks before committing. Never pushes. Use only when the user explicitly asks to commit.
argument-hint: "[module name(s) or path(s)]"
disable-model-invocation: true
---

# Commit module work

Target: `$ARGUMENTS` (empty: work out the candidates and ask)

The working tree here usually carries a lot of the human's uncommitted work.
Committing the wrong half of it is the failure this skill exists to prevent.

## Never

- `git add -A`, `git add .`, `git add -u`, `git commit -a`: stage explicit paths only.
- Stash, reset, restore, clean or check out over anything.
- `--no-verify`, `--amend` on a commit that is not yours from this session,
  rebase, or a push / tag / release of any kind.
- Stage a secret-bearing file (`.env`, `*.pem`, `*.key`, `*.tfvars`,
  `*.tfstate*`). The `.githooks/pre-commit` hook refuses them too.

## 1. Inventory

```bash
git status --porcelain
git diff --stat
git diff --cached --stat     # already staged by the human: leave it, and say so
```

Group paths: per `modules/<name>/` (with its root `examples/` that call it,
from `scripts/tf-modules.sh examples <name>`), repo tooling, docs. If the
target is empty or ambiguous, show the groups and ask which to commit.
If something is already staged that is not in the target, stop and ask.

A file that mixes intended and unintended changes cannot be split
non-interactively here: say so and let the human stage it.

## 2. Gates before staging

```bash
make check MODULE=<name>         # per module being committed
python3 scripts/check_governance.py
```

A failure blocks the commit unless the human says otherwise; show the tail of
the output either way.

## 3. Is it breaking?

Compare against `HEAD` for the module (`git diff HEAD -- modules/<name>`):

| Change | Breaking for an unchanged caller? |
|---|---|
| Input or output removed or renamed | yes |
| New variable without a default | yes |
| A default changed | yes |
| Resource address changed (without a `moved` block it is also a bug) | yes, even with `moved` if it replaces |
| An update that becomes a replacement | yes |
| `required_version` or provider floor raised, ceiling lowered | yes |
| New optional input, new output, new `check` | no |

Breaking means `!` after the scope and a `BREAKING CHANGE:` footer, and a
**BREAKING** line in the module CHANGELOG.

## 4. CHANGELOG

The module's `CHANGELOG.md` has an entry under its unreleased heading for
this change (Keep a Changelog sections: Added, Changed, Deprecated, Removed,
Fixed, Security). If it is missing, draft it, show it, and add it with the
human's agreement. Tooling-only and test-only commits need none.

## 5. Stage and commit

One commit per module unless the changes cannot work apart. Stage the paths,
then show `git diff --cached --stat` before committing.

Message:

```
type(scope)!: subject in lowercase, imperative, no period, <= 72 chars

Why the change was needed, and what an unchanged caller's plan now shows.
Wrap at 72.

BREAKING CHANGE: what the caller must do.
```

- `type`: feat, fix, docs, test, ci, refactor, perf, chore, revert.
- `scope`: the module directory name; `repo`, `ci` or `docs` for repo-level work.
- End with the attribution trailers the session is configured with.

Pass the message through a heredoc (`git commit -F - <<'EOF'`) so nothing is
shell-interpreted. If a hook fails, fix the cause and commit again (a new
commit, not `--amend`).

## 6. Report

`git log --oneline -n <count>` and `git show --stat HEAD` for each commit
made, what remains uncommitted, and whether anything was left staged by the
human. Pushing is the human's next step, not yours.
