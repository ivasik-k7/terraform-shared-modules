---
inclusion: fileMatch
fileMatchPattern: "**/*.md"
---

# Documentation conventions

Modules are consumed from the HCP Terraform **private registry**, published
tag-based from this monorepo (tag prefix `<module>-`, e.g. `aurora-v2.0.0`).
Readers are on the registry page or in an HCP Terraform workspace, not on a
laptop with the repo checked out. Write for that reader.

Each document answers a different question:

| File | Question | Where it is read |
|---|---|---|
| `README.md` | What is this, how do I call it, what does it refuse, what are its limits | **Registry page** and GitHub |
| `examples/<name>/README.md` | What does this example show, and what fails in it | **Registry examples list** and GitHub |
| `COSTS.md` | What does it cost, which line has no ceiling, what moves the bill | GitHub |
| `CHANGELOG.md` | What changed in each version, and which changes are breaking | GitHub |
| `docs/UPGRADE-<major>.0.md` | How does an existing deployment move to this major | GitHub |
| `ROLLOUT.md` | How does a fleet adopt the artifact, and how do I get it back | GitHub |

## What the registry changes

- **It generates the Inputs, Outputs and Resources tabs from the code.** So a
  README does not carry a hand-written table of every variable: it drifts, and
  the registry already shows the real one. Carry instead a short "most-used
  inputs" table (fifteen rows at most) and the **contract outputs** — the ones
  another team acts on — with what each is for. Descriptions in `variables.tf`
  and `outputs.tf` are the reference documentation; write them to be read there.
- **Links are relative, always.** Never write the repository's URL, owner or
  name into a document: no absolute GitHub links, no issue-tracker links. Link
  to files with paths relative to the document (`COSTS.md`,
  `examples/basic`, `../route53-resolver`). Relative links 404 on the
  registry page; that is the accepted cost.
- **It shows a usage block from the README.** Lead with one: the registry
  `source`, `version = "~> X.0"`, and only the required inputs plus the few
  without which the module refuses to plan.

## README rules

- **Lead with the trap, not the feature list.** The valuable part of these
  modules is the failures they refuse; put them right after usage and
  requirements.
- **Assume HCP Terraform.** Changes are reviewed as speculative plans on pull
  requests and applied by a workspace; outputs reach other teams through
  re-exported root outputs, `tfe_outputs` and run triggers; verification runs
  from CloudShell. Do not tell a reader to run `terraform output` on a laptop.
- **State the requirements** — Terraform and provider ranges, and what a
  workspace must change to meet them (Terraform version setting, lock file).
- **Tables over paragraphs** for anything comparative.
- **State the limits.** Every README carries a limits section that includes
  what has never been exercised against real AWS. Never quietly drop a caveat
  that is still true.
- **Versioning and support section**: what counts as breaking, the deprecation
  window, the supported ranges, and links to the changelog and upgrade guide.
- No self-congratulation, no audit theatre, no "this used to be broken"
  framing. A README reader wants the current state and the reasoning. History
  belongs in `CHANGELOG.md`.
- Keep anchors honest; prefer few of them.

## Changelog and upgrade guides

- `CHANGELOG.md` per module, [Keep a Changelog](https://keepachangelog.com)
  format, newest first, an `unreleased` heading until the tag exists. Mark every
  change that alters an unchanged caller's plan **BREAKING**: removed or renamed
  inputs and outputs, new required inputs, **changed defaults**, changes that
  turn an update into a replacement, address changes, raised version floors.
- A major release that existing deployments must cross gets
  `docs/UPGRADE-<major>.0.md`: every old input mapped to its new one or to
  "removed, because…", the `moved` blocks, the inputs that must match what is
  running, what still changes on the first plan, and the steps in HCP Terraform
  (speculative plan on a pull request, what to search the plan for). Kept apart
  from the README because most registry readers are starting fresh and should
  not wade through it.
- `moved` blocks are never deleted, so a workspace can skip versions; say so.

## Cost documents specifically

- Header block with region, currency, **pricing date**, and the analysis basis
  (which version or commit, which defaults).
- A visible "verify before quoting externally" note if the prices were not
  pulled from the Price List API in that session. Never imply a live pull.
- **Compute every number**, keep the tables internally consistent, and show the
  arithmetic basis (unit price × quantity) so a reader can re-derive it.
- Project far enough out that the dominant line is visible. A retention cost
  that plateaus in year two is invisible in a twelve-month table, and a review
  run at month twelve will reach the wrong conclusion.
- Separate what the module spends from what the *caller's* network or fleet
  spends because of it, and name who is billed.
- Recommendations ordered by dollars per hour of work, not by tidiness.
