# Security policy

## Reporting a vulnerability

Report privately, never as a public issue or pull request:

1. **Preferred:** the **Report a vulnerability** button on the repository's
   Security tab (private vulnerability reporting).
2. **Otherwise:** email [kovtun.ivan@proton.me](mailto:kovtun.ivan@proton.me)
   with the subject `[SECURITY] <module>: <short description>`.

Include the module and version (the tag, e.g. `aurora-v2.0.0`), a minimal
configuration that shows the problem, what it exposes, and a fix if you have
one.

| Step | Target |
|---|---|
| Acknowledgement | 2 working days |
| Assessment and severity | 5 working days |
| Fix released for Critical / High | as fast as the fix can be proven, normally within 14 days |
| Advisory published | when the fixed version is tagged |

Reporters are credited in the advisory unless they ask not to be.

## Supported versions

Modules are versioned independently (tags `<module>-vX.Y.Z`).

| Version of a module | Security fixes |
|---|---|
| Latest minor of the current major | Yes |
| Previous major | For 6 months after the next major is tagged |
| `0.x` and anything marked experimental in its README | Best effort; upgrade |
| Untagged `main` | No: consume tagged versions |

## What counts as a vulnerability here

- The module grants more than its documentation says: IAM policies, trust
  policies, key policies, resource policies, network rules.
- A secret reaches state, a plan, logs or an output that is not marked
  `sensitive`.
- A refusal or guard the README promises can be bypassed by a valid
  configuration.
- An insecure default: public exposure, encryption off, audit logging off,
  IMDSv1, without the description making the trade-off explicit.
- Code the module runs with privilege (user data, SSM documents, build
  components, container entrypoints) can be made to run caller-controlled
  input.
- A supply-chain gap: an unpinned artifact fetched at runtime, a download
  without checksum verification.

Out of scope: misconfiguration by the caller that the module documents as the
caller's responsibility, and findings in examples that are labelled as
non-production.

## What this repository does about it

| Control | Where |
|---|---|
| Secret scanning on every push and pull request | gitleaks in `terraform-ci.yaml`; `.githooks/pre-commit`; pre-commit's `gitleaks` and `detect-private-key` |
| Misconfiguration scan of every changed module, blocking at HIGH/CRITICAL | `.github/workflows/security.yml` (trivy); accepted findings in `.trivyignore`, each with a reason |
| IAM policy rendering and linting for modules that write policies | the `<module>-gates` jobs in `terraform-ci.yaml` |
| Workflow linting | `.github/workflows/governance.yml` (actionlint) |
| Third-party actions pinned to commit SHAs; updates after a 14-day cooldown | every workflow; `.github/dependabot.yml` |
| Changes to `main` only through reviewed pull requests | branch protection and `.github/CODEOWNERS` (see [docs/GOVERNANCE.md](docs/GOVERNANCE.md)) |
| Security review of modules before release | `/tf-module-security` (see [CLAUDE.md](CLAUDE.md)) |

## For contributors

The rules a module must meet are in [CONTRIBUTING.md](CONTRIBUTING.md#security-requirements).
Never commit credentials, state, `*.tfvars`, keys or certificates; the hooks
refuse them, and a secret that reached history must be rotated, not just
deleted.
