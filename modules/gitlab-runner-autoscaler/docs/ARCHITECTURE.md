# Architecture and rollout plan

The target: autoscaling GitLab CI runners in a private AWS network with no
internet egress, where every job runs in Docker on an EC2 instance that exists
only while there is work, caches survive the instance, jobs that must reach AWS
do so through roles you choose, and every failure that matters raises an alarm.

This document is the plan to follow from an empty account to a pipeline running
green, and the operations after that. Facts it relies on are numbered in
[RESEARCH.md](RESEARCH.md); the ones marked **Unverified** there are listed in
[section 10](#10-what-to-prove-before-production), as the first thing to check
in a real account.

## 1. The shape

```
         GitLab (HTTPS, private)                         Registry mirror (HTTPS)
            ▲              ▲                                  ▲
 poll jobs, │              │ git clone, artifacts             │ Docker Hub images
 send logs  │              │                                  │
┌───────────┼──────────────┼──────────────────────────────────┼─────────────────┐
│ VPC, private subnets in 2+ AZs                              │                 │
│           │              │                                  │                 │
│ ECS cluster (Fargate), one task per pool   SSH :22    ┌─────┴──────────────┐  │
│ ┌─────────────────────────────────┐   static key      │ ASG <name>-<pool>-*│  │
│ │ manager: gitlab-runner          │──────────────────▶│ EC2 job instances  │  │
│ │  + fleeting-plugin-aws          │ Docker API over   │ Docker, ec2-user   │  │
│ │  + docker-credential-ecr-login  │ SSH               │ helper + job       │  │
│ │ collector sidecar (optional)    │                   │ containers         │  │
│ └───┬──────────┬──────────┬───────┘                   └──┬───────┬─────────┘  │
│     │          │          │ signs cache URLs             │       │ IMDS (pools│
│     │          │          ▼                              │       │ with       │
│     │          │      S3 cache bucket ◀── archives ──────┘       │ aws_access)│
│     │          │      (gateway endpoint)                         ▼            │
│     │          │                                       instance role ─▶ STS ─▶│
│     │          ▼                                       job roles you own      │
│     │  CloudWatch: logs, metric filters, alarms, dashboard ─▶ SNS topic       │
│     ▼                                                                         │
│  autoscaling, ec2 (scale the group); ecr, secretsmanager, ssm, logs, kms      │
└───────────────────────────────────────────────────────────────────────────────┘
```

One **pool** is one runner in GitLab (its own token and tags), one manager task,
and one Auto Scaling group. Pools are the trust boundary: put jobs of different
trust levels (shared, protected branches, deploy, privileged image builds) in
different pools. Each pool's cache lives under its own prefix, which only its
own manager may sign for.

### Who makes what

| Piece | Made by | Notes |
|---|---|---|
| Runner in GitLab and its `glrt-` token | **You**, in GitLab | One per pool |
| Token parameter or secret | **You**: SSM SecureString or Secrets Manager | Its ARN is `pools[*].token_arn`. Terraform never sees the value |
| SSH key pair | **You**: private key in Secrets Manager, public key as `ssh_public_key` | |
| Manager image | **You**: `images/manager/build.sh` is one way | `manager_image` |
| Helper image | **You**: `images/mirror.sh` copies it | `helper_image` |
| Job instance AMI | ECS-optimized AL2023 as is, or **you** with `images/job-host` and `modules/ami-builder` | `ami_id` |
| Roles jobs assume | **You** | Trust policy from `output.job_role_trust_policies` |
| Network endpoints, KMS key policies, SNS topic | **You** (network, key and platform owners) | From `network_contract`, `kms_key_policy_requirements` |
| Security groups, key pair, managers, fleets, cache bucket, alarms, dashboard | **This module** | |

### How a job runs

1. The manager polls GitLab for jobs matching its runner.
2. If no instance has a free slot, the plugin raises the group's desired
   capacity; the group launches an instance from the launch template (AMI,
   key pair, security groups, user data).
3. The manager connects to the instance's private IP on port 22 as `ec2-user`
   with the static key, waits for cloud-init, and checks `docker info`, with
   retries. A failure deletes the instance (RESEARCH 3.4).
4. The manager drives Docker on the instance through that SSH connection
   (3.10). It resolves registry credentials itself: ECR through the `ecr-login`
   helper with its task role (3.6-3.9), Docker Hub images through the mirror
   the instance's Docker is configured with.
5. The helper container restores the cache: the manager signs a URL for
   `<bucket>/<pool>/project/<id>/<key>`, the helper downloads it through the
   S3 gateway endpoint (3.17-3.20).
6. The job runs. On a pool with `aws_access`, its containers reach the
   instance role through IMDS and assume the roles it may (section 3).
7. The helper uploads the cache (tar+zstd by default, 3.21) and artifacts.
8. After `max_use_count` jobs or `idle_time` without work, the plugin
   terminates the instance.

## 2. Network

### Endpoints (owned by the network team)

| Need | Endpoint | Used by |
|---|---|---|
| Scale the group | `autoscaling` (interface) | Manager (plugin) |
| Find instances | `ec2` (interface) | Manager (plugin) |
| Images | `ecr.api`, `ecr.dkr` (interface), S3 (gateway, on the subnets' route tables) | Fargate, manager, instances |
| Cache | S3 (gateway) | Instances, with URLs the manager signed |
| Secrets at task start | `secretsmanager`, `ssm` (interface) | Fargate |
| Logs, metrics | `logs` (interface) | Fargate, collector sidecar |
| Customer keys | `kms` (interface) | Fargate (secrets), AWS services |
| Jobs that assume roles | `sts` (interface), plus every service those jobs call | Job containers |
| Session Manager on instances | `ssm`, `ssmmessages`, `ec2messages` (interface) | Operators |

Private DNS on every interface endpoint, and 443 allowed from the subnets.
`output.network_contract` lists exactly what this configuration needs.

### Security groups (made by the module)

| Group | Ingress | Egress |
|---|---|---|
| `<name>-manager-*` | none | 443 to `egress_cidr_blocks` and the S3 prefix list; 22 to the instance group |
| `<name>-instance-*` | 22 from the manager group | 443 to `egress_cidr_blocks` and the S3 prefix list |

Jobs that must reach more (a database, a deploy target) get an extra group
through `instance_security_group_ids`. Network ACLs and organization policies
must allow TCP 22 between the two groups and 443 out; the module cannot see them.

## 3. Identity and job access to AWS

| Role | Can do |
|---|---|
| Manager task role `<name>-<pool>-task` | Scale its own group only (name prefix and `GitLabRunnerPool` tag); describe groups, instances, Spot requests; pull the ECR repositories the images name plus `ecr_repository_arns`; sign cache transfers under its own pool's prefix; write the collector's metrics |
| Manager execution role `<name>-<pool>-exec` | Pull the manager image; read the pool's token and the SSH key; decrypt them through SSM and Secrets Manager with `secrets_kms_key_arns` |
| Instance role (per pool) | Session Manager. An explicit **deny** on every runner token and the SSH key. On pools with `aws_access`: its policies, and `sts:AssumeRole` on its job roles |
| Job roles (yours) | What deploys need. Trust: `output.job_role_trust_policies[<pool>]` |

**How jobs get AWS credentials.** A pool with `aws_access` sets the instance
metadata hop limit to 2, so containers on the bridge network reach the instance
role. Every job on that pool can then use it. That is why:

- such a pool must be a **protected runner** in GitLab (only protected branches
  and tags run on it); the check `jobs_hold_aws_credentials` warns until you
  acknowledge it;
- the preferred shape is an instance role that can do nothing but assume
  roles you own (`assume_role_arns`), so permissions live in job roles you can
  audit by session name, and the instance role stays small;
- the explicit deny keeps even a privileged job (root on the host, so able to
  reach IMDS whatever the hop limit, RESEARCH 6.4) away from runner tokens.

A job assumes its role with the AWS CLI or SDK in the usual way, for example:

```yaml
deploy:
  tags: [deploy]
  script:
    - aws sts assume-role --role-arn "$DEPLOY_ROLE_ARN" --role-session-name "$CI_PROJECT_PATH_SLUG-$CI_PIPELINE_ID" > creds.json
    - export AWS_ACCESS_KEY_ID=$(jq -r .Credentials.AccessKeyId creds.json) ...
```

or with a profile using `credential_source = Ec2InstanceMetadata`. Jobs get
`AWS_REGION` and `AWS_STS_REGIONAL_ENDPOINTS=regional` from the runner, so STS
calls use the regional endpoint the VPC serves.

OIDC (`id_tokens`) would remove the shared role, but needs AWS to reach the
GitLab OIDC discovery document from the internet (RESEARCH 4.13).

## 4. Cache

| Choice | Value | Why |
|---|---|---|
| Storage | One S3 bucket for all pools (`cache`), created through `modules/s3` or yours | Survives the instance; one place to bound |
| Isolation | Prefix `<pool>/`, `Shared = true` inside the pool | A pool cannot read or poison another's cache; the managers of one pool share |
| Access | Presigned URLs signed by the manager's task role, regional endpoint, dual-stack off | Instances hold no S3 permission; traffic stays on the gateway endpoint |
| Encryption | The bucket's default key (`kms_key_arn` on a created bucket) | Uploads need no encryption header; the key policy names the managers (`CacheSigners`) |
| Expiry | `expiration_days` (14) after the last write; incomplete uploads 1 day | The cost is bounded |
| Format | `tarzstd`, level `fast` | Smaller and faster to unpack than zip |
| Size | `max_archive_gib` (0: no limit) | Stops one job filling the bucket |

Two further caches come with the design: an unprivileged pool's instance keeps
its pulled images for up to `max_use_count` jobs (`pull_policy =
if-not-present`), and the job-host AMI can carry the helper image pre-pulled.
For `docker build` on a privileged pool, BuildKit's registry cache
(`--cache-to type=registry,ref=<ECR repo>:cache,image-manifest=true`) keeps
layers across one-job instances; that is set in the job, not here.

## 5. Monitoring

| Signal | Source | Alarm (to `sns_topic_arn`) |
|---|---|---|
| Manager not running | ECS Container Insights `RunningTaskCount` | `<name>-<pool>-running-tasks` (from `modules/ecs`) |
| Manager errors | Metric filter `{ $.level = "error" }` on the manager log | `<name>-<pool>-manager-errors`: `error_threshold` in 15 min |
| Jobs failed by the infrastructure | Metric filter `{ $.failure_reason = "runner_system_failure" }` | `<name>-<pool>-system-failures`: `system_failure_threshold` in 15 min |
| Fleet at its ceiling | `AWS/AutoScaling GroupDesiredCapacity` | `<name>-<pool>-at-ceiling` after `ceiling_minutes` |
| Instances billing with no manager | `GroupInServiceInstances` and `RunningTaskCount`, metric math | `<name>-<pool>-instances-without-manager` after 15 min |
| Launch failures | EventBridge rule from `modules/asg-group` | Notification |
| Failed deployments, tasks that cannot start | EventBridge rule from `modules/ecs` | Notification |
| Jobs waiting too long for an instance | Collector: `fleeting_taskscaler_task_operations_total{operation="acquire_timeout"}` | `<name>-<pool>-acquire-timeouts` |
| Manager CPU and memory | Container Insights | From `modules/ecs` |

With `monitoring.metrics_collector_image` set (an AWS Distro for OpenTelemetry
collector image the subnets can pull), a sidecar scrapes the runner's
Prometheus endpoint on localhost and writes a chosen set of runner and fleeting
metrics to the `GitLabRunner` namespace: jobs by state, failed jobs by reason,
errors by level, instances and tasks by state, task operations, desired
instances, queue time. The dashboard `<name>-gitlab-runner` shows, per pool,
instances, manager health, errors and system failures, and with the collector,
jobs, waits and failure reasons.

## 6. Rollout, step by step

Each step has a check. Do not move on until it passes.

### Step 0. Decide

| Decision | Input |
|---|---|
| Runner version: GitLab's major.minor, 17.1 or later | `runner_version` |
| Pools: names, GitLab tags, privileged or not, AWS access, `max_instances` | `pools` |
| Region, VPC, two or more private subnets in different AZs | `vpc_id`, `subnet_ids` |
| Customer key for logs, volumes and the cache | `kms_key_arn` |
| Alert topic | `sns_topic_arn` |
| AMI: ECS-optimized AL2023, or the job-host AMI | `ami_id` |
| Docker Hub mirror | `docker_registry_mirror` |

### Step 1. Network

Create the endpoints in section 2 (`sts` only with `aws_access`). **Check:** from
an instance in the subnets, `getent hosts autoscaling.<region>.amazonaws.com`
returns a private address, and GitLab and the mirror answer on 443.

### Step 2. Images

```bash
images/mirror.sh <mirror>/gitlab/gitlab-runner-helper:x86_64-v<version> <ECR repository>
images/mirror.sh <mirror>/aws-observability/aws-otel-collector:<version> <ECR repository>   # with the collector
cp images/manager/versions.env.example images/manager/versions.env   # fill in, including the SHA-256s
images/manager/build.sh images/manager/versions.env
```

The repositories are yours (for example through `modules/ecr`). Optionally build
the job-host AMI (`examples/job-host-ami`). **Check:** `aws ecr describe-images`
shows both tags; the manager build printed the three component versions.

### Step 3. Runners, tokens, SSH key

For each pool, create a runner in GitLab with its tags (protected for pools
with `aws_access`), and store its token:

```bash
read -rs TOKEN
aws ssm put-parameter --name /ci/<pool>/runner-token --type SecureString \
  [--key-id <key>] --value "$TOKEN"
```

Then the SSH key:

```bash
ssh-keygen -t ed25519 -N '' -C gitlab-runner-managers -f runner-key
aws secretsmanager create-secret --name ci/runner-ssh [--kms-key-id <key>] --secret-string file://runner-key
shred -u runner-key
```

Pass the token ARNs as `pools[*].token_arn`, the secret's **full** ARN as
`ssh_private_key_secret_arn`, `runner-key.pub` as `ssh_public_key`, and any
customer keys of these as `secrets_kms_key_arns`.

**Check:** each parameter's value starts with `glrt-` (`verify_commands.<pool>.token_is_set`
after the apply, or the same command now).

### Step 4. Job roles (pools with `aws_access` only)

Create the roles jobs will assume, with the trust policy from the speculative
plan's `job_role_trust_policies[<pool>]` and the permissions the deploys need.

### Step 5. Apply

Review the speculative plan: `config_toml` per pool, `network_contract`,
`kms_key_policy_requirements` (give these to the key owner before applying),
`governance`. Apply.

**Check:**

- `verify_commands.<pool>.manager_logs` shows the runner started with no
  `fleeting-plugin` errors;
- the runner is online in GitLab;
- the dashboard shows the manager running and, if an idle policy is active,
  instances becoming InService;
- every alarm in `alarm_names` is `OK` or `INSUFFICIENT_DATA`.

### Step 6. First pipelines

```yaml
smoke:
  tags: [<pool tag>]
  image: <an image in ECR or behind the mirror>
  cache: { key: smoke, paths: [.cache/] }
  script:
    - mkdir -p .cache && date > .cache/stamp && cat .cache/stamp
```

Run it twice. **Check:** the second run restores the cache (the job log says
"Successfully extracted cache"), the object is under `<bucket>/<pool>/`. For a
privileged pool, a `docker build` with `docker:dind` and
`DOCKER_TLS_CERTDIR=/certs`; the instance is deleted after the job. For a
deploy pool, `aws sts get-caller-identity` after assuming the job role shows
the role and the session name.

### Step 7. Acceptance

| Test | Expected |
|---|---|
| 20 jobs at once on a pool with `max_instances = 5`, capacity 4 | 5 instances, 20 jobs in parallel; after `ceiling_minutes` the ceiling alarm fires |
| Stop the manager task during a job | The job fails; instances are deleted at shutdown or by the new manager at start (RESEARCH 3.5); ECS starts a new manager |
| Set the pool's `enabled = false` with instances running | The manager stops and deletes its instances; the orphan alarm stays `OK` |
| Break the token (write `x`), restart the manager | The task stops at once with "RUNNER_TOKEN is not a runner authentication token"; the running-task alarm fires |
| A job on an unprivileged pool reads IMDS | No credentials (hop limit 1) |
| A job on a pool with `aws_access` runs `aws ssm get-parameter` on a runner token | AccessDenied (the explicit deny) |
| Block port 22 between the groups | Instances are created and deleted repeatedly; the manager-errors alarm fires |

## 7. Operations

| Task | How |
|---|---|
| Upgrade the runner | Mirror the new helper; build the new manager image; change `runner_version`, `helper_image`, `manager_image` together; apply in a quiet window. Running jobs on each pool fail when its manager restarts |
| Rotate a token | Reset it in GitLab, overwrite the parameter or secret, bump the pool's `token_revision`, apply |
| Rotate the SSH key | New private key in the secret, new `ssh_public_key`, apply, restart the managers (old-key instances are deleted at restart) |
| New AMI | Change `ami_id`, apply. New instances take it; old ones end at `max_use_count` or `idle_time` |
| Pause a pool | `enabled = false`, apply |
| Clear a pool's cache | `aws s3 rm s3://<bucket>/<pool>/ --recursive` |
| Investigate | Dashboard; `manager_logs`, `scaling_activity`, `fleet_instances`; Session Manager to an instance |

## 8. Failure modes

| Symptom | Likely cause | Where to look |
|---|---|---|
| Manager task exits within seconds | Token not a `glrt-` token; execution role cannot read it or its key | Manager log; `token_is_set`; `secrets_kms_key_arns` |
| Jobs pending, desired capacity stays 0 | No `autoscaling`/`ec2` endpoint, or the task role is denied | Manager log, `fleeting-plugin` lines |
| Instances created and deleted repeatedly | Ready command fails: port 22 blocked, wrong key, `ec2-user` not in `docker` | Manager log; Session Manager: `journalctl -u cloud-final`, `id ec2-user` |
| Group cannot launch | Key policy lacks the service-linked role entries; no addresses; type unavailable | `scaling_activity`; launch-failure notification |
| Job fails pulling helper or image | Tag missing; repository not in what the task role may pull; Docker Hub image without a mirror | Job log; `ecr_repository_arns`; `docker_registry_mirror` |
| Cache "403" or never restored | Key policy lacks `CacheSigners`; bucket policy restricts to another endpoint; wrong region | Job log; `kms_key_policy_requirements` |
| `git clone` fails on TLS | Private CA not given as `ca_certificate_pem` | Job log |
| Deploy job cannot assume its role | Role trust differs from `job_role_trust_policies`; no `sts` endpoint; runner not that pool | Job log; CloudTrail `AssumeRole` errors |
| Bill grows with no jobs | Instances whose manager is down | `instances-without-manager` alarm; `fleet_instances` |

## 9. Not built

| Need | Why not |
|---|---|
| Jobs finishing during a manager restart | Fargate stops a task within 120 s; a graceful drain needs longer, so the manager runs forceful shutdown |
| OIDC credentials per job | A privately reachable GitLab cannot be an IAM OIDC provider as is (RESEARCH 4.13) |
| Windows or arm64 jobs | The helper tag, the image build and the AMI are Linux x86_64 |

## 10. What to prove before production

From [RESEARCH.md](RESEARCH.md), in the order they would break the rollout:

1. 4.8: on the chosen AMI, Docker and `sshd` run and `ec2-user` reaches Docker
   after user data (step 5).
2. 4.5: static keys need no Instance Connect endpoint (step 5).
3. 3.15: the helper trusts a private CA for `git clone` (step 6).
4. 3.16: `idle_time = "20m"` is accepted (step 5 with an idle policy).
5. 7.1-7.3: the collector reads `AOT_CONFIG_CONTENT`, counters arrive as
   deltas, and the orphan alarm's metric math is accepted (step 5 with the
   collector; `aws cloudwatch describe-alarms`).
6. 4.15-4.17: role tags as `aws:PrincipalTag`, the deny on tokens, regional STS
   (step 6, deploy pool).
7. 3.14: how many runner-manager entries accumulate in GitLab.
8. 2.9: Spot pools under Capacity Rebalancing.
9. 4.6, 4.7: no STS endpoint for the manager, no KMS rights for ECR pulls.
10. 4.9-4.11: only if building the job-host AMI.
