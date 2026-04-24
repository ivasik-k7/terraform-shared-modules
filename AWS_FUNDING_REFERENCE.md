# AWS Funding Programs — Meeting Reference

> A full-picture cheat sheet for AWS commercial and migration funding: what each program is, when it applies, who signs, and how the pieces stack

---

## 1. The Landscape at a Glance

AWS funding splits into **four buckets**. Most real engagements combine two or three of them.

| Bucket                   | Purpose                                    | Typical Vehicles                                          |
| ------------------------ | ------------------------------------------ | --------------------------------------------------------- |
| **Commercial / pricing** | Reduce list-price spend on committed usage | EDP, PPA, Savings Plans, RIs                              |
| **Migration**            | Fund the _cost of moving_ workloads to AWS | MAP 2.0, MAP Lite, MAP for Windows, OLA, MRA              |
| **Innovation / build**   | De-risk new workloads or modernization     | PIF, POC Credits, Build, ISV Accelerate, Well-Architected |
| **Partner-led**          | Delivered via AWS Partner (e.g. DataArt)   | MDF, OIP, PDF, Partner Originated funding                 |

Rule of thumb: **Commercial programs lower the price of what you _will_ spend. Migration/Innovation programs pay you back for what you _do_ spend during a defined period.**

---

## 2. Commercial & Pricing Agreements

### 2.1 EDP — Enterprise Discount Program

- **What**: Multi-year committed spend agreement (typically 1–5 years) in exchange for a discount on all AWS usage.
- **Minimum**: Historically $1M+/year committed; thresholds vary by region/segment.
- **Discount shape**: Tiered — the more committed, the deeper the %.
- **Covers**: Nearly all AWS services at list price; some marketplace spend counts partially.
- **Watch-outs**:
  - Unused commit is **lost** at term end (use-it-or-lose-it).
  - Shortfall = billed to make up the gap.
  - True-ups are negotiated, not automatic.
- **Signature authority**: **Pillar / C-level** only. Director / Sr Manager (C−3) **cannot** submit.

### 2.2 PPA — Private Pricing Agreement _(successor/umbrella for EDP-style deals)_

- **What**: AWS's modern custom-pricing framework, replacing/wrapping older EDP constructs. Single negotiated agreement covering discounts, custom terms, service-specific pricing, and sometimes marketplace.
- **Why it matters**: If someone says "PPA" in 2026, they usually mean "our enterprise deal with AWS" — more flexible than the classic EDP.
- **Scope options**: All-services discount, service-specific (e.g. S3, data transfer), hybrid.
- **Negotiation levers**: commit $, term length, ramp schedule, included services, marketplace inclusion.
- **Stack with**: MAP credits, PIF, POC credits — all of those _offset_ PPA-committed spend.

### 2.3 Savings Plans & Reserved Instances (RIs)

- **Savings Plans**: Commit to $/hour of compute usage for 1 or 3 years → up to ~72% off.
  - _Compute SP_: flexible across EC2/Fargate/Lambda.
  - _EC2 Instance SP_: deeper discount, locked to family+region.
  - _SageMaker SP_: ML-specific.
- **RIs**: Older construct; still relevant for RDS, ElastiCache, Redshift, OpenSearch.
- **Not "funding"** strictly — but they're the first optimization lever before/after migration credits land.

---

## 3. Migration Programs

### 3.1 MAP 2.0 — Migration Acceleration Program

The flagship migration funding vehicle.

- **What**: AWS funds a portion of migration costs (partner fees + AWS consumption) as **credits** against your bill.
- **Structure — three phases**:
  1. **Assess** — MRA (see below). Produces business case & TCO.
  2. **Mobilize** — Landing zone, CoE, pilot workloads. Funded at a lower tier.
  3. **Migrate & Modernize** — Bulk of credits here; tied to actual migrated workload ARR on AWS.
- **Credit math (typical)**: ~15–25% of projected AWS ARR for migrated workloads, delivered as credits over ~2 years.
- **Eligibility gates**:
  - Qualified partner engagement (e.g. DataArt as AWS Partner).
  - Agreed migration scope + workload inventory.
  - **FinOps tagging in place** — Environment, Project, Team, CostCenter.
    - _Without tags, credits cannot be validated against the claimed workloads._
  - Cost-center mapping signed off.
- **Common failure mode**: Teams migrate first, tag later → credits get clawed back or reduced.

### 3.2 MAP Lite

- Same shape as MAP, lower thresholds, less paperwork.
- For smaller workloads (~$250K–$1M ARR).
- Fewer phases; often Assess + Migrate only.

