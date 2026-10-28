# terraform-aws-s3 — what a bucket costs

| | |
|---|---|
| Region | eu-west-2 (London) |
| Currency | USD |
| Pricing date | 2026-10-28 |
| Basis | s3 0.1.0, defaults unless stated |

> **Verify before quoting externally.** Rates are from the machine-readable
> file behind the S3 pricing page (published 2026-10-15), read in this
> session, not from the Price List API.

## 1. What is billable

| Line | Unit | Driven by |
|---|---|---|
| **Storage** | per GB-month, by class | every current **and noncurrent** version |
| **Requests** | per 1,000 | PUT/COPY/POST/LIST at one rate, GET and the rest at another |
| Lifecycle transitions | per 1,000 objects moved | `lifecycle_rules` transitions; small objects are skipped by default |
| Early deletion | the rest of the minimum duration | moving out of GLACIER_IR/GLACIER before 90 days, DEEP_ARCHIVE before 180 |
| KMS | per request | `kms_key_arn`; an S3 Bucket Key cuts it by up to 99% (not with DSSE) |
| Replication | storage at the destination, inter-region transfer, RTC per GB | `replication` |
| Request metrics | per metric-month | `request_metrics` |
| Inventory | per million objects listed | `inventory` |
| Server access logs | the log bucket's storage | `access_logging` |

## 2. Rates used (London)

| Item | Rate |
|---|---|
| S3 Standard, first 50 TB | $0.024 per GB-month |
| S3 Standard-IA | $0.0131 per GB-month |
| S3 Glacier Instant Retrieval | $0.005 per GB-month |
| S3 Glacier Flexible Retrieval | $0.00405 per GB-month |
| PUT, COPY, POST, LIST | $0.0053 per 1,000 |
| GET and others | $0.00042 per 1,000 |

## 3. The line that grows: noncurrent versions

Versioning keeps every overwritten and deleted object, billed like the
current one, and a listing does not show them. A bucket of 1 TB whose
content is rewritten once a month gains 1 TB of noncurrent versions a month:

| Month | Noncurrent kept forever | With the default 90-day expiry |
|---|---|---|
| 3 | 3 TB, $73.73 | 3 TB, $73.73 |
| 12 | 12 TB, $294.91 | 3 TB, $73.73 |
| 24 | 24 TB, $589.82 | 3 TB, $73.73 |

(1 TB = 1,024 GB at $0.024.) Without expiry it never stops; with the
default it levels at about three months of rewrites.
`old_versions_expire` warns when nothing expires them.

The second silent line is **incomplete multipart uploads**: their parts are
billed and invisible in listings. The default rule aborts them after 7 days.

## 4. Choosing a class

Transitions pay off only for data that stays long enough: 1 TB in Standard
is $24.58 a month; in Glacier Instant Retrieval $5.12, but 90 days are billed
whatever happens. Move data by age (`lifecycle_rules`) when you know its
pattern, Intelligent-Tiering when you do not.
