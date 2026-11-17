# terraform-aws-asg-group — what a fleet costs

**Region:** `eu-west-2` — EU (London)
**Currency:** USD, on-demand list price, Linux, shared tenancy, no Savings Plans
or Reserved Instances
**Pricing date:** rates pulled from the **AWS Price List bulk API** on
**2026-11-17**: `AmazonEC2` (published 2026-11-14) for instances, EBS and CPU
credits; `AmazonVPC` for public IPv4; `AmazonCloudWatch` (published 2026-11-04)
for alarms. Rates marked *not pulled* were not in those offers.
**Basis:** `terraform-aws-asg-group` 2.0.0 (unreleased), module defaults
(`t3.medium`, 30 GiB gp3 root, standard CPU credits, alarms on). 730 hours per
month, 8,760 per year.

> **Verify before quoting externally.** These are list prices on the pricing
> date. Spot prices are not in the price list: they move with spare capacity,
> so every Spot figure is a share of the on-demand figure you must confirm on
> your own bill.

## 1. The shape of the bill

The module itself costs almost nothing: two alarms. The instances it launches
are the bill, and `max_size` is its ceiling.

| Line | Who is billed | Scales with | Bounded by default |
|---|---|---|---|
| Instances | The workload's account | Instance type × hours × count | By `max_size` |
| EBS volumes | Same | GB, and IOPS and throughput above gp3's included 3,000 and 125 MiB/s | Deleted with the instance (`delete_on_termination`) |
| **T-family surplus credits** | Same | vCPU-hours above the baseline | **Yes: `cpu_credits = "standard"`. `"unlimited"` has no ceiling** |
| **Retained instances** | Same | Instances whose drain hook abandoned, each billed beside its replacement | **Only `terminate_hook_abandon = "retain"` creates them; nothing bounds how many** |
| Warm pool | Same | Stopped: EBS only. Running: the full instance | By `warm_pool.min_size` and `max_group_prepared_capacity` |
| Public IPv4 | Same | $0.005 per address-hour | Only with `public_ip = "assign"` |
| Alarms | Same | $0.10 per alarm-month | Two |
| Detailed monitoring | Same | Billed as CloudWatch metrics per instance (*not pulled*) | Off by default |
| VPC endpoints for Session Manager | **The network owner** | Endpoints × AZs, per hour, plus GB | Not by this module (*not pulled*) |

## 2. Instances

| Type | Per hour | Per month | One instance, a year |
|---|---:|---:|---:|
| t3.medium (default) | $0.0472 | 0.0472 × 730 = $34.46 | $413.47 |
| t3.large | $0.0944 | $68.91 | $826.94 |
| m7g.large (Graviton) | $0.0944 | $68.91 | $826.94 |
| c7i.large | $0.10605 | $77.42 | $929.00 |
| m7i.large | $0.11655 | $85.08 | $1,020.98 |
| m7i.xlarge | $0.2331 | $170.16 | $2,041.96 |

Graviton (`m7g.large`) is 19% cheaper than `m7i.large` for the same size
($0.0944 against $0.11655). Attribute-based selection with
`cpu_manufacturers = ["amazon-web-services"]` takes it where the image is ARM.

**The ceiling.** The `complete` example's fleet, `max_size = 12` of
`m7i.large` with a 40 GiB root, costs at most
12 × ($85.08 + 40 × $0.0928) = **$1,065.52 per month** on-demand. Spot above the
on-demand base lowers that by the Spot discount on the Spot share (*not pulled*).

## 3. Volumes

gp3 **$0.0928 per GB-month**, IOPS above 3,000 **$0.0058 per IOPS-month**,
throughput above 125 MiB/s **$0.0464 per MiB/s-month**. gp2 is $0.116 per
GB-month, so gp3 (the default) is 20% cheaper per GB.

| Volume | Per instance-month |
|---|---:|
| 30 GiB gp3 root (default) | 30 × $0.0928 = $2.78 |
| 40 GiB gp3 root | $3.71 |
| 100 GiB gp3 with 6,000 IOPS | $9.28 + (6,000 − 3,000) × $0.0058 = $26.68 |
| gp3 at 250 MiB/s | + (250 − 125) × $0.0464 = $5.80 |

## 4. The lines that grow

**Unlimited CPU credits.** Surplus credits are billed at **$0.05 per
vCPU-hour** (T3 and T3a on Linux; $0.04 on T4g). A `t3.medium` (2 vCPUs) held
at 100% CPU above a 20% baseline per vCPU (the baseline is from the EC2
burstable instance documentation, *not pulled*) uses 2 × 0.8 = 1.6 surplus
vCPU-hours an hour: 1.6 × $0.05 × 730 = **$58.40 per month, on a $34.46
instance**. Standard credits (the default) throttle instead.

**Retained instances.** Each one costs its full hourly price, every hour, while
a replacement runs beside it. Ten `m7i.large` instances forgotten after failed
drains are 10 × $85.08 = $850.80 a month. `verify_commands.terminate_retained`
is the way out; the `retained_instances_are_cleaned_up` check warns while
retention is on.

## 5. Signals

| Item | Rate | This module |
|---|---|---|
| Alarms | $0.10 per alarm-month | 2: $0.20 per month |
| Group metrics (`enabled_metrics`) | Free at one-minute granularity | 20 collected by default |
| EventBridge rules on Auto Scaling events | AWS service events to the default bus are not charged for matching | $0 |
| SNS deliveries | The topic owner's | — |

## 6. Checking the bill

- Cost Explorer grouped by your `required_tag_keys` (`CostCenter`, `Owner`):
  instances, volumes and network interfaces carry them from launch.
- `verify_commands.group` shows the live count against `max_size`.
