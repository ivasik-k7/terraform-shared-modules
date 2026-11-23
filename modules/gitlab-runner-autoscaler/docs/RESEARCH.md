# Research findings behind this module

Every fact the design relies on, where it comes from, and how firmly it is
established. Re-verify before production use. Anything marked **Unverified** is
a belief, not a result: it has not been read in source or documentation, and
nothing in the module should be trusted on it until it has been checked.

| Mark | Meaning |
|---|---|
| **Source** | Read in the code at the version named, while this module was written |
| **Docs** | Read in vendor documentation while this module was written |
| **Unverified** | Not proven. The "How to check" column says what would settle it |

Versions read:

- GitLab Runner source: `main` at commit `ce364f61`, `VERSION` 19.7.0 (unreleased
  at the time). Released versions may differ; re-read at the tag you deploy.
- fleeting-plugin-aws source: `main` at commit `7df83e63`, latest release v1.3.2.
- hashicorp/aws provider source: tag `v6.57.1`.
- Docs: read in November 2026.

## 1. Choosing the executor

| # | Finding | Mark | Source |
|---|---|---|---|
| 1.1 | The docker-autoscaler and instance executors are generally available from GitLab Runner 17.1. | Docs | <https://docs.gitlab.com/runner/executors/docker_autoscaler/> |
| 1.2 | The Docker Machine executor is deprecated (17.5) and planned for removal in Runner 20.0. New autoscaling setups should use docker-autoscaler. | Docs | <https://docs.gitlab.com/runner/executors/docker_machine/> |
| 1.3 | Docker Autoscaler runs each job's containers on an instance from a cloud instance group; on AWS the group is an Auto Scaling group driven by fleeting-plugin-aws. | Docs | <https://docs.gitlab.com/runner/executors/docker_autoscaler/> |
| 1.4 | Each docker-autoscaler configuration must have its own dedicated Auto Scaling group. Two managers driving one group are not supported. | Docs | <https://docs.gitlab.com/runner/executors/docker_autoscaler/> |
| 1.5 | fleeting-plugin-aws latest release is v1.3.2 (2026-11-11), MIT licensed. | Docs | <https://gitlab.com/gitlab-org/fleet-plugins/aws/-/releases> |
| 1.6 | The runner's major.minor should match GitLab's major.minor. | Docs | <https://docs.gitlab.com/runner/#gitlab-runner-versions> |

## 2. fleeting-plugin-aws

| # | Finding | Mark | Source |
|---|---|---|---|
| 2.1 | The plugin calls the Auto Scaling, EC2 and EC2 Instance Connect APIs, and connects to an instance's `PrivateIpAddress` unless told to use the external address. | Source | `provider.go` |
| 2.2 | `plugin_config` fields: `name` (the group), `region`, `profile`, `config_file`, `credentials_file`, `scale_in_termination`. | Source | `provider.go`, struct tags |
| 2.3 | With `use_static_credentials = true`, the plugin does not call `SendSSHPublicKey`: the connector uses the key in `key_path`. | Source | `provider.go` (the `SendSSHPublicKey` branch) |
| 2.4 | Connector defaults: `os = linux`, `protocol = ssh`, port 22, `username = ec2-user`. | Docs | plugin README, "Default connector config" |
| 2.5 | Group requirements: desired and minimum 0; maximum at least `max_instances`; no scaling policy; `AZRebalance` suspended; scale-in protection on. | Docs | plugin README, "Autoscaling Group Setup" |
| 2.6 | Recommended IAM: `autoscaling:SetDesiredCapacity`, `SetInstanceProtection`, `TerminateInstanceInAutoScalingGroup` on the group; `autoscaling:DescribeAutoScalingGroups`, `ec2:DescribeInstances`, `ec2:DescribeSpotInstanceRequests` on `*`; `ec2-instance-connect:SendSSHPublicKey`, `ec2:GetPasswordData` (and Start/Stop, standby calls only for suspend) for dynamic credentials and Windows. | Docs | plugin README, "Recommended IAM Policy" |
| 2.7 | Release assets are `fleeting-plugin-aws-<os>-<arch>` plus a signed checksum file `release.sha256`. | Source | `Makefile`, `ci/generate-checksums-file.sh`, `ci/upload-release.sh` |
| 2.8 | A plugin binary on `PATH` is used directly with `plugin = "fleeting-plugin-aws"`; `gitlab-runner fleeting install` instead fetches an OCI artifact from `registry.gitlab.com`, which an isolated network cannot reach. | Docs | <https://docs.gitlab.com/runner/fleet_scaling/fleeting/> |
| 2.9 | How the plugin behaves with Capacity Rebalancing (on whenever a group uses Spot): whether it adopts the replacement instance and how the job on the old one ends. | **Unverified** | Run a Spot pool, trigger a rebalance recommendation (or wait for one), read the manager log and the group's activity |
| 2.10 | The plugin is built with `CGO_ENABLED=0` (a static binary that runs on Alpine) and answers `-version`. | Source | `Makefile` (`CGO_ENABLED ?= 0`); fleeting `plugin/plugin.go` `Main` |
| 2.11 | `docker-credential-ecr-login` ships for Linux as distribution packages (Alpine community, Debian, Ubuntu, Amazon Linux); GitHub releases carry Windows executables. It is built with `CGO_ENABLED=0` and prints its version with `-v`. | Source | amazon-ecr-credential-helper `README.md`, `scripts/build_binary.sh`, `ecr-login/cli/docker-credential-ecr-login/main.go` (main, VERSION 0.13.0) |