### 3.3 MAP for Windows

- Specifically for Windows Server / SQL Server workloads.
- Higher funding % because AWS wants these off on-prem / off-Azure.
- Requires EOL or licensing-driven rationale typically.

### 3.4 MRA — Migration Readiness Assessment

- **Not funding itself** — a prerequisite artifact.
- Partner-led workshop (1–2 weeks) assessing 7 perspectives: Business, People, Governance, Platform, Security, Operations, Ops-Experience.
- Output: readiness score + gap list + phased plan.
- **Why it matters for funding**: MAP Mobilize+Migrate credits usually gated on MRA completion.

### 3.5 OLA — Optimization & Licensing Assessment

- Partner/AWS inventory of current on-prem compute + licenses (VMware, Windows, SQL, Oracle).
- Output: right-sized target architecture + license optimization + TCO.
- Often a **precondition** for MAP for Windows and for some EDP/PPA concessions.
- Can itself be **funded** via small AWS credits to the partner.

---

## 4. Innovation & Build Programs

### 4.1 POC Credits — Proof of Concept

- **What**: Small AWS credits ($5K–$50K typical) to run a time-boxed technical POC.
- **Gate**: Business case + defined success criteria + exit decision date.
- **Good for**: Validating a new service (Bedrock, SageMaker, Aurora Limitless) before production commit.

### 4.2 PIF — Partner Innovation Funding _(sometimes: Partner Investment Fund)_

- **What**: Partner-led, outcome-based funding where the AWS partner proposes an innovation engagement and AWS co-invests.
- **Shape**: Milestone-based cash or credits to the partner, partially flowing to the customer as discounted delivery.
- **Scope**: Modernization, GenAI, analytics, industry solutions.
- **Submission**: Through the partner (DataArt) → AWS Partner team.
- **Stacks with**: MAP (for the "Modernize" phase of MAP 2.0).

### 4.3 Build

- AWS's umbrella term for various "help you build a new workload on AWS" credits — usually small, tactical.
- Often packaged as Well-Architected Review remediation credits ($5K per completed WAR with remediations).

### 4.4 Well-Architected Review (WAR) credits

- Run a WAR (6 pillars), close a minimum # of high-risk issues → receive $5K AWS credits.
- Repeat per workload. Soft cap usually negotiated per account.

### 4.5 ISV Accelerate / SaaS Factory

- For ISVs.
- Co-sell + credits for SaaS transformation.

---

## 5. Partner-Led Funding (Flows via DataArt)

| Program                                 | Who Benefits       | Purpose                                                |
| --------------------------------------- | ------------------ | ------------------------------------------------------ |
| **MDF** — Marketing Development Funds   | Partner            | Joint marketing / events                               |
| **PDF** — Proposal Development Funds    | Partner            | Funds pre-sales effort on large deals                  |
| **OIP** — Opportunity Incentive Program | Partner            | Cash rebate to partner for closed/won AWS revenue      |
| **Partner Originated funding**          | Partner → Customer | Customer gets discounted delivery from partner rebates |

Customer doesn't submit these — the partner does. But they shape how the partner prices the engagement.

---

## 6. FinOps Prerequisites (NON-NEGOTIABLE)

No AWS funding claim survives validation without these:

| Tag           | Purpose                     | Enforcement                        |
| ------------- | --------------------------- | ---------------------------------- |
| `Environment` | dev / staging / prod        | Required on all billable resources |
| `Project`     | Maps to business initiative | Must match claim submission        |
| `Team`        | Owning squad / pillar       | For chargeback                     |
| `CostCenter`  | Finance ledger mapping      | Reconciles AWS → GL                |

**Additional requirements**:

- Cost-center → AWS account mapping signed off by Finance.
- AWS Organizations + SCPs in place for tag enforcement.
- CUR (Cost and Usage Report) landing in S3, ideally with CUR 2.0 schema.
- Tag policies enforced at OU level, not just account.

**If tags are missing** → claim is partially or fully rejected, and previously-granted credits can be clawed back at audit.

---

## 7. Decision Matrix — Which Program When?

