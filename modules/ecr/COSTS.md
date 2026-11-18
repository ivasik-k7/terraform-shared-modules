# terraform-aws-ecr — what a registry costs

**Region:** `eu-west-2` — EU (London)
**Currency:** USD, on-demand list price
**Pricing date:** ECR rates pulled from the **AWS Price List bulk API** on
**2026-11-18** (`AmazonECR` offer published 2026-11-13). The 90-day archive
minimum is from the ECR pricing page on the same day. Rates marked *not
pulled* were not in that offer.
**Basis:** `terraform-aws-ecr` 1.0.0 (unreleased), module defaults (lifecycle
preset: untagged images expire after 14 days, the newest 100 images stay).
Decimal GB.

> **Verify before quoting externally.** These are list prices on the pricing
> date. The image sizes below are assumptions about a typical service; your
> bill is your images.

## 1. The shape of the bill

The module's resources cost nothing by themselves. Storage is the bill, and it
grows with every push unless a lifecycle policy deletes something.

| Line | Who is billed | Scales with | Bounded by default |
|---|---|---|---|
| **Standard storage** | The registry's account | GB of image layers kept, per month | **Yes: the preset keeps the newest 100 images. `enabled = false` or archive-only keeps everything** |
| Archive storage | Same | GB archived, per month, at least 90 days each | By `archive_expire_days` (0: never) |
| Archive restore | Same | GB restored | Per restore |
| Replicas | Same, in each destination | Every replicated GB is stored again there, plus transfer between Regions (*not pulled*) | By the destination's creation template |
| Pull through cache | Same | GB of upstream images cached | By the cache template's lifecycle policy; no template, no bound |
| Enhanced scanning | Same, by Amazon Inspector | Images scanned, and rescans while continuous (*not pulled*) | By the scanning rules' filters |
| KMS | The key's owner | $1 per key-month and per 10,000 requests (*not pulled*) | — |
| Pulls | The puller | Free within a Region to EC2, ECS and Lambda; internet egress at data transfer rates (*not pulled*) | — |

## 2. Storage

| Rate | eu-west-2 |
|---|---:|
| Standard storage | **$0.10 per GB-month** |
| Archive storage | **$0.04 per GB-month**, billed for at least 90 days |
| Archive retrieval | **$0.03 per GB** |

A repository stores each image layer once, so a push adds only the layers that
changed. Assume a service pushing **10 images a day, each adding 50 MB** of new
layers on a 500 MB base: 10 × 50 MB × 30 = 15 GB a month.

| | Per month | After 12 months | After 36 months | 36-month total |
|---|---:|---:|---:|---:|
| No lifecycle policy | grows 15 GB a month | 180 GB = $18.00 | 540 GB = $54.00 | 0.10 × 15 × (1 + … + 36) = $999.00 |
| Preset (newest 100 images) | 100 × 50 MB + 500 MB = 5.5 GB = $0.55 | $0.55 | $0.55 | 36 × $0.55 = $19.80 |

Without a policy the monthly bill passes $10 in month 7 and never stops
growing; the `storage_is_bounded` check warns. Fifty repositories on the
preset are 50 × $0.55 = **$27.50 a month**.

## 3. Archive

Archiving fits images kept for audit that nobody pulls: **200 GB** of release
images cost $20.00 a month in standard storage and 200 × $0.04 = **$8.00** in
archive, a 60% saving. Restoring 10 GB for an investigation costs 10 × $0.03 =
$0.30. Deleting an image before it has been archived 90 days is still billed
for 90 days: 100 GB archived and deleted after 30 days costs 100 × $0.04 × 3 =
$12.00, not $4.00, which is why `archive_expire_days` is at least 90.

## 4. What moves the bill, per hour of work

1. **A lifecycle policy on every repository**, including the ones ECR creates:
   give the pull through cache and replication prefixes a creation template
   with a lifecycle policy (`ecr_created_repositories_follow_a_template` warns
   without one). A cache of busy upstream images grows like section 2's first
   row.
2. **`keep_last` sized to rollback needs, not to history.** 100 images at 50 MB
   is 5 GB; 1,000 is 50 GB = $5.00 a month per repository.
3. **Archive instead of keep** for audit retention (section 3).
4. **Replicate only what a DR Region needs** (`repository_prefixes`): every
   replicated GB is billed again in each destination.

## 5. Checking the bill

- Cost Explorer, service Amazon EC2 Container Registry (ECR), grouped by your
  `required_tag_keys`: repositories carry the module's tags, and repositories
  created from templates get them through `resource_tags`.
- `verify_commands.images` lists sizes and last pull times per repository;
  `verify_commands.lifecycle_preview` shows what a policy will delete.
