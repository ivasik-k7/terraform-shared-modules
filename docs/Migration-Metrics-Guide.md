# Migration Metrics — Database & Compute

Notes on what to gather from the current estate so we can size AWS and make the calls — Oracle vs Postgres on the data side, right-sizing on the app side. Two parts, database and compute. The rule throughout is the same: work from what's actually used, not what was provisioned.

---

## Database

### Why

This is where most of the cost and the one big decision sit. CPU, memory, data size and IO set the instance, the storage and the IOPS, so they have to be measured rather than guessed — and what was provisioned years ago is usually well above what the database really uses, so we work from the actual peak.

The decision is whether to stay on Oracle at all. The licence and annual support is the recurring bill a move to Aurora would shed, but that move is only clean if the database isn't leaning on Enterprise-only options — Partitioning, TDE, RAC and the like keep you on EE and BYOL. The object and PL/SQL counts, and the SCT report, tell us how much rewriting it would take.

A few things shape the target rather than the price. RAC vs Data Guard and the RPO/RTO decide whether it's plain RDS/Aurora Multi-AZ or something heavier (Database@AWS, RAC-on-EC2), and regulated data pins the region and the encryption story up front. Storage here never gets purged, so it only grows — we forecast a couple of years out before committing to anything reserved.

### Where to obtain

| Need | Source |
|---|---|
| CPU, memory, IOPS, sessions, redo, top SQL | **AWR report** over a peak window _(needs Diagnostics Pack; else Statspack, or OS tools + `v$` views)_ |
| Licensed options/packs actually in use | `dba_feature_usage_statistics` — one query, the licence-exposure list (run on prod) |
| Oracle→PostgreSQL conversion effort | **AWS SCT** assessment report (point it at a non-prod copy) |
| Edition, version, licences owned, support | Procurement / the Oracle contract (CSI, ULA, processor count) |
| Size, growth, schema object counts | `dba_segments` (size split), `dba_objects` (counts), archive-log history (growth) |
| Host CPU/RAM, SGA/PGA | `v$osstat`, `v$sga`, `v$pgastat`, init parameters / the DBA |
| HA topology, RPO/RTO, backup | DBA — RAC node count, Data Guard standbys, RMAN retention & size |
| Growth trend & seasonality (12–24m) | AWR history / monitoring history + the product/business volume forecast |

Three things get you most of this in one go, so ask the DBA for them first: an AWR report, the `dba_feature_usage_statistics` query, and an AWS SCT assessment. Take the AWR over a real window — at least a month with a month-end in it, ideally a quarter, the same window we use for the apps so the two line up.

### What to capture

Capture the same set for each database. Filled in below for `SLEND_PROD` as a worked example.

```text
DB: SLEND_PROD

Commercial
  - Oracle 19c Enterprise Edition (19.21, EE)
  - 8 Processor licences (perpetual, CSI active)
  - Support ~22%/yr (~$84k) — the line a Postgres move would remove

Engine / migration facts
  - Charset AL32UTF8 (national AL16UTF16), 8k block
  - Server timezone Europe/London; date-heavy schema

Packs / options in use  (from dba_feature_usage_statistics)
  - On:  Partitioning, Advanced Security/TDE, Diagnostics+Tuning
  - Off: Advanced Compression, RAC, Spatial, GoldenGate
  - EE-only features in use -> no clean SE2/Aurora drop without conversion work

Compute
  - Host 16 cores / 2 sockets, hyperthreading on (32 vCPU)
  - CPU 28% avg, 71% peak (host busy, peak day)
  - Memory 256 GB host, SGA 64 GB, PGA 16 GB

Workload  (AWR load profile)
  - ~140 tx/sec avg, ~520 peak; read/write 80/20
  - Nightly batch 02:00-04:00 (DBMS_SCHEDULER) — peak redo here

Storage
  - Used 1,820 GB (data 1,310 / index 410 / LOB 70 / temp 18 / undo 12)
  - Allocated 2,400 GB
  - Redo ~45 GB/day, archive ~50 GB/day

IO  (peak, AWR / IOStat)
  - Read 3,200 IOPS, write 1,100 IOPS, ~180 MB/s

Concurrency / HA
  - PROCESSES 1,500; peak sessions 640; AAS 4.2
  - Data Guard, 1 physical standby (no RAC)
  - RMAN backup, 14-day retention ~1.6 TB; RPO 5m / RTO 30m

Growth & trends
  - Storage +~20 GB/mo, roughly linear over 18m (1.4 -> 1.8 TB)
  - 7-year regulatory hold, no purge -> only grows
  - Fastest growers: LOAN_EVENT +9 GB/mo, QUOTE_HISTORY +5 GB/mo
  - Transactions +18% YoY (tracks loan applications)
  - Peak sessions 480 -> 640 over 12m (~13%/yr)
  - CPU peak 58% -> 71% over 12m (headroom shrinking)
  - ~2.5x spike in the last 3 business days of each month
  - Product plans ~2x volume within 24 months

Conversion complexity  (dba_objects, app schemas)
  - PL/SQL 180 packages (~95k LOC), 240 triggers, 12 materialized views
  - 9 DBMS_SCHEDULER jobs, 310 sequences, a few proprietary types (SDO_*)
  - SCT: ~78% auto-convertible, rest manual (attach the report)
```

