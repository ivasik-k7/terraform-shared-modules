# Starting a new module from this template

This repository is a working module (a CloudWatch log group) and the template
for new ones. Everything in it passes CI as it stands, so a new module starts
green and each change shows what it broke.

## 1. Create the repository

On GitHub: **Use this template** → `terraform-aws-<name>`. The HCP Terraform
private registry requires the name `terraform-<provider>-<name>`.

## 2. Replace the example

| File | Do |
|---|---|
| `main.tf`, `variables.tf`, `locals.tf`, `outputs.tf`, `checks.tf` | Replace the log group with your resources; keep the `create` switch, the tag merge, `acknowledged_checks`, `governance` and `verify_commands` |
| `locals.tf` | Set `module_tags.Module` to the module name |
| `data.tf` | Keep, or delete the data sources you do not use |
| `versions.tf` | Set the floors your resources need; write versions without a leading `v` |
| `tests/*.tftest.hcl` | Replace the runs; keep the three files' roles (properties, guards, examples) |
| `examples/basic`, `examples/complete` | The smallest call, and every input |
| `README.md` | Name, usage, refusals, checks, contracts, limits |
| `COSTS.md` | The billable lines and the one that grows |
| `CHANGELOG.md` | Empty the 0.1.0 entry |
| `.github/CODEOWNERS` | The owning team |
| `.github/dependabot.yml` | One `directories` entry per example |
| `tests/check_consistency.py` | Update the self-test's anchors (it says which) |

`make check` after each step: the consistency checker and the linters say
what is out of step.

## 3. Repository settings

- **Branch protection on `main`**: pull requests only, one approving review
  from CODEOWNERS, and these checks required: `terraform fmt`, every
  `test (...)` leg, `tflint and the repository's own linters`,
  `trivy config scan`, `conventional`.
- **Squash merge only**, with the pull request title as the commit message.
- **Private vulnerability reporting** on (Security tab).
- **Dependabot** alerts and security updates on.
- **Actions**: allow only actions pinned to a full commit SHA, if the
  organization supports it.

## 4. Publish

In HCP Terraform: Registry → Publish → Module → this repository, tag-based.
The first release is the release pull request release-please opens after the
first `feat:` merge (0.1.0).

## 5. Delete this file

And the template note at the top of README.md.
