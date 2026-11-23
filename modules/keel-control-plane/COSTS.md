# keel-control-plane — what it costs

**Basis:** `keel-control-plane` 0.1.0 (unreleased). **Prices:** not pulled for
this document. **Verify before quoting externally.**

| Line | Scales with | Order of magnitude |
|---|---|---|
| EventBridge custom bus | Events put, per million | Signals are counted in thousands a month: cents |
| EventBridge archive | GB archived and stored | Kilobytes per signal |
| SNS | Publishes and deliveries | Cents |
| SQS dead-letter queue | Messages | Normally empty |
| Data Firehose | GB ingested | Kilobytes per signal, buffered five minutes |
| S3 evidence | GB-months for `retention_days` | A few MB a year at alert volumes |
| CloudWatch | Two alarms, a log group | Under a dollar a month |

**The growing line** is the evidence bucket, by design: it keeps everything
for `retention_days` and deletes it after. At alert volumes it stays small.
