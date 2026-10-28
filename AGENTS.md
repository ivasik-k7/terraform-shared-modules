# Notes for AI coding assistants

The conventions live in `.kiro/steering/`, written for any agent. Read them
before changing anything:

| File | Carries |
|---|---|
| `.kiro/steering/00-repo.md` | What the repo is, the verification battery, comment and naming style |
| `.kiro/steering/40-guardrails.md` | What never happens without being asked |
| `.kiro/steering/10-terraform-modules.md` | Variables, the 1.9 eager-operator rule, validation vs precondition vs check, load-bearing patterns |
| `.kiro/steering/20-tests.md` | What `mock_provider` cannot prove; test naming |
| `.kiro/steering/30-docs.md` | README, CHANGELOG, COSTS and upgrade-guide conventions |
| `.kiro/steering/50-finops.md` | Tag attribution and the unbounded cost line |

Then `CONTRIBUTING.md` for the workflow and `make help` for the commands.

## The short version

- Verify before you claim: `make check MODULE=<name>`, and paste the result.
- Never push, tag, apply, destroy, import, touch state, or read secrets
  (`.env`, `*.pem`, `*.key`, `*.tfvars`, `*.tfstate*`) unless the human asks
  in that turn.
- The working tree carries the human's uncommitted work: stage by explicit
  path, never discard or "tidy" it.
- Links in documents are relative; never write the repository URL or owner.
