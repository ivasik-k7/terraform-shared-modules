# keel-signals — what it costs

**Basis:** `keel-signals` 0.1.0 (unreleased), per account and Region.
**Currency:** USD. **Pricing date:** not pulled for this document. **Verify
before quoting externally.**

| Line | Billed per | Volume | Notes |
|---|---|---|---|
| SNS topics | Request and delivery | A few signals a day | Cents a month; e-mail deliveries have a free tier |
| SQS queue | Request | The same signals, plus the pipes' polling | Polling an empty queue is billed too. A long poll every 20 seconds is about 130,000 requests a month per poller, four pipes about 520,000, against SQS's free million. How many pollers a pipe runs is not checked |
| EventBridge Pipes | Request, after filtering | One per signal | Cents a month |
| Default-bus rules to another bus | Event delivered | One per signal | Cross-account and cross-Region delivery is billed as custom events |

Nothing here grows without the signals growing. The volume is the number of
alerts, which the limits set.