## 3. GitLab Runner

| # | Finding | Mark | Source |
|---|---|---|---|
| 3.1 | `[runners.autoscaler]` keys: `capacity_per_instance`, `max_use_count`, `max_instances`, `plugin`, `plugin_config`, `connector_config`, `policy`, `instance_ready_command`, `instance_acquire_timeout`, `delete_instances_on_shutdown`, `state_storage`, and others. | Source | `common/config.go`, `AutoscalerConfig` |
| 3.2 | `connector_config` keys: `os`, `arch`, `protocol`, `protocol_port`, `username`, `password`, `key_path`, `use_static_credentials`, `keepalive`, `timeout`, `use_external_addr`. | Source | `common/config.go`, `ConnectorConfig` |
| 3.3 | Policy types: `idle_count` int, `idle_time` duration, `scale_factor` float64, `scale_factor_limit` int, plus `periods`, `timezone`, `preemptive_mode`. | Source | `common/config.go`, `AutoscalerPolicyConfig` |
| 3.4 | `delete_instances_on_shutdown` deletes all provisioned instances when the runner shuts down (default false, since 15.11). `instance_ready_command` runs on each new instance; a failure removes the instance (since 16.11). | Docs | <https://docs.gitlab.com/runner/configuration/advanced-configuration/> |
| 3.5 | Without `state_storage`, a starting runner removes every instance that already exists in the group ("no data on pre-existing instance so removing for safety"), and any instance with a recorded acquisition. A manager restart therefore cleans up after the previous one, and ends the jobs that were on those instances. | Source + Docs | `executors/internal/autoscaler/provider.go`, `instanceReadyUp`; docs: `state_storage` section |
| 3.6 | The helper image is pulled through the same pull manager, with the same credential resolution, as job images. | Source | `executors/docker/docker.go` `getHelperImage` → `pullManager.GetDockerImage` → `resolveAuthConfigForImage` |
| 3.7 | Registry credentials are looked up in order: `DOCKER_AUTH_CONFIG`, then the runner user's `~/.docker/config.json`, then build credentials. | Source | `helpers/docker/auth/auth.go`, `AllConfigs` |
| 3.8 | `allowed_docker_credential_helpers` restricts helpers named by a job-supplied `DOCKER_AUTH_CONFIG`; helpers named in the runner host's own Docker configuration files are not affected. | Source + Docs | `common/config.go` field description; advanced configuration docs |
| 3.9 | Credential helpers run on the runner manager host, with its credentials. So `docker-credential-ecr-login` in the manager image authenticates ECR pulls with the manager's task role, and the job instances need no ECR permission. | Docs + Source | GitLab "Use a private container registry" docs; 3.6 and 3.7 |
| 3.10 | The runner reaches Docker on an instance at the manager's `DOCKER_HOST`, or the default Unix socket, dialled through the SSH connection to the instance. The SSH user (`ec2-user`) must therefore be able to use the Docker socket, i.e. be in the `docker` group. | Source | `executors/docker/docker.go`, `environmentDialContext` |
| 3.11 | The helper image tag is `x86_64-v<runner version>`; it must exist in the registry the runner uses before the runner is upgraded, or jobs fail with "No such image". | Docs | <https://docs.gitlab.com/runner/configuration/advanced-configuration/#helper-image> |
| 3.12 | One runner authentication token (`glrt-...`) can be used by several runner managers; each is told apart by its `system_id`. | Docs | <https://docs.gitlab.com/ci/runners/new_creation_workflow/> |
| 3.13 | Signals: `SIGTERM`/`SIGINT` force a shutdown (jobs are aborted after `shutdown_timeout`); `SIGQUIT` waits for running jobs. | **Unverified** | Read <https://docs.gitlab.com/runner/commands/#signals> |
| 3.14 | The `system_id` is kept in a file next to `config.toml`. On Fargate the file system is new on every start, so each manager restart shows in GitLab as a new runner manager under the same runner. How GitLab ages out the old entries. | **Unverified** | Restart a manager twice; look at the runner's managers list in GitLab |
| 3.15 | With `tls-ca-file`, the runner also passes the CA to the job, so the helper's `git clone` trusts the same certificate. | **Unverified** | Run a job against a GitLab whose certificate is from a private CA; check the clone step |
| 3.16 | BurntSushi/toml (v1.6.0 in the runner) decodes a TOML string such as `"20m"` into a `time.Duration`. The module writes `idle_time` that way, as GitLab's own examples do. | **Unverified** | `gitlab-runner verify` / first start with an idle policy |
| 3.17 | `Type = "s3"` uses the AWS SDK v2 adapter (`s3v2`) unless `FF_USE_LEGACY_S3_CACHE_ADAPTER` is on. With `AuthenticationType = "iam"` it loads the SDK's default credential chain, so the manager's task role signs. | Source | `common/build.go` (the adapter switch), `cache/s3v2/s3.go` `newRawS3Client` |
| 3.18 | `DualStack` defaults to true; with no `ServerAddress` the SDK uses the bucket's regional endpoint, and `BucketLocation` sets the region without a lookup. The module sets `DualStack = false`. | Source | `cache/cacheconfig/cacheconfig.go` `DualStackEnabled`; `cache/s3v2/s3.go` |
| 3.19 | Cache objects are at `<Path>/project/<id>/<key>` when `Shared = true`, else `<Path>/runner/<short token>/project/<id>/<key>`. | Source | `cache/cache.go` |
| 3.20 | A presigned PUT carries encryption headers only when `ServerSideEncryption` is set; otherwise the bucket's default encryption applies. `modules/s3`'s `enforce_kms_key` denies only a PUT whose header names something else. | Source | `cache/s3v2/s3.go` `PresignURL`; `modules/s3/locals.tf` (`DenyOtherEncryption`) |
| 3.21 | The cache archiver reads `CACHE_COMPRESSION_LEVEL` (fastest, fast, default, slow, slowest) and `CACHE_COMPRESSION_FORMAT` (zip, tarzstd, zipzstd) from the job's variables. `MaxUploadedArchiveSize` (bytes) stops larger uploads. Fastzip is on by default and its flag is deprecated. In which runner version each first appeared is not established. | Source | `commands/helpers/cache_archiver.go`; `cache/cacheconfig/cacheconfig.go`; `helpers/featureflags/flags.go` |
| 3.22 | `log_format = "json"` uses logrus's JSON formatter (`level`, `msg`, `time` fields). A failed job is logged with `failure_reason`; a system failure at error level with `failure_reason = "runner_system_failure"`. | Source | `log/configuration.go`; `common/build.go`; `common/network.go` |
| 3.23 | The runner serves Prometheus metrics at the global `listen_address`, among them `gitlab_runner_jobs`, `gitlab_runner_failed_jobs_total`, `gitlab_runner_errors_total`, `gitlab_runner_job_queue_duration_seconds`. Fleeting adds `fleeting_provisioner_instances{state}`, `fleeting_provisioner_instance_operations_total{operation}`, `fleeting_taskscaler_tasks{state}`, `fleeting_taskscaler_task_operations_total{operation}` (operations include `acquire_timeout`, `reserve_available_capacity_failure`), `fleeting_taskscaler_desired_instances`. | Source | runner `common/config.go` and metric definitions; fleeting and taskscaler `metrics/prometheus/metrics_collector.go`, `metrics/collector.go` (HEAD, November 2026) |
| 3.24 | The official Alpine runner image: `dumb-init` as PID 1, `/entrypoint` copies `/etc/gitlab-runner/certs/ca.crt` into the system trust store and execs `gitlab-runner`, `STOPSIGNAL SIGQUIT`, `VOLUME ["/etc/gitlab-runner", "/home/gitlab-runner"]`. The manager image keeps the first two and sets `STOPSIGNAL SIGTERM`. | Source | runner-tools base-images `dockerfiles/runner/Dockerfile.alpine`, `dockerfiles/runner/alpine/entrypoint` (HEAD, November 2026) |

