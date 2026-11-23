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

**The growing line** is the export data: hourly granularity and resource IDs
multiply rows. Daily granularity and a lifecycle rule on old billing periods
bound it.

Order of magnitude for the whole option B, from the deck: under £10k a year in
seats for ten authors and two hundred readers, plus about a person-month to
deploy.