---

## Compute

### Why

For the apps this is mostly a sizing exercise. Add up the memory actually used across every instance and that's the cluster we need on AWS — and these services are nearly always memory-bound, a couple of percent CPU against 30–50% memory, so we size on memory and the CPU comes along for free. The gap between the peak and what's allocated is the headroom we'd reclaim. Keep prod and non-prod on separate cards: non-prod can be parked out of hours, so it sizes to a smaller, cheaper total.

Past raw size, what each app depends on — database, queues, cache, outside calls — tells us both how hard the lift is and what managed services we'd stand up beside it (Amazon MQ, ElastiCache, RDS, and so on). Restarts and OOM kills are a tell-tale for memory set too low; p99 latency and error rate are the baseline we mustn't make worse during cut-over. Criticality and tier set the HA design and the order we move things in. And, as with the database, the load follows the business — so we size to where it's going, not just where it is today.

### Where to obtain (universal, on-prem)

| Need | Source (any of) |
|---|---|
| Allocation & instance count | Platform: **PCF** App Manager / `cf app` · **Kubernetes** `kubectl` · **VMs** hypervisor inventory (vSphere / Hyper-V) |
| CPU / memory / disk used — avg & peak (30d) | Monitoring: Prometheus/Grafana, Datadog, Dynatrace, AppDynamics, CloudWatch agent · platform metrics (PCF Metrics, `kubectl top`) · OS tools (`sar`, `vmstat`, `top`, Windows PerfMon) |
| Throughput / latency (p50,p99) / error rate | Gateway or LB (TYK, F5, NGINX, HAProxy, ALB logs) · APM · app metrics (Spring Boot Actuator / Micrometer) |
| Restarts / OOM kills | Platform events (`cf events`, `kubectl describe`) · OS logs (`dmesg`, OOM killer) · monitoring |
| Dependencies (DB, messaging, cache, external) | App config / bindings (`cf env` VCAP_SERVICES, k8s config/secrets) · code review · confirm with the team |
| Business (criticality/tier/owner) & growth | Service catalogue / app owner + product forecast |
| Backing services (queues, cache, config) | Platform service brokers (`cf services`, k8s operators) — each needs an AWS equivalent |
| Platform footprint (for the landing zone) | App/instance count, total used memory, worker/cell count & size, foundations / namespaces — from the platform team |

Most of this comes out of one metrics export over the window (App Manager, PCF Metrics or Grafana) for CPU/memory/disk/instances, with the gateway giving throughput, latency and error rate, and `cf app`/`cf env` giving the allocation and bindings; business and growth come from the owner. Use the same window as the database — a month with a month-end, ideally a quarter — so we catch the real peak rather than a quiet week. If there's no long-term store, scrape Actuator and grab a few snapshots at peak.

### What to capture

One card per application, prod and non-prod kept separate. Filled in below for `nbp-application-mgmt-ms` (prod) as a worked example.

```text
APP: nbp-application-mgmt-ms  (prod)

Business
  - Criticality Medium, Tier-2, owner Lending Platform

Runtime
  - PCF; Java 17 / Spring Boot; 2 instances

Resource utilisation (30d)
  - Allocated 2 GB mem, 1 GB disk
  - CPU 1.67% avg, ~5% peak
  - Memory 725 MB avg (35%), 922 MB peak (45%)
  - Disk 324 MB avg (32%), 359 MB peak (35%)

Traffic & performance
  - 2.03 req/min avg, ~6 peak
  - Latency p50 19 ms, p99 50 ms
  - Error rate < 0.1%

Reliability
  - 0 restarts, 0 OOM kills (30d)

Dependencies
  - Database SLEND_PROD; no messaging; no cache; 2 external services

Growth & outlook
  - Requests +18% YoY; ~2x load within 24 months
  - Substantial headroom at current utilisation

Migration assessment
  - (left blank — we fill this in the migration review: target runtime, task size, disposition)
```

You can read a fair bit off that one card. It's barely touching its CPU and sitting under half its memory, so it's over-provisioned — an easy rightsizing win. The dependencies are simple: one database, no queue or cache, so the lift is straightforward. It is growing though (+18% a year, expected to roughly double), so we'd size the target to that rather than to the 2 GB it has today.