## 4. AWS

| # | Finding | Mark | Source |
|---|---|---|---|
| 4.1 | `autoscaling:SetDesiredCapacity`, `SetInstanceProtection` and `TerminateInstanceInAutoScalingGroup` act on the `autoScalingGroup` resource and support the `autoscaling:ResourceTag/${TagKey}` and `aws:ResourceTag/${TagKey}` condition keys. The module scopes them by name prefix and a pool tag. | Docs | <https://docs.aws.amazon.com/service-authorization/latest/reference/list_amazonec2autoscaling.html> |
| 4.2 | The Fargate container `stopTimeout` ceiling is 120 seconds. | Docs | <https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html> |
| 4.3 | Fargate CPU and memory come in fixed pairs (0.25 vCPU: 0.5-2 GB; 0.5 vCPU: 1-4 GB; 1 vCPU: 2-8 GB). | **Unverified** | Read <https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-tasks-services.html> |
| 4.4 | The plugin's calls need interface endpoints `com.amazonaws.<region>.ec2` and `com.amazonaws.<region>.autoscaling` in a VPC without internet egress. | Docs | AWS PrivateLink "AWS services that integrate with AWS PrivateLink" |
| 4.5 | EC2 Instance Connect's `SendSSHPublicKey` has no documented interface endpoint; the EC2 Instance Connect Endpoint product is a different thing (a tunnel). The module therefore uses static SSH credentials. | **Unverified** | Search the PrivateLink service list for `ec2-instance-connect` in your region |
| 4.6 | Fargate tasks get task-role credentials from the ECS credentials endpoint, so the manager needs no STS endpoint. | **Unverified** | Run the manager in a subnet without an STS endpoint and watch for credential errors |
| 4.7 | Pulling from an ECR repository encrypted with a customer managed key needs no KMS permission on the puller's side. | **Unverified** | Pull with a role that has no `kms:Decrypt` on the repository's key |
| 4.8 | The Amazon ECS-optimized Amazon Linux 2023 AMI has Docker installed and enabled, `sshd` running, and `ec2-user` able to `sudo`. Whether `ec2-user` is already in the `docker` group is not known; the module's user data adds it. | **Unverified** | Launch it once; `id ec2-user`, `systemctl is-enabled docker sshd` |
| 4.9 | Amazon Linux 2023 package repositories are reachable through the S3 gateway endpoint (the job-host AMI build installs Docker with `dnf` when the parent lacks it). | **Unverified** | `dnf makecache` on an instance in the build subnet |
| 4.10 | The AWS CLI is on the ECS-optimized AL2023 AMI (the job-host component uses it to pre-pull the helper from ECR). | **Unverified** | `aws --version` on a build of the component |
| 4.11 | Starting or stopping a systemd unit from user data with a blocking call can deadlock `cloud-final`; `systemctl --no-block` avoids it. | **Unverified** (reported) | Boot the AMI with and without `--no-block` |
| 4.12 | Docker's `registry-mirrors` applies only to images from Docker Hub. Images from other registries must be named with the mirror's host. | **Unverified** | Read <https://docs.docker.com/reference/cli/dockerd/#daemon-configuration-file> |
| 4.13 | A job's OIDC `id_tokens` can be exchanged for AWS credentials only if AWS STS can fetch GitLab's OIDC discovery document and keys from the internet. A GitLab that is reachable only privately cannot be an IAM OIDC provider as is. | **Unverified** | Create the IAM OIDC provider for the GitLab URL; try `AssumeRoleWithWebIdentity` |
| 4.14 | EC2 key pairs accept ED25519 public keys for Linux instances. | **Unverified** | Read <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html> |
| 4.15 | An assumed-role session carries the role's tags as `aws:PrincipalTag/<key>`, so a job role's trust can select the instance roles of one pool by the `GitLabRunnerPool` tag. | **Unverified** | Assume a job role from a deploy pool; then from another pool's instance role, which must be refused |
| 4.16 | `AmazonSSMManagedInstanceCore` grants `ssm:GetParameter(s)` on `*`, so an instance role with it could read SecureString tokens under the AWS-managed key. The module adds an explicit deny on the runner tokens and the SSH key. | **Unverified** | Read the policy version: `aws iam get-policy-version` |
| 4.17 | AWS SDKs and the CLI honour `AWS_STS_REGIONAL_ENDPOINTS=regional`; current versions use the regional endpoint anyway. | **Unverified** | `aws sts get-caller-identity --debug` in a job; look at the endpoint |
| 4.18 | Auto Scaling group metrics at one-minute granularity are free. | **Unverified** (stated by `modules/asg-group`) | Read the Amazon EC2 Auto Scaling monitoring page |
| 4.19 | S3 gateway endpoints serve the regional S3 hostnames of their region; dual-stack hostnames are not relied on (3.18). | **Unverified** | A cache round trip from an instance (ARCHITECTURE step 6) |
| 4.20 | Docker's `registry-mirrors` accepts a mirror served under a URL path. The module accepts only `https://host[:port]` so it does not depend on it. | **Unverified** | Start Docker with a path-style mirror and pull `alpine` |
| 4.21 | Fargate sends the image's `STOPSIGNAL` when it stops a task. With `STOPSIGNAL SIGTERM` the manager gets SIGTERM either way. | **Unverified** | Stop a task; the manager log shows which shutdown ran |
| 4.22 | The `awscli-2` package is in the Amazon Linux 2023 repositories (the job-host component installs it when the parent lacks `aws`). | **Unverified** | `dnf info awscli-2` on AL2023 |