| Situation                                     | Primary Program                | Stack with                 |
| --------------------------------------------- | ------------------------------ | -------------------------- |
| "We're moving N workloads off on-prem to AWS" | **MAP 2.0**                    | PPA, OLA, MRA              |
| "Mostly Windows/SQL workloads migrating"      | **MAP for Windows**            | OLA (mandatory)            |
| "Smaller migration, < $1M ARR"                | **MAP Lite**                   | —                          |
| "Want to test if Service X works for us"      | **POC Credits**                | —                          |
| "Modernizing already-on-AWS workload"         | **PIF**                        | MAP Modernize phase, Build |
| "Want discount on all future AWS spend"       | **PPA** (or EDP)               | Savings Plans              |
| "Need licensing clarity before we migrate"    | **OLA**                        | Precursor to MAP           |
| "Want to know if we're ready at all"          | **MRA**                        | Precursor to everything    |
| "Continuous workload optimization"            | **WAR credits**, Savings Plans | —                          |

---

## 8. Stacking — How Programs Combine

A well-run enterprise migration typically runs **3–4 programs in parallel**:

```
Year 0:  MRA → OLA → PPA signed
          │
Year 1:  MAP 2.0 (Mobilize)     ← credits
          + POC credits (new services)
          + Savings Plans (as steady state emerges)
          │
Year 2:  MAP 2.0 (Migrate & Modernize)  ← bulk credits
          + PIF (modernization work)
          + WAR credits per workload
          │
Year 3+: PPA renewal / true-up
          + ongoing Savings Plans / RIs
          + OIP rebates to partner
```

**Interaction rules**:

- MAP credits **offset PPA-committed spend** — they count toward your commit.
- PIF credits usually also count toward PPA commit (confirm per agreement).
- Savings Plans apply to whatever you actually pay — credits reduce the base first.

---

## 9. Typical Timeline (Enterprise Migration)

| Month | Activity                             | Funding Touchpoint                   |
| ----- | ------------------------------------ | ------------------------------------ |
| 0     | Discovery, stakeholder alignment     | —                                    |
| 1–2   | MRA + OLA workshops                  | MRA/OLA may be partner-funded        |
| 2–3   | Business case, TCO, scope sign-off   | Pillar-level review                  |
| 3     | PPA negotiation kicks off            | Commercial team + pillar             |
| 3–4   | MAP Mobilize submission              | **C-Level −3 prep → Pillar submit**  |
| 4–6   | Landing zone, FinOps tagging rollout | Tagging = gate for all future claims |
| 6+    | Wave-based migration                 | MAP Migrate credits per wave         |
| 12+   | Modernization waves                  | PIF engagements                      |
| 18–24 | True-up / reconciliation             | CUR vs. claims audit                 |

---

## 10. Red Flags to Raise in the Meeting

1. **"Let's claim after we migrate"** — No. Tagging and claim submission must precede or accompany migration waves.
2. **"My director will sign the MAP form"** — No. Pillar-level only.
3. **"We'll tag in a later sprint"** — No. Tags are the validation key.
4. **"We'll use the POC credits for production"** — Scope mismatch → claim rejected.
5. **"Can we retro-apply MAP to already-migrated workloads?"** — Extremely limited; AWS usually won't.
6. **"PPA and MAP are separate pots"** — They're intertwined; MAP credits consume PPA commit.
7. **Unused EDP/PPA commit at year-end** — Lost money. Plan ramp carefully.

---

## 11. Glossary

| Term    | Meaning                                                                   |
| ------- | ------------------------------------------------------------------------- |
| **ARR** | Annual Recurring Revenue (AWS's term for annualized run-rate consumption) |
| **CoE** | Cloud Center of Excellence                                                |
| **CUR** | Cost and Usage Report                                                     |
| **EDP** | Enterprise Discount Program (older name / subset of PPA)                  |
| **ISV** | Independent Software Vendor                                               |
| **MAP** | Migration Acceleration Program                                            |
| **MDF** | Marketing Development Funds                                               |
| **MRA** | Migration Readiness Assessment                                            |
| **OIP** | Opportunity Incentive Program (partner rebate)                            |
| **OLA** | Optimization & Licensing Assessment                                       |
| **PDF** | Proposal Development Funds                                                |
| **PIF** | Partner Innovation Funding                                                |
| **POC** | Proof of Concept                                                          |
| **PPA** | Private Pricing Agreement                                                 |
| **RI**  | Reserved Instance                                                         |
| **SCP** | Service Control Policy (AWS Orgs)                                         |
| **SP**  | Savings Plan                                                              |
| **TCO** | Total Cost of Ownership                                                   |
| **WAR** | Well-Architected Review                                                   |

---

_Last updated: 2026-04-23. Numbers (discount %, thresholds, credit ratios) are indicative — always confirm current values with the AWS account team before committing in any document._
