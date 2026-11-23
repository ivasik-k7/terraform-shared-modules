# gitlab-runner-autoscaler

Autoscaling GitLab CI runners on AWS with the **docker-autoscaler** executor and
**fleeting-plugin-aws**, for networks with no internet egress. Each pool is one
runner in GitLab: a manager on ECS Fargate and an Auto Scaling group of EC2
instances that exist only while there are jobs. With an S3 cache that outlives
the instances, AWS access for the jobs that need it, and alarms and a dashboard
for every pool. Built from this repository's `asg-group`, `ecs` and `s3` modules.

```hcl
module "runner" {
  source  = "app.terraform.io/<org>/gitlab-runner-autoscaler/aws"
  version = "~> 0.1"

  name           = "ci"
  gitlab_url     = "https://gitlab.example.com"
  runner_version = "18.6.1"
  manager_image  = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-manager:18.6.1-1"
  helper_image   = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/gitlab-runner-helper:x86_64-v18.6.1"

  vpc_id     = "vpc-0a1b2c3d4e5f60001"
  subnet_ids = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]

  ami_id                     = "ami-0123456789abcdef0"
  ssh_public_key             = "ssh-ed25519 AAAA... gitlab-runner-managers"
  ssh_private_key_secret_arn = "arn:aws:secretsmanager:eu-west-1:111122223333:secret:ci/runner-ssh-AbCdEf"
  sns_topic_arn              = "arn:aws:sns:eu-west-1:111122223333:alerts"

  pools = {
    docker = {
      token_arn = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/docker/runner-token"
      job_image = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/build:1.0.0"
    }
  }
}
```

**What the module does not make:** the images, the runner tokens, the SSH key,
the roles jobs assume. They are inputs. Tools to build the images are in
[images](images). The rollout from an empty account to a green pipeline is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); every fact the design rests on,
with its source and whether it has been proven, is in
[docs/RESEARCH.md](docs/RESEARCH.md).

## Requirements

| | |
|---|---|
| Terraform | `>= 1.9.0` |
| hashicorp/aws | `>= 6.57.1, < 7.0.0`, the range of `asg-group` and `ecs` |
| GitLab Runner | 17.1 or later (docker-autoscaler GA), major.minor equal to GitLab's |
| Network | The endpoints in `output.network_contract`; GitLab, the registries and the mirror on 443; TCP 22 between the module's two security groups |
| Images | Manager image ([images/manager](images/manager)), helper image and, with the collector, the collector image (copied by [images/mirror.sh](images/mirror.sh)) |
| Secrets | Per pool, the `glrt-` token in an SSM SecureString or a Secrets Manager secret; the SSH private key in Secrets Manager |

## What the module refuses

| Refused | Why |
|---|---|
| A `helper_image` not tagged `x86_64-v<runner_version>` | The runner looks the helper up by exactly that tag; a mismatch fails every job with "No such image" |
| `runner_version` before 17.1, or not x.y.z | docker-autoscaler is not generally available before 17.1 |
| A `manager_image` without a tag or digest, or tagged `latest` | Every manager restart would run whatever the tag points to then |
| A `token_arn` that is neither an SSM parameter nor a Secrets Manager secret | ECS can inject only those |
| `aws_access` that grants nothing | It would expose the instance role to jobs for no purpose |
| `gitlab_url` over plain HTTP; `egress_cidr_blocks` with `0.0.0.0/0` | The token travels on every request; the groups exist to keep egress known |
| A `name` longer than 19 characters | `<name>-<pool>` must fit `asg-group`'s 36 characters |
| Fargate CPU/memory pairs that do not exist; fractional counts; idle policies without periods; unknown cache formats | The API or the runner rejects them, later and less clearly |

### Advisory checks

Warnings in the plan, never refusals. Silence one with `acknowledged_checks`;
the decision is then listed in `output.governance`.