## 5. Terraform and the AWS provider

| # | Finding | Mark | Source |
|---|---|---|---|
| 5.1 | With `aws_ssm_parameter.value_wo`, the read sets `value` to null, so the value written later with `put-parameter` never enters state. With `value` plus `ignore_changes`, every refresh reads the real value back into state. | Source | provider `v6.57.1` `internal/service/ssm/parameter.go`, read function |
| 5.2 | Any in-place update of such a parameter other than tags (description, key, tier, pattern) sends `PutParameter` with the stored `value`, which is empty under `value_wo`, so the update fails. Together with 5.1, this is why the module takes the token as a parameter or secret made outside Terraform. | Source | same file, update function |
| 5.3 | Write-only arguments need Terraform 1.11 or later. | Docs | <https://developer.hashicorp.com/terraform/language/resources/ephemeral#write-only-arguments> |
| 5.4 | HCL evaluates both branches of a conditional but reports errors only from the selected one, so a ternary guards a `tonumber()` that would fail on bad input. | **Unverified** for this exact case | `terraform test` on the `runner_version` validation with a malformed value |

## 6. Security posture

| # | Finding | Mark | Source |
|---|---|---|---|
| 6.1 | A privileged container is root on its host: it can read and change other jobs' files, Docker state and credentials on the same instance. One job per instance (`capacity_per_instance = 1`, `max_use_count = 1`) is the isolation boundary for privileged work. | **Unverified** | Read <https://docs.gitlab.com/runner/security/#usage-of-docker-executor> |
| 6.2 | Anyone who can push a pipeline that runs on a pool controls code on that pool's instances. Pools are the trust boundary: one per trust level (shared, protected branches, deploy). | **Unverified** | Read <https://docs.gitlab.com/runner/security/> |
| 6.3 | With an IMDS hop limit of 1, containers on the default bridge network cannot reach the instance metadata service, so jobs do not get the instance role's credentials. | **Unverified** | Read <https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/configuring-IMDS-existing-instances.html> |
| 6.4 | A privileged container is root on the host, so it can reach the instance metadata service from the host's network namespace whatever the hop limit, and with it the instance role. The instance role therefore stays minimal and carries the explicit deny (4.16). | **Unverified** (follows from 6.1) | From a privileged job: `nsenter -t 1 -n curl` to IMDS |

