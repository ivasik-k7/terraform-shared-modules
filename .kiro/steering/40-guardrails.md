---
inclusion: always
---

# Guardrails

The rule behind all of these: **anything that leaves this machine, destroys
work, or spends money is the human's call.** Everything else, go ahead.

## Never, without being asked in that turn

- **Push.** `git push` to any remote, any branch, force or not. Also: no tags,
  no PRs, no issue comments, no release creation. Committing locally is fine
  *when asked*; pushing never is.
- **Rewrite or discard work.** `git reset --hard`, `git clean -fd`,
  `git checkout --` over uncommitted changes, `git rebase`, `git stash drop`,
  `filter-branch`. This tree usually carries a lot of uncommitted work in
  progress — it belongs to the human, and "tidying" it is data loss.
- **Delete or truncate.** `rm -rf`, any recursive delete, `find -delete`,
  `truncate`, `dd`, `shred`, `mkfs`, `mv` onto an existing path, `chmod -R`,
  `chown -R`. To remove a tracked file use `git rm` so it is recoverable, and
  ask first.
- **Change real infrastructure.** `terraform apply`, `destroy`, `import`,
  `state mv|rm|push`, or any mutating `aws` CLI call. `terraform plan` and
  read-only `aws describe-*`/`get-*` still use live credentials — say which
  profile you would use and ask.
- **Touch secrets.** Do not read, copy, print or move `.env`, `*.pem`,
  `*.tfvars`, `terraform.tfstate*`, `~/.aws/credentials`, or anything that looks
  like a token. Do not paste their contents into a file, a commit, or the
  transcript. If a task appears to need one, stop and say so.
- **Fetch and execute.** No `curl | sh`, no `pip install`/`npm install -g` of
  something not already declared, no downloading binaries.

## Safe, and expected

`terraform fmt`, `validate`, `test` (mocked, no credentials), `tflint`, the
Python linters, `git status|diff|log|show`, reading and editing files in the
workspace, creating new files, running `grep`/`find`/`sed -n`.

Run the verification battery from `00-repo.md` before reporting that something
works. "Tests pass" without a run in the transcript is not a claim, it is a
guess.

## When you are blocked

Say what you would run, why, and what it would change — then let the human run
it. Do not look for a way around a guardrail (a different flag, a script that
wraps the same command, `--no-verify`). Finding the bypass is the failure mode
this file exists to prevent, and the git hooks in `.githooks/` will not stop a
determined agent either — they are there to catch accidents.

## Prefer recoverable working shapes

For anything risky, work on a branch or in a `git worktree`, so the worst case
is a discarded branch rather than a lost afternoon.
