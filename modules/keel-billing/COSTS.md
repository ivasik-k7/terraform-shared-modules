# keel-billing — what it costs

**Basis:** `keel-billing` 0.1.0 (unreleased). **Prices:** from AWS pricing
pages as checked for the platform options deck on 23 November 2026, **not
pulled for this document**. **Verify before quoting externally.**

| Line | Price | Bounded by |
|---|---|---|
| Cost categories, allocation tags | Free | |
| Cost Optimization Hub, Compute Optimizer (default tier) | Free | |
| Cost Anomaly Detection, monitors and subscriptions | Free | |
| Limits and commitment targets (budgets) | Free | |
| Budget actions (`action` on a limit) | $0.10 a day each after the first two in the account | The number of limits with an action |
| Billing views, RAM shares | Free | |
| AWS FinOps Agent | Preview; price not published at the pricing date | **Not checked**; read the agent's pricing before enabling it beyond a pilot |
| Severity topics, queue, pipes, forwarding (`keel-signals`) | Cents a month at alert volumes | Alert volume |
| Anomaly alert topic | SNS publishes and e-mail deliveries | Anomaly count |
| Cost Explorer API | $0.01 a request | This module makes none at run time |
| Data exports (CUR 2.0, FOCUS, COH) | S3 storage in the destination account | `keel-insights`' bucket lifecycle |

The line that grows without anyone noticing is in the destination account:
hourly CUR 2.0 and FOCUS exports with resource IDs accumulate every month
(`keel-insights`).