## 7. Monitoring

| # | Finding | Mark | Source |
|---|---|---|---|
| 7.1 | The AWS Distro for OpenTelemetry collector on ECS reads its configuration from the `AOT_CONFIG_CONTENT` environment variable. | **Unverified** | Start the sidecar; its log names the configuration it loaded |
| 7.2 | The `awsemf` exporter turns Prometheus counters (cumulative) into per-interval values, so a `Sum` over a period is the increase in that period. The `acquire_timeouts` alarm relies on it. | **Unverified** | Compare `fleeting_taskscaler_task_operations_total` in CloudWatch with the runner's `/metrics` |
| 7.3 | CloudWatch metric math accepts `IF(FILL(tasks, 0) < 1 AND instances > 0, 1, 0)` in an alarm. | **Unverified** | `aws cloudwatch describe-alarms` after the apply; the alarm state is not `INSUFFICIENT_DATA` forever |
| 7.4 | Container Insights publishes `RunningTaskCount` per service in `ECS/ContainerInsights`, which `modules/ecs` already alarms on. | Source | `modules/ecs/observability.tf` |

## 8. What the module does because of these findings

| Finding | Effect in the module |
|---|---|
| 1.4 | One manager per pool, ECS deployment that stops the old task before starting the new one |
| 2.3, 4.5 | Static SSH key; no Instance Connect permissions or endpoint |
| 2.5 | `asg-group` called with min 0, desired 0, protection on, `AZRebalance` suspended, no refresh, no scaling policy |
| 2.6, 4.1 | Task role: scaling actions on `<name>-<pool>-*` groups carrying the pool tag; describe calls on `*`; nothing for Instance Connect |
| 2.8, 2.10, 2.11, 3.24 | The plugin binary is baked into the manager image; the ECR helper comes from apk; the image keeps dumb-init and the official entrypoint and stops with SIGTERM |
| 3.4, 3.5 | `delete_instances_on_shutdown = true`; restarts clean up after themselves |
| 3.6-3.9 | `docker-credential-ecr-login` in the manager image, registries listed in the manager's `~/.docker/config.json`, not in `DOCKER_AUTH_CONFIG` |
| 3.10 | User data and the job-host AMI put `ec2-user` in `docker`; the ready command waits for cloud-init and checks with `sg docker` |
| 3.11 | `helper_image` must carry `x86_64-v<runner_version>` (validation) |
| 4.2, 3.13 | `stop_timeout = 120`, `shutdown_timeout = 110` |
| 5.1-5.3 | The module creates no token parameter: written by Terraform, the token would sit in state (`value`), or need write-only arguments and Terraform 1.11 and then fail on any later update (`value_wo`). Pools take the ARN of a parameter or secret made outside |
| 3.17-3.21 | Cache: S3 through the task role, regional endpoint, prefix per pool, bucket-default encryption, tar+zstd |
| 3.22, 3.23, 7.x | Metric filters on `level` and `failure_reason`; optional collector for runner and fleeting metrics |
| 4.15, 4.16, 6.4 | Job roles trust a pool by tag; the instance role is denied the runner's secrets |
| 6.1 | Privileged pools default to one job per instance; a check warns otherwise |
