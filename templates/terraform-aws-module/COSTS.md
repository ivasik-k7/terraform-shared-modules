# What a log group costs

| | |
|---|---|
| Region | eu-west-2 (London) |
| Currency | USD |
| Pricing date | 2026-10-26 |
| Basis | 0.1.0, defaults |

> **Verify before quoting externally.** List prices as known to the author,
> not pulled from the AWS Price List API.

## What is billable

| Line | Unit | Driven by |
|---|---|---|
| **Ingestion** | per GB | what writes to the group; lower in `INFREQUENT_ACCESS` |
| **Storage** | per GB-month, compressed | everything kept, for `retention_days` |
| KMS | per request beyond the free tier | `kms_key_arn` |
| The log group itself | $0 | |

## The line that grows

**Storage, with `retention_days = 0`.** Ingestion is paid once; storage is
paid every month for everything ever written. At 10 GB a month kept forever,
at $0.03 per GB-month:

| Month | Stored | Storage that month |
|---|---|---|
| 1 | 10 GB | $0.30 |
| 12 | 120 GB | $3.60 |
| 36 | 360 GB | $10.80 |

It never levels off. With the default 30 days it stays at about one month of
volume, $0.30 a month here. `log_retention_is_bounded` warns on 0.
