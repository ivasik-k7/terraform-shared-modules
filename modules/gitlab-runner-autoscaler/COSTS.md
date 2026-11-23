# gitlab-runner-autoscaler — what it costs

**Region:** `eu-west-2` — EU (London), the basis of the sibling modules' cost
documents
**Currency:** USD, on-demand list price, Linux, no Savings Plans
**Pricing date:** rates carried from `modules/asg-group/COSTS.md`,
and `modules/ecs/COSTS.md`, which pulled them from the AWS Price List bulk API
on 2026-11-17. **Not pulled again for this document.**
Rates marked *not pulled* are in none of them.
**Basis:** `gitlab-runner-autoscaler` 0.1.0 (unreleased); manager 0.5 vCPU /
1 GB (the default); job instances `m7i.large` (the default) with a 50 GiB gp3
root (the default). 730 hours per month.

> **Verify before quoting externally.** List prices on the date above, not
> re-checked. Spot is not in the price list, and the eu-west-1 rates differ.

## 1. The shape of the bill

| Line | Who is billed | Scales with | Bounded by default |
|---|---|---|---|
| Job instances | The module's account | Instance-hours: jobs ÷ `capacity_per_instance`, plus idle time | Yes: `max_instances` per pool |
| Instance volumes | Same | GB × hours the instance lives | Deleted with the instance |
| Managers | Same | One Fargate task per enabled pool, all month | One per pool |
| Manager logs | Same | GB written; GB kept | 30 days (`log_retention_days`) |
| Alarms, Container Insights | Same | 7 alarms per pool (4 here, 3 from `modules/ecs`) | Per pool |
| Log metric filters | Same | 2 custom metrics per pool | Per pool |
| Dashboard | Same | One | `monitoring.dashboard` |
| Cache bucket | Same | GB stored; requests | `cache.expiration_days` (14) |
| Collector metrics (optional) | Same | Custom metrics per metric and label set; EMF log ingestion | The `metric_declarations` in `locals.tf` select what is kept |
| Images, tokens, SSH key, job roles | **Whoever makes them** | Repositories, secrets | Outside this module |
| Interface endpoints `ec2`, `autoscaling` (and the others in `network_contract`) | **The network owner** | Endpoints × AZs × hours, plus GB | Not by this module; *not pulled* |

## 2. Unit rates

| Item | Rate |
|---|---|
| Fargate Linux/x86 | $0.04656 per vCPU-hour, $0.00511 per GB-hour |
| `m7i.large` | $0.11655 per hour |
| gp3 | $0.0928 per GB-month |
| CloudWatch Logs | $0.5985 per GB ingested, $0.0315 per GB-month stored |
| CloudWatch alarm | $0.10 per alarm-month |
| CloudWatch custom metric | $0.30 per metric-month (first 10,000) |
| CloudWatch dashboard | $3.00 per month (*not pulled*) |
| S3 Standard | $0.024 per GB-month (*not pulled*) |

Derived:

- **Manager:** 0.5 × $0.04656 + 1 × $0.00511 = $0.02839 per hour;
  × 730 = **$20.72 per pool per month**, whether or not jobs run.
- **Instance-hour:** $0.11655 + 50 GiB × $0.0928 ÷ 730 = $0.11655 + $0.00636 =
  **$0.12291**.

## 3. Ceilings

The most a pool can cost in a month is every instance running all month:

| `max_instances` | Instances | Manager | Ceiling |
|---|---|---|---|
| 5 | 5 × 730 × $0.12291 = $448.62 | $20.72 | $469.34 |
| 10 (default) | 10 × 730 × $0.12291 = $897.24 | $20.72 | $917.96 |
| 20 | 20 × 730 × $0.12291 = $1,794.49 | $20.72 | $1,815.21 |

## 4. A worked month

Two pools as in [examples/complete](examples/complete), on `m7i.large`,
on-demand prices throughout. The job and idle lines are added, not overlapped,
so this is an upper estimate for the assumptions.

| Line | Assumption | Arithmetic | Month |
|---|---|---|---|
| Managers | 2 pools | 2 × $20.72 | $41.44 |
| `docker` idle | 1 instance (4 slots) warm 12 h × 22 working days | 264 h × $0.12291 | $32.45 |
| `docker` jobs | 4,000 jobs × 10 min, 4 per instance | 166.7 h × $0.12291 | $20.49 |
| `build` jobs | 1,000 jobs × (10 min + 2 min boot), one instance each | 200 h × $0.12291 | $24.58 |
| Logs | 2 GB written per manager, 30 days kept | 2 × (2 × $0.5985 + 2 × $0.0315) | $2.52 |
| Alarms | 7 per pool | 14 × $0.10 | $1.40 |
| Metric filters | 2 custom metrics per pool | 4 × $0.30 | $1.20 |
| Dashboard | One | | $3.00 |
| Cache | 50 GB kept (14-day expiry) | 50 × $0.024 | $1.20 |
| **Total** | | | **$128.28** |

With the collector, add its custom metrics: about 40 metric and label sets per
pool at $0.30, so roughly $12 per pool per month, plus the EMF log ingestion at
$0.5985 per GB. That is the line to watch if pools multiply.

Spot on the `build` pool lowers its line by the Spot discount on the share above
`on_demand_base` (*not pulled*). The fixed part is the managers: $20.72 per pool
whether it runs one job or none, so a pool that runs a handful of jobs a month
is cheaper merged into another with the same trust level.

## 5. The line that can grow without anyone noticing

**Instances whose manager is gone.** The alarm
`<name>-<pool>-instances-without-manager` exists for this line. Instances are protected from scale-in and
the group has no scaling policy, so only a manager removes them. A manager that
stops normally deletes its instances (`delete_instances_on_shutdown`), and a
manager that starts deletes any it finds. A manager that **cannot start** (a
bad token, a missing image, a broken endpoint) removes nothing: its instances
bill at up to `max_instances` × $0.12291 per hour until it is fixed. That alarm, the
running-task alarm on the manager service and the ECS event rule (with
`sns_topic_arn`) are what notice it; `verify_commands.<pool>.fleet_instances`
shows what is running.

## 6. What moves the bill, by value per hour of work

| Change | Effect | Effort |
|---|---|---|
| Lower `max_instances` to the real peak | Caps the ceiling in section 3 | Minutes |
| Idle policies only in working hours (`idle_count = 0` otherwise) | Removes warm instances nights and weekends: 264 h → 0 h of the idle line outside them | Minutes |
| Raise `capacity_per_instance` on unprivileged pools | Fewer instance-hours for the same jobs, if jobs fit | Minutes, then watch job times |
| Spot for interruptible pools | The Spot discount on their instance line | Minutes; jobs can fail on reclaim |
| Merge low-traffic pools of the same trust level | $20.72 per merged pool | An hour |
| Graviton (`m7g`) instances | ~19% on instances (per `asg-group` COSTS) | Needs arm64 job images and helper; not supported by this module yet |