| Check | Fires when |
|---|---|
| `privileged_jobs_get_their_own_instance` | A privileged pool runs more than one job per instance, at once or in turn |
| `jobs_hold_aws_credentials` | A pool has `aws_access`: every job on it can use the role. Make that runner protected in GitLab, then acknowledge |

`acknowledged_checks` also accepts the checks of `asg-group`, `ecs` and `s3`
and passes each to the module that owns it. Those the design trips by
construction are acknowledged already (`output.governance.built_in_acknowledgements`):
a zero floor, the managers' static key, no instance refresh under running jobs,
one manager per pool, and an unversioned, destroyable cache bucket.

## Job access to AWS

A pool with `aws_access` lets its jobs use the instance role (metadata hop limit 2):

```hcl
deploy = {
  token_arn  = "arn:aws:ssm:eu-west-1:111122223333:parameter/ci/deploy/runner-token"
  job_image  = "111122223333.dkr.ecr.eu-west-1.amazonaws.com/ci/deploy:1.0.0"
  aws_access = { assume_role_arns = ["arn:aws:iam::111122223333:role/ci-deploy-workloads"] }
}
```

Prefer `assume_role_arns`: the instance role can then only assume your roles,
which carry the permissions and show each job's session in CloudTrail. Give
those roles the trust policy in `output.job_role_trust_policies[<pool>]`. Jobs
get `AWS_REGION` and `AWS_STS_REGIONAL_ENDPOINTS=regional`. Every instance role,
with or without `aws_access`, is explicitly denied the runner tokens and the SSH
key, because a privileged job can reach it too.

## Cache

On by default. One S3 bucket (created through `modules/s3`, or yours with
`cache.bucket_name`); each pool under its own prefix, which only its manager may
sign for. Instances hold no S3 permission: the manager signs each transfer, the
instance moves the archive through the S3 gateway endpoint. Objects expire
after `cache.expiration_days` (14); archives are tar+zstd at the fast level.

## Monitoring

Per pool, to `sns_topic_arn`:

| Alarm | Fires when |
|---|---|
| `<name>-<pool>-manager-errors` | The manager logs `error_threshold` errors in 15 minutes |
| `<name>-<pool>-system-failures` | `system_failure_threshold` jobs fail with `runner_system_failure` in 15 minutes |
| `<name>-<pool>-at-ceiling` | The group has wanted `max_instances` for `ceiling_minutes` |
| `<name>-<pool>-instances-without-manager` | Instances are in service and no manager runs, for 15 minutes: they bill and nothing removes them |
| `<name>-<pool>-running-tasks`, `-cpu`, `-memory` | From `modules/ecs`: the manager is down or starved |
| `<name>-<pool>-acquire-timeouts` | With the collector: jobs timed out waiting for an instance |

Plus failed-launch and failed-deployment notifications from `asg-group` and
`ecs`, and the dashboard `<name>-gitlab-runner`. With
`monitoring.metrics_collector_image`, a collector sidecar sends the runner's
and fleeting's own metrics (jobs, queue time, failure reasons, instances and
tasks by state) to the `GitLabRunner` namespace.

## Behaviour to know about

- **A manager restart fails the jobs running on its pool.** One manager per
  pool is GitLab's rule, so a deployment stops the old manager before starting
  the new one; it deletes its instances on the way out, and a new manager
  deletes any it finds.
- **The token is never in Terraform.** Rotate it by overwriting the parameter or
  secret and bumping the pool's `token_revision`.
- **ECR pulls use the manager's role,** for job and helper images alike: the
  repositories the configured images name, plus `ecr_repository_arns`.
- **Docker Hub images need a mirror** (`docker_registry_mirror`) in a network
  without internet access.
- **Idle capacity is what you pay to avoid waiting.** With no idle instance a
  job waits for one to boot, typically one to three minutes.
- **Instances are never refreshed.** A new AMI reaches new instances; old ones
  end at `max_use_count` or `idle_time`.

## Images

