# keel-insights — what it costs

**Basis:** `keel-insights` 0.1.0 (unreleased), CID templates 0.13.0 and 4.4.21.
**Prices:** from the platform options deck (AWS pricing pages checked 23
November 2026), **not pulled for this document**. **Verify before quoting
externally.**

| Line | Price | Who is billed |
|---|---|---|
| Quick Sight | Authors about $24 a month, readers $3 a month; AWS estimates $100-200 a month for three authors and fifteen readers | This account |
| SPICE | At least 10 GB, the template's prerequisite | This account |
| S3 (export data) | Per GB-month, growing every month with hourly exports | This account |
| Athena | Per TB scanned by dataset refreshes and queries | This account |
| Lambda, Glue crawlers | Small, per run | This account |

**The growing line** is the export data, kept on purpose. The CID template's
bucket rules expire noncurrent versions and abort stale uploads
(data-exports 0.13.0, lines 314-323). No rule expires current objects, and the
module adds none: billing history is evidence, and compressed Parquet is the
cheapest line here.

- **Storage grows linearly.** It is S3 Standard per GB-month, times the months
  kept. Measure it with `verify_commands.export_data_size` after two or three
  months.
- **Queries and SPICE cost more than storage.** They grow with how much
  history the dashboards scan, not with how much is kept.
- **Hourly granularity stays.** The template recommends HOURLY *"unless your
  AWS invoice is more then $50M"*, and changing it needs a purge and backfill.
- **If the measured growth matters,** the next step is S3 Intelligent-Tiering,
  which Athena still reads, not deletion. A lifecycle rule managed outside the
  template replaces the template's own rules and must repeat them.

Order of magnitude for the whole option B, from the deck: under £10k a year in
seats for ten authors and two hundred readers, plus about a person-month to
deploy.
