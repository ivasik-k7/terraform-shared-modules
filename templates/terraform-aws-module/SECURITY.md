# Security

## Reporting

Report a vulnerability privately, through GitHub's **Report a vulnerability**
on the Security tab, not as an issue or a pull request. Include the module
version, the configuration that shows it, and what it exposes. You will get
an answer within five working days.

## What counts

- The module grants more than its documentation says (IAM, key policies,
  network rules).
- A secret reaches the plan, the state or an output unmarked.
- A guard the README promises (a refusal or a check) can be bypassed by a
  valid configuration.

## What this repository does about it

- Actions are pinned to commit SHAs; updates wait 14 days (Dependabot
  cooldown).
- CI scans the configuration with trivy on every pull request.
- pre-commit runs gitleaks and refuses private keys and AWS credentials.
- `main` takes changes only through reviewed pull requests (CODEOWNERS).
