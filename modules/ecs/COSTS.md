# terraform-aws-ecs — what a cluster costs

**Region:** `eu-west-2` — EU (London)
**Currency:** USD, on-demand list price, no Savings Plans or EDP discount
**Pricing date:** Fargate and CloudWatch rates pulled from the **AWS Price List
bulk API** on **2026-11-16** (`AmazonECS` offer published 2026-11-11,
`AmazonCloudWatch` offer published 2026-11-04). Rates marked *not pulled* were
not in those offers.
**Basis:** `terraform-aws-ecs` 3.0.0 (unreleased), module defaults
(`container_insights = "enabled"`, `log_retention_days = 30`, alarms on).
730 hours per month.

> **Verify before quoting externally.** These are list prices on the pricing
> date. Fargate Spot has no fixed rate in the price list: it moves with spare
> capacity, so every Spot figure here is a share of the on-demand figure you
> must confirm on your own bill.

## 1. The shape of the bill

The module creates almost nothing that costs money by itself. The tasks it
runs are the bill; the logs they write are the line that grows.

| Line | Who is billed | Scales with | Bounded by default |
|---|---|---|---|
| Fargate tasks | The workload's account | vCPU and GB per task, per hour running | By `desired_count` / `autoscaling.max` |
| CloudWatch Logs ingestion | Same | GB written by containers and the Service Connect proxy | No: it is what the application writes |
| **CloudWatch Logs storage** | Same | GB kept | **Yes: 30 days. `0` keeps everything forever** |
| Container Insights | Same | Metrics per cluster, service and task; performance log events | Turned off with `container_insights = "disabled"` |
| Alarms | Same | 2-3 per service | $0.10 each per month |
| Managed EBS volumes | Same | GB and IOPS per task volume | Deleted with the task |
| VPC interface endpoints | **The network owner** | Endpoints × AZs, per hour, plus GB processed | Not by this module |

## 2. Fargate tasks

Linux/x86: **$0.04656 per vCPU-hour, $0.00511 per GB-hour.** Linux/ARM
(`cpu_architecture = "ARM64"`): **$0.03725 per vCPU-hour, $0.00409 per GB-hour.**
Ephemeral storage above the included 20 GB: **$0.000129 per GB-hour.**

| `cpu` / `memory` | x86 per hour | x86 per month | ARM per month | One task, a year (x86) |
|---|---:|---:|---:|---:|
| 256 / 512 | 0.25 × 0.04656 + 0.5 × 0.00511 = $0.014195 | $10.36 | $8.29 | $124.35 |
| 512 / 1024 | $0.028390 | $20.72 | $16.58 | $248.70 |
| 1024 / 2048 | $0.056780 | $41.45 | $33.16 | $497.39 |
| 2048 / 4096 | $0.113560 | $82.90 | $66.33 | $994.79 |
| 4096 / 8192 | $0.227120 | $165.80 | $132.66 | $1,989.57 |

ARM is 20% cheaper at every size here ($0.04543 against $0.05678 per hour at
1 vCPU / 2 GB). Ephemeral storage at 200 GB (`ephemeral_storage_gib = 200`)
adds 180 × $0.000129 × 730 = **$16.95 per task-month**, more than a 256/512
task costs.

**What moves the bill, per hour of work:**

1. `autoscaling.min`. Two tasks of 1 vCPU / 2 GB at the floor around the clock
   are $82.90/month; scheduled scaling to `min = 1` from 20:00 to 07:00 on
   weekdays and all weekend (103 of 168 hours, 61%) saves 0.61 × $41.45 = about
   $25/month per service.
2. `cpu_architecture = "ARM64"`, where the image builds for it: 20% of the task line.
3. `capacity = "balanced"` or `"spot_preferred"` for interruptible workloads.
   The saving is the Spot discount on the Spot share; confirm the discount on
   your bill (*not pulled*).
4. Right-sizing `memory`: at 1 vCPU, each GB above 2 adds $3.73/month per task.

## 3. Logs — the line that grows

Ingestion **$0.5985 per GB** (Standard class), storage **$0.0315 per GB-month**.
Storage is billed on the compressed size, so the figures below, which use the
ingested size, are an upper bound.

A cluster writing **5 GB a day** (150 GB a month):

| | Per month | After 12 months | After 36 months | 36-month total |
|---|---:|---:|---:|---:|
| Ingestion | 150 × $0.5985 = $89.78 | $89.78 | $89.78 | $3,231.90 |
| Storage, `log_retention_days = 30` | ~150 GB × $0.0315 = $4.73 | $4.73 | $4.73 | $170.10 |
| Storage, `log_retention_days = 0` | grows 150 GB a month | 1,800 GB = $56.70 | 5,400 GB = $170.10 | 0.0315 × 150 × (1 + … + 36) = $3,146.85 |

With no retention, the monthly storage bill passes the ingestion bill in month
20 (20 × $4.725 = $94.50), and by month 36 storage has cost $3,146.85 against
$3,231.90 ingested, and keeps growing. The `log_retention_is_bounded` check warns at 0. Debug logging is
the usual reason ingestion doubles; the line is per GB, so it is visible within
a day in Cost Explorer under `DataProcessing-Bytes`.

## 4. Signals

| Item | Rate | Typical |
|---|---|---|
| Alarms | $0.10 per alarm-month | 3 per service with Container Insights: $0.30/service/month |
| Container Insights | Billed as custom metrics ($0.30 per metric-month, first 10,000) and as log ingestion of performance events ($0.5985/GB) | Depends on services and tasks; the per-resource metric count is on the CloudWatch pricing page (*not pulled*) |
| EventBridge rules on ECS events | AWS service events to the default bus are not charged for matching | $0 |
| EventBridge Scheduler invocations | *not pulled* | One per schedule run |
| SNS deliveries | The topic owner's | — |

## 5. What the caller's network spends

The tasks need VPC endpoints in subnets without a NAT path
(`output.network_contract`): typically `ecr.api`, `ecr.dkr`, `logs`, plus
`secretsmanager`, `ssm`, `kms` and `ssmmessages` as features are used. Interface
endpoints are billed per endpoint, per AZ, per hour, plus per GB processed, to
the account that owns them (*not pulled*). The S3 gateway endpoint ECR needs is
free. One set of endpoints shared by every cluster in a VPC is the cheap shape.

## 6. Checking the bill

- Cost Explorer, grouped by the `aws:ecs:serviceName` tag (activate it as a
  cost allocation tag; the module turns on ECS managed tags) and by your own
  `required_tag_keys`.
- `verify_commands.capacity` shows running and pending tasks per cluster.
