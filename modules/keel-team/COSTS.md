# keel-team — what it costs

**Basis:** `keel-team` 0.1.0 (unreleased), per account and Region. **Currency:**
USD. **Pricing date:** not pulled for this document. **Verify before quoting
externally.**

## What the module spends

| Line | Price | Quantity | Notes |
|---|---|---|---|
| Budgets (limits, platform limits, AI caps) | Free | Any | |
| Budget actions (locks, SCPs) | $0.10 a day each after the first two in the account | One per limit with `action` | About $3 a month each |
| Anomaly monitors and subscriptions | Free | One per limit with `anomaly` | |
| Severity topics, queue, pipes, forwarding rules | Cents a month | Four topics, one queue, four pipes per Region | Pipes bill per request; signals are few |
| Inference profiles | Free | | Model calls are billed as before |
| Burn alarm | CloudWatch metric-math alarm pricing, per metric in the expression | Up to ten metrics, one alarm per Region | |
| Invocation logs | CloudWatch Logs ingestion and storage | One record per model call, metadata only | **The growing line**, bounded by `retention_days` (default 90) |
| Schedules | EventBridge Scheduler invocations and Automation steps | Two a day per schedule per working day | Well inside the free tiers at this volume |
| FinOps role, quota reads | Free | | |

## What the module saves

| Lever | Arithmetic |
|---|---|
| Running hours | Weekdays 08:00-19:00 is 55 of 168 hours. An instance on that schedule runs 33% of the time, so its compute bill falls by about two thirds. Storage is billed as before |
| Sandbox lock | Spend stops growing at the limit instead of at the next bill |
| Burn meter | A runaway agent is caught within the hour, not on the bill |
| Platform limits | An overrun is attributed to a platform and its owner the day it starts |

The invocation log line grows with call volume. At 90 days it plateaus once
the oldest records expire; a longer `retention_days` raises the plateau, not
the slope.