| Directory | What |
|---|---|
| [images/manager](images/manager) | `Dockerfile`, `entrypoint.sh`, `build.sh`, `versions.env.example`: the official runner image plus fleeting-plugin-aws and docker-credential-ecr-login, every download checked against a SHA-256 |
| [images/mirror.sh](images/mirror.sh) | Copies the helper (`gitlab-runner-helper:x86_64-v<version>`) and the collector image into ECR unchanged |
| [images/job-host](images/job-host) | An AWSTOE component for `modules/ami-builder`: Docker for `ec2-user`, the ECS agent off, bounded logs, the helper pre-pulled, an optional Docker Hub mirror |

## Examples

| Example | Shows |
|---|---|
| [examples/basic](examples/basic) | One unprivileged pool, cache, alarms and dashboard on defaults |
| [examples/complete](examples/complete) | Unprivileged, privileged Spot and deploy pools; an existing cache bucket; the collector; a mirror; a private CA |
| [examples/job-host-ami](examples/job-host-ami) | The job instance AMI through `modules/ami-builder`, in its own workspace (hashicorp/aws 5.x) |

## Most-used inputs

| Input | Default | What it does |
|---|---|---|
| `pools` | `{}` | The runners, keyed by name; fields are described on the variable |
| `pools[*].token_arn` | | The parameter or secret holding the runner's token |
| `pools[*].privileged` | `false` | Privileged job containers; defaults to one job per instance |
| `pools[*].max_instances` | `10` | The pool's ceiling, and its bill's |
| `pools[*].idle` | `[]` | Ready capacity by time of day |
| `pools[*].aws_access` | null | AWS credentials for the pool's jobs |
| `pools[*].spot` / `on_demand_base` | `false` / `0` | Spot above an on-demand base |
| `runner_version`, `manager_image`, `helper_image` | | Change all three together |
| `ami_id` | | Pinned job instance AMI |
| `cache` | on, created bucket | The S3 cache |
| `monitoring` | alarms and dashboard on | Thresholds; the collector image |
| `docker_registry_mirror` | `""` | Docker Hub mirror for the instances |
| `ca_certificate_pem` | `""` | Private CA of GitLab's certificate |
| `secrets_kms_key_arns` | `[]` | Keys of the token and SSH key secrets |
| `sns_topic_arn` | `""` | Where every alarm and notification goes |

## Contract outputs

| Output | For |
|---|---|
| `network_contract` | The network owner: endpoints, 443 destinations and ports the subnets must provide |
| `kms_key_policy_requirements` | The key owner: contract v2 entries of the fleets, managers, cache bucket and cache signers |
| `job_role_trust_policies` | Owners of the roles deploy jobs assume |
| `manager_execution_role_arns` | Owners of the token parameters and secrets, if their policies name readers |
| `deployer_requirements` | Whoever grants the Terraform role its permissions |
| `alarm_names` | On-call: what fires, per pool |
| `verify_commands` | Operators: check a token, restart a manager, follow its log, watch its fleet |
| `config_toml` | Reviewers: each manager's configuration, with the token as a placeholder |
| `governance` | Change review: pools, privilege, AWS access, cache, monitoring, acknowledgements |

## Limits

- **Never applied against real AWS.** The design is checked against GitLab
  Runner, fleeting and provider source and documentation, and the configuration
  against mocked plans. The open points, in the order they would bite, are in
  section 10 of [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
- **Relative module sources.** The module calls `../asg-group`, `../ecs` and
  `../s3`. Whether the private registry's tag-based publishing resolves those
  paths has not been checked.
- Linux x86_64 only. Jobs running during a manager restart fail.
- Spot pools under Capacity Rebalancing have not been exercised.
- One GitLab instance per module call.

## Versioning and support

Semantic versioning; tags `gitlab-runner-autoscaler-vX.Y.Z`. Breaking: removed
or renamed inputs and outputs, new required inputs, changed defaults, changes
that replace a resource, raised version floors. A deprecated input keeps working
for one minor release with a warning. Supported: the Terraform and provider
ranges above. Changes are in [CHANGELOG.md](CHANGELOG.md); costs in
[COSTS.md](COSTS.md).
