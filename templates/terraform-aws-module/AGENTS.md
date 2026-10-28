# Notes for AI coding assistants

Read CONTRIBUTING.md first: its conventions apply to you unchanged. This file
adds what is specific to an agent working in this repository.

## Verify before you claim

Run `make check` and paste its result before saying something works. "Tests
pass" without the run is a guess. Provider behaviour (replacement, defaults,
enums) comes from `terraform providers schema -json` or the provider source
at the pinned version; AWS behaviour from the AWS documentation, quoted. What
you could not verify, say so.

## Never, unless the human asks in that turn

- Push, tag, open or merge pull requests, or create releases.
- `terraform apply`, `destroy`, `import` or `state` commands, or any
  mutating AWS CLI call. Plans also use real credentials: ask first.
- Delete, reset or discard work: `rm -rf`, `git reset --hard`, `git clean`,
  `git checkout --` over uncommitted changes.
- Read or copy secrets: `*.tfvars`, `*.tfstate*`, `~/.aws/credentials`,
  `.env`, keys and tokens.
- Install or fetch-and-run anything not already declared (`curl | sh`,
  `pip install`).

## Safe, and expected

`terraform fmt`, `validate`, `test` (mocked), `tflint`, the Python linters,
reading and editing files, `git status|diff|log`.

## Style

Comments are short and state the mechanism or the trap; history belongs in
the CHANGELOG. If a comment is longer than the code it explains, it belongs
in the README.
