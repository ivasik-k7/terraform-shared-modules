---
name: tf-module-security
description: Security audit of one Terraform module in this monorepo - threat model, IAM privilege escalation and confused-deputy trust, resource and KMS key policies (contract v2), encryption, network exposure, secrets in state/plan/outputs, audit logging, scripts that run as root, and supply chain - with every finding proven offline in this session. Use when asked for a security review, security audit or threat model of a module, or before releasing a module that grants access, stores data or opens a network path.
argument-hint: <module name or path>
---

# Security audit of a module

Target: `$ARGUMENTS`

Read-only, offline. Never call AWS, never plan or apply against an account,
never read secret files. Scratch work goes in the session scratchpad.

The bar is the same as a review here: **a finding is proven in this session
or it goes under "Not checked"**. Sources of truth are in
[provider-facts.md](../tf-module-create/provider-facts.md).

## 1. Threat model first (short, written down)

From README, variables and resources, state:

- **Assets**: data stores, keys, secrets, artifacts, logs the module creates or touches.
- **Principals**: every IAM role, user, service principal, OIDC subject and
  account the module creates or trusts, and who can assume each.
- **Trust boundaries**: account, organization, VPC, internet, CI system.
- **Privileged surfaces**: policies the module writes, documents that run as
  root (user data, SSM documents, AWSTOE components, container entrypoints),
  anything that executes a caller-supplied string.
- **What the module promises to refuse** (README "refuses" table): each
  promise is something to try to break.

## 2. Get the real artifacts

Policies are the evidence; reading HCL that builds them is not enough.

1. **Render offline.** If the module has `tests/render`, read its config: it
   must use mock credentials, `skip_*` provider flags and `create = false`.
   Only then `terraform init -backend=false` and `terraform apply` there, and
   export the policy outputs to the scratchpad. If the module has no render
   config, build one in the scratchpad on the same pattern
   (`modules/agent-warden/tests/render/main.tf`), calling the module by path,
   outputting the policy JSON. Ask before running an apply you have not read.
2. **Tests.** `terraform test` in the module; read which security properties
   are asserted and which are only claimed.
3. **Scanners, if installed:** `trivy config --severity HIGH,CRITICAL modules/<name>`,
   `checkov -d modules/<name>`. Triage every hit: a scanner line is a lead,
   not a finding. Check `.trivyignore` for accepted IDs and their reasons.
4. **IAM linters, if installed:** `parliament` on the rendered JSON
   (agent-warden's CI step shows the invocation).

## 3. What to look for

### IAM

- Escalation paths: `iam:PassRole` without `iam:PassedToService` and a role
  ARN scope; `iam:Create/AttachRole/PutRolePolicy`,
  `iam:CreatePolicyVersion`, `iam:UpdateAssumeRolePolicy`; `lambda:UpdateFunctionCode`
  or `ec2:RunInstances` together with PassRole; `ssm:SendCommand` on `*`;
  `sts:AssumeRole` on `*`.
- `*` in `Action` or `Resource`: each needs a reason the API forces it
  (some List/Describe actions do); otherwise a finding.
- `NotAction` / `NotResource` with `Allow`.
- Trust policies: service principals without `aws:SourceArn` /
  `aws:SourceAccount` (confused deputy); OIDC trust (`ci-oidc`, GitHub,
  GitLab) without `aud` and a pinned `sub` (repo **and** ref/environment); cross-account
  trust without `sts:ExternalId` or an org condition.
- Permission boundaries and SCPs the module emits: each prohibition is an
  unconditional explicit `Deny` (agent-warden-2's guardrail proof is the model).

### Resource and key policies

- `Principal: "*"` without `aws:PrincipalOrgID`, `aws:SourceVpce` or
  `aws:SourceAccount`.
- KMS: `kms_key_policy_requirements` entries carry the v2 fields; actions are
  the minimum (no `kms:*`); `kms:ViaService` not on a service-principal
  entry; `kms:CreateGrant` constrained (`kms:GrantIsForAWSResource`) unless
  the grantee needs otherwise; the key region matches the resource region.
- S3: public access block on, `aws:SecureTransport` deny, ownership controls,
  no ACL grants.

### Encryption and data protection

- At rest on by default, with a customer-key option that is complete (the
  module tells the caller the key policy it needs, as data).
- In transit: TLS-only listeners and endpoints, minimum TLS policy, no
  plaintext ports opened by default.
- Deletion protection, backups / PITR, versioning on by default for stateful
  resources; final snapshot on destroy.

### Network

- `0.0.0.0/0` or `::/0` ingress; egress wider than the documented need;
  public IPs; `publicly_accessible`; internet-facing load balancers by
  default.
- IMDSv2 required (`http_tokens = "required"`, hop limit 1 unless containers
  need 2).

### Secrets

- Anything secret in state: `random_password`, passwords as plain
  variables, secret values in SSM parameters the module writes, in user data,
  in environment variables, in rendered templates.
- Floor-aware alternatives: write-only arguments need Terraform 1.11 and
  ephemeral resources 1.10, above this repo's 1.9 floor; at 1.9 prefer
  service-managed secrets (`manage_master_user_password`), references to an
  existing Secrets Manager / SSM SecureString, and `sensitive = true` on
  inputs and outputs.
- Outputs exposing secrets without `sensitive = true`; logs that capture them.

### Logging and audit

- The operator can see what happened: access logs, flow logs, execution logs,
  CloudTrail data events where the asset warrants it, with bounded retention
  and encryption. Optional only when the description says what is lost.

### Code that runs with privilege

- Scripts as root (user data, SSM, AWSTOE, entrypoints): injection through
  unvalidated inputs interpolated into shell; `curl | sh`; downloads without
  checksum verification; unpinned packages or images (tag instead of
  digest).
- Lambda code: least privilege per function, no secrets in env, timeouts.

### Supply chain

- Provider constraint has an upper bound; module sources pinned; container
  images by digest; build artifacts reproducible from the repo; no runtime
  fetch from mutable URLs.

## 4. Prove each candidate

For every candidate: the rendered JSON or the quoted line, then the attack in
one sentence: **attacker position → action → impact**. If the exploit needs
something you cannot show offline (an AWS evaluation nuance, a service's
real behaviour), it is "Not checked", with the exact test that would settle
it (e.g. "IAM policy simulator on statement X with context key Y").

Check the module does not already handle it (a validation elsewhere, a
precondition, a `check`, a documented caller responsibility). A
`check` warning is an accepted posture, not a hole, unless the default
leaves it on for everyone.

## 5. Report

1. **Threat model** (the section 1 notes, ten lines at most).
2. **Toolchain**: commands run and their result lines; which renders were produced.
3. **Findings**, most severe first:

   ```
   #N [Critical|High|Medium|Low] [Confirmed] [IAM|KMS|Network|Secrets|Logging|Exec|Supply chain] Title
   Location:  path/file.tf:LINE
   Evidence:  rendered JSON excerpt or quoted code
   Attack:    attacker position -> action -> impact
   Fix:       concrete change; BREAKING if it changes an unchanged caller's plan
   Verify:    the test or render assertion that proves the fix
   ```

4. **Refusals verified**: each README promise tried and whether it held.
5. **Not checked**: what needs AWS, credentials or a real apply, and how to prove it.

Do not edit the module. If asked to fix, fix one finding at a time with a
test (or a render assertion) that fails before and passes after.
