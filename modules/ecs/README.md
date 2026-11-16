# terraform-aws-ecs

Amazon ECS for a regulated estate: one cluster, and every workload on it from a
single `services` map. Long-running services, daemons, scheduled jobs and
pipeline-run tasks; Fargate, Fargate Spot and EC2 capacity; Service Connect,
load balancers, EFS and managed EBS volumes; autoscaling; per-workload IAM;
alarms, and EventBridge rules for the failures that leave an apply green.

**Stage:** 1.0.0 release candidate. Stable once a security review reports no
open Critical or High finding ([GOVERNANCE](../../docs/GOVERNANCE.md)).

```hcl
module "ecs" {
  source  = "app.terraform.io/<org>/ecs/aws"
  version = "~> 1.0"

  name               = "orders-prod"
  subnet_ids         = var.private_subnet_ids # two AZs or more, with the endpoints in output.network_contract
  security_group_ids = [var.task_sg_id]
  sns_topic_arn      = var.alerts_topic_arn
  log_kms_key_arn    = var.logs_key_arn

  services = {
    api = {
      image          = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/orders-api:1.4.2"
      port           = 8080
      load_balancers = [{ target_group_arn = var.api_target_group_arn }]
      autoscaling    = { min = 2, max = 10 }
      secrets        = { DB_PASSWORD = "${var.db_secret_arn}:password::" }
    }
    nightly = {
      workload = "scheduled"
      image    = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/orders-jobs:1.4.2"
      capacity = "spot_preferred"
      schedule = { expression = "cron(0 2 * * ? *)", timezone = "Europe/London", dead_letter_queue_arn = var.dlq_arn }
    }
    migrate = {
      workload = "task" # run by the pipeline: output.run_task_commands.migrate
      image    = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/orders-api:1.4.2"
      command  = ["./bin/migrate", "up"]
    }
  }
}
```

Re-export the contract outputs as root outputs of the workspace, or read them
with `tfe_outputs`: `network_contract` goes to the network team,
`kms_key_policy_requirements` to the key owners (or straight into
[`modules/kms`](../kms) as a consumer), `notification_requirements` to whoever
owns the topic, and `deployer_requirements` to whoever owns the apply role.

## Requirements

| Component | Supported | What a workspace must do |
|---|---|---|
| Terraform | `>= 1.9.0` | Set the workspace's Terraform version to 1.9 or later |
| `hashicorp/aws` | `>= 5.100.0, < 7.0.0` | Commit the `.terraform.lock.hcl`. CI runs every test on 5.100.0 and the newest 6.x, so the module can share a workspace with modules on either major |
| Account | The ECS service-linked role `AWSServiceRoleForECS` | ECS creates it on first use if the apply role may call `iam:CreateServiceLinkedRole`; `output.deployer_requirements` includes that permission |
| Network | Private subnets with the VPC endpoints the workloads need | The module creates no network resources. `output.network_contract` lists the endpoints for exactly the features used |

Secret ARNs, policy documents, target groups and keys can come from resources
in the same root. Which roles, policies and alarms exist is decided by map keys
and switches, never by whether an ARN is known, so values unknown at plan do
not break the plan.

## What the module refuses

These fail at plan, with a message naming the field. Each is a configuration
ECS would accept and then get wrong, or reject at apply or at the first task
start.

| Refused | Because |
|---|---|
| A Fargate `cpu`/`memory` pair Fargate does not offer | `RegisterTaskDefinition` fails at apply. The table is AWS's ([task size](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html#task_size)), including 32 vCPU |
| On Fargate: a network mode other than `awsvpc`, placement constraints or strategies, `privileged`, `host_path` or Docker volumes, `ipc_mode` | Fargate does not support them |
| A capacity strategy mixing Fargate and EC2 providers, more than one `base`, no positive weight | ECS rejects the strategy; it holds Fargate or Auto Scaling group providers, never both |
| `capacity` or `capacity_provider_strategy` on a daemon | A daemon runs one task on every container instance, so it is sent as `launch_type = EC2` |
| A secret, global secret or log secret given by name instead of ARN | The execution role's policy cannot be scoped to a name. Secrets Manager ARNs may carry `:json-key:version-stage:version-id` |
| `assign_public_ip = true` without `allow_public_ip = true` | A public IP in a public subnet exposes every port the security groups open |
| `rollback` without `circuit_breaker` | ECS has nothing to roll back from |
| A container mounting a volume the service does not declare; `depends_on` or `volumes_from` naming a container it does not have; `awsfirelens` logging with no router container | The task registers and then fails to start |
| `configure_at_launch` without a `managed_ebs_volume` naming it, or the reverse | The task fails to start, waiting for a volume nothing provides |
| EFS IAM authorisation or an access point without transit encryption | EFS requires TLS for both |
| ECS Exec on a container with a read-only root file system | The SSM agent writes to it; sessions fail |
| Load balancers, Service Connect or a registry on a `scheduled` or `task` workload; a `schedule` anywhere else; autoscaling on anything but a `service` | There is no service for them to attach to, or no schedule to run |
| `autoscaling` with nothing to scale on | The target exists and nothing ever changes the count |
| A Fargate ephemeral storage key that is an alias or multi-Region key | Fargate supports neither ([storage key](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-create-storage-key.html)) |
| A `required_tag_keys` key missing from `tags` | Tasks would be invisible to cost allocation and tag-based SCPs |
| A scheduled workload with more than six strategy entries | EventBridge Scheduler accepts no more |

### Advisory checks

Fifteen `check` blocks warn without refusing. Each is silenced by naming it in
`acknowledged_checks`, and the decision is then listed in `output.governance`.
All are silent when `create = false`.

| Check | Warns when |
|---|---|
| `somebody_hears_a_failure` | `sns_topic_arn` is empty, or both `create_alarms` and `create_event_rules` are off |
| `deployments_roll_back` | a service has the circuit breaker or rollback off |
| `images_are_pinned` | an image has no tag, or is tagged `latest`: two tasks of one revision can run different code. Other tags are trusted to be immutable (ECR tag immutability); `governance.mutable_tag_images` lists every image not pinned by digest |
| `log_retention_is_bounded` | `log_retention_days = 0` |
| `logs_use_a_customer_key` | `log_kms_key_arn` is empty |
| `services_survive_an_az` | a service runs fewer than two tasks (`desired_count`, or `autoscaling.min`) |
| `spot_services_keep_an_on_demand_floor` | a service is on Fargate Spot with no on-demand share. Fargate does not fall back to on-demand |
| `shell_access_is_intended` | a workload has `enable_execute_command` |
| `task_costs_are_attributable` | a workload has `propagate_tags = "NONE"` |
| `running_task_alarms_have_data` | alarms are on and `container_insights = "disabled"`, so no running-task alarm can exist |
| `failed_schedules_are_kept` | a scheduled workload has no `dead_letter_queue_arn` |
| `shell_sessions_are_recorded` | ECS Exec is on and `execute_command.logging = "NONE"` |
| `containers_stay_on_their_side` | a container is privileged, adds capabilities, mounts a host path, or shares the host's network, pid or ipc namespace (`governance.host_access`) |
| `roles_are_not_administrators` | a workload role has `AdministratorAccess`, `IAMFullAccess`, `PowerUserAccess`, or an inline `"Action": "*"` or `"iam:*"` |
| `secrets_are_not_in_environment` | an environment variable is named like a secret (`*PASSWORD`, `*TOKEN`, `*API_KEY`...): it would be in state and in `DescribeTaskDefinition` |

## Workloads

Every entry of `services` is a task definition, `<name>-<key>`, with its own
task role, execution role and log group (`/ecs/<name>/<key>`), plus:

| `workload` | Becomes | Notes |
|---|---|---|
| `service` (default) | An ECS service | `desired_count`, or `autoscaling` |
| `daemon` | A DAEMON service on EC2 | `launch = "EC2"`, no capacity |
| `scheduled` | An EventBridge Scheduler schedule in the group `<name>` | Runs with the workload's strategy, retries `maximum_retry_attempts` times, then its DLQ |
| `task` | The task definition only | `output.run_task_commands` has the `aws ecs run-task` line for the pipeline |

**Containers.** `image` with `port`, `command`, `environment`, `secrets` and
`health_check` is one container named after the key. For sidecars, init
containers and log routers, use `containers`, keyed by container name; each
takes the full container definition in snake_case (`port_mappings`,
`mount_points`, `depends_on`, `health_check`, `readonly_root_filesystem`,
`linux_parameters` as `init_process_enabled`/`capabilities_*`, `ulimits`,
`firelens`, `log_driver`...). `global_environment` and `global_secrets` reach
every container; a container's own value wins. Empty and zero fields are not
sent (only `readonlyRootFilesystem` and `essential` always are), so the
definition ECS returns matches the one planned.

**Capacity.** `capacity` is a preset or an `ec2_capacity_providers` key;
`capacity_provider_strategy` overrides it. Fargate workloads without either use
`default_capacity` when that is a preset, otherwise `on_demand`.

| Preset | Strategy | For |
|---|---|---|
| `on_demand` | FARGATE | Anything that must not be interrupted |
| `balanced` | FARGATE base 1, then 1:3 FARGATE:FARGATE_SPOT | Services that tolerate interruption above one task |
| `spot_preferred` | 1:4 FARGATE:FARGATE_SPOT | Workers and jobs that retry |
| `spot_only` | FARGATE_SPOT | Jobs that can wait for capacity |

**Service Connect.** `service_connect = {}` on an image-shortcut service with
a `port` publishes that port under the service name in the cluster's
namespace. With `containers`, name the ports to publish in `expose` (keyed by
`port_mappings[*].name`); an empty `expose` makes the service a client only.
The proxy logs to the workload's log group.

**IAM.** The task role trusts `ecs-tasks.amazonaws.com` only with
`aws:SourceAccount` and an `aws:SourceArn` of ECS in this account and region,
the form AWS documents (a cluster-specific ARN is not supported there). The
module adds what the configuration needs and nothing else: the four
`ssmmessages` actions for ECS Exec, `kms:Decrypt` on the exec key, writes to
the exec log destination, and `elasticfilesystem:ClientMount` (plus
`ClientWrite` where a mount is writable) scoped to the access point. Your own
statements go in `task_role.policies`, keyed by name. The execution role gets
`AmazonECSTaskExecutionRolePolicy`, `GetSecretValue` on exactly the workload's
secrets, `ssm:GetParameters` on its parameters, `kms:Decrypt` on
`secrets_kms_key_arns` only through Secrets Manager and SSM, environment files
and `environment_files_kms_key_arns` through S3, and the log key through
CloudWatch Logs, which requires log writers to hold it. Every S3 grant carries
`aws:ResourceAccount` (`trusted_s3_account_ids`, default this account), so a
deleted bucket's name registered elsewhere receives nothing. The scheduler role
may send to the workloads' dead-letter queues and use their keys through SQS.
Bring your own role with `create = false` and `arn`.

## Services fields

Every field of a `services` entry. Empty strings and `0` mean unset unless a
row says otherwise.

**Shape and placement**

| Field | Default | Effect |
|---|---|---|
| `workload` | `"service"` | `service`, `daemon`, `scheduled` or `task` ([Workloads](#workloads)) |
| `launch` | `"FARGATE"` | `FARGATE` or `EC2`; the task definition's `requiresCompatibilities` |
| `capacity`, `capacity_provider_strategy` | `""`, `[]` | Preset or EC2 provider key; an explicit strategy wins. Never set on a daemon |
| `cpu`, `memory` | `256`, `512` | Task size in CPU units and MiB; Fargate pairs are validated. $0.04656 per vCPU-hour, $0.00511 per GB-hour in eu-west-2 |
| `cpu_architecture`, `operating_system_family` | `"X86_64"`, `"LINUX"` | `ARM64` is 20% cheaper on Fargate |
| `network_mode` | `"awsvpc"` | Fargate requires `awsvpc` |
| `ephemeral_storage_gib` | `0` (20 GiB) | 21-200, Fargate only; $0.000129 per GB-hour above 20 |
| `pid_mode`, `ipc_mode` | `""` | `pid_mode = "task"` on Fargate; `host` only on EC2, and warned (`containers_stay_on_their_side`) |
| `platform_version` | `"LATEST"` | Fargate platform version |
| `subnet_ids`, `security_group_ids` | module values | Per-workload network |
| `assign_public_ip` | `false` | Needs `allow_public_ip` |
| `placement_constraints`, `ordered_placement_strategy` | `[]` | EC2 only. A first strategy other than an AZ spread turns AZ rebalancing off |

**Containers** (the image shortcut: `image`, `port`, `command`, `environment`, `secrets`, `health_check` as a command list)

| Field | Default | Effect |
|---|---|---|
| `containers[*].image` | required | Pin a tag in an immutable repository, or a digest |
| `essential` | `true` | At least one per workload |
| `cpu`, `memory`, `memory_reservation` | `0` | Container-level limits |
| `command`, `entrypoint`, `working_directory`, `user` | empty | As in Docker |
| `environment`, `secrets` | `{}` | `secrets` values are Secrets Manager or SSM ARNs; merged over `global_*` |
| `environment_files` | `[]` | S3 object ARNs ending in `.env`; keys in `environment_files_kms_key_arns` |
| `port_mappings` | `[]` | `name` is what Service Connect and `expose` refer to; the shortcut's port is named after the workload |
| `mount_points`, `volumes_from`, `depends_on` | empty | `depends_on` maps a container to `START`, `COMPLETE`, `SUCCESS` or `HEALTHY` |
| `health_check` | none | `interval` 30, `timeout` 5, `retries` 3, `start_period` 0 |
| `readonly_root_filesystem` | `false` | Not with ECS Exec |
| `privileged`, `capabilities_add`, `capabilities_drop` | off | EC2 only for `privileged`; warned |
| `init_process_enabled` | `false` | On for the image shortcut whenever `enable_execute_command` is |
| `ulimits`, `docker_labels`, `start_timeout`, `stop_timeout` | empty | As in ECS |
| `repository_credentials_arn` | `""` | Secrets Manager secret for a private registry |
| `log_driver`, `log_options`, `log_secret_options` | `awslogs` to `/ecs/<name>/<key>` | `awsfirelens` needs a container with `firelens` |
| `firelens` | none | `{ type = "fluentbit", options }` makes the container a log router |

**Storage**

| Field | Default | Effect |
|---|---|---|
| `volumes[*]` | bind mount | One of `host_path` (EC2), `efs`, `docker` (EC2), `configure_at_launch` |
| `volumes[*].efs` | TLS and IAM on | `access_point_id` scopes the task role's mount permission; `root_directory` only without one |
| `managed_ebs_volume` | none | `volume_name` (a `configure_at_launch` volume), `size_in_gb` or `snapshot_id`, `volume_type` gp3, `iops`, `throughput`, `kms_key_arn`, `file_system_type` ext4. Always encrypted and tagged; billed per GB-month while the task runs |

**Running the service**

| Field | Default | Effect |
|---|---|---|
| `desired_count` | `1` | Ignored for `scheduled`, `task` and `daemon`; the starting count with autoscaling |
| `load_balancers` | `[]` | `container_name` and `container_port` default from the shortcut, or from a container's only port |
| `health_check_grace_period_seconds` | `0` | 60 when the service has a load balancer |
| `deployment.minimum_healthy_percent` | unset | 100 for a service, 0 for a daemon (the API's defaults) |
| `deployment.maximum_percent` | `200` | 100 turns AZ rebalancing off |
| `deployment.circuit_breaker`, `rollback` | `true`, `true` | Services only |
| `deployment.alarm_names` | `[]` | CloudWatch alarms that fail and roll back a deployment |
| `deployment.wait_for_steady_state` | `false` | The apply waits for the deployment |
| `deployment.availability_zone_rebalancing` | `true` | Sent only where ECS supports it |
| `autoscaling` | none | `min` 1, `max` required, `cpu_target` 70, `memory_target` 0, `requests_per_target` 0 with `alb_resource_label`, `custom` metrics, cooldowns 300/60, `disable_scale_in`, `schedules` with a timezone |
| `schedule` | none | `expression`, `timezone` UTC, `enabled`, `task_count` 1, `flexible_window_minutes` 0, `maximum_retry_attempts` 2, `maximum_event_age_seconds` 3600, `dead_letter_queue_arn`, `dead_letter_queue_kms_key_arn` |
| `service_connect` | none | `namespace_arn` (else the cluster's), `log_proxy` true, `expose` keyed by port name with `discovery_name`, `dns_name`, `port`, `ingress_port_override`, timeouts |
| `service_registry_arn` | `""` | A Cloud Map service with A records; SRV records are not supported |
| `enable_execute_command` | `false` | Warned (`shell_access_is_intended`) |
| `propagate_tags` | `"SERVICE"` | `NONE` is warned for services |
| `force_delete` | `false` | Delete the service without scaling it to zero first |
| `task_role`, `execution_role` | created | `create = false` with `arn` to bring your own; `policies` (inline, by name) and `managed_policies` (by name) on created roles |
| `alarms` | on | `enabled`, `cpu_percent` and `memory_percent` (`0` is the module default) |
| `tags` | `{}` | Added to the workload's resources and tasks; `ManagedBy` and `Module` stay the module's |

## Behaviour to know about

**Every service update is a deployment.** `force_new_deployment` is always
`true`. Without it, changing `capacity_provider_strategy` replaces the service
on aws 5.x and is refused at plan on 6.x (provider source,
`internal/service/ecs/service.go`, `capacityProviderStrategyCustomizeDiff`, at
both tags). With it, a change between two strategies is an update, and an
update to anything but tags (a grace period, a count on a static service) also
replaces the tasks, by a rolling deployment. On aws 5.x, adding a strategy to a
service that had none still replaces it; the module always sends one, so this
only meets services created elsewhere (see the upgrade guide).

**An autoscaled service is a different resource.** `aws_ecs_service.autoscaled`
ignores `desired_count` after creation, so an apply does not undo the scaler;
it starts at `autoscaling.min` when `desired_count` is below it. Adding or
removing `autoscaling` on an existing service moves it between
`aws_ecs_service.this` and `.autoscaled`: write a `moved` block in the root
(`docs/UPGRADE-1.0.md` shows it), or the service is destroyed and created.

**Images belong to the plan.** The task definition is the deployment, so a new
image is a new `image` value in a reviewed run (a workspace variable the
pipeline sets). A pipeline that calls `update-service` behind Terraform's back
is undone by the next apply. `verify_commands.roll_back` lists revisions; with
`task_definition_skip_destroy = true` (the default) old revisions stay ACTIVE,
so a manual rollback has something to roll back to.

**Silent failures are routed.** With `sns_topic_arn`, EventBridge rules publish
failed deployments (a circuit-breaker rollback leaves the apply green), service
warnings and errors (tasks that cannot start or be placed), and scheduled or
`task` workloads that never started or exited non-zero (any container: a
sidecar killed after the essential container finishes also matches). Alarms cover CPU,
memory and, with Container Insights, running tasks below the lowest count the
workload is allowed (scheduled scale-downs included), with missing data as
breaching.

**Storage keys reach tasks at their next deployment.** Changing
`fargate_ephemeral_storage_kms_key_arn` updates the cluster in place; running
tasks keep the key they started with until their service deploys again.

## Examples

| Example | Shows |
|---|---|
| [`basic`](examples/basic) | The smallest call: one Fargate service of two tasks |
| [`complete`](examples/complete) | Every module-level input and every workload kind: an autoscaled API behind an ALB with Service Connect and EFS, a Spot queue worker, a nightly job with a DLQ, a pipeline-run migration, a service on a managed EBS volume, a daemon on EC2 capacity |

## Most-used inputs

The registry's Inputs tab is the reference; descriptions in `variables.tf` are
written to be read there.

| Name | Default | Notes |
|---|---|---|
| `name` | required | Cluster name and resource prefix; changing it replaces everything |
| `services` | `{}` | The workloads; see [Workloads](#workloads) |
| `subnet_ids`, `security_group_ids` | `[]` | Defaults for every awsvpc workload; a workload can set its own |
| `sns_topic_arn` | `""` | Where alarms and event rules publish |
| `log_retention_days` | `30` | `0` keeps logs forever |
| `log_kms_key_arn` | `""` | Customer key for the log groups |
| `container_insights` | `"enabled"` | Needed for the running-task alarm; billed per metric and per GB |
| `default_capacity` | `"on_demand"` | Preset, or an EC2 provider key |
| `ec2_capacity_providers` | `{}` | Auto Scaling groups you own, as capacity |
| `global_environment`, `global_secrets` | `{}` | For every container |
| `secrets_kms_key_arns` | `[]` | Keys of the referenced secrets |
| `execute_command` | `DEFAULT` logging | ECS Exec session key and log destination |
| `fargate_ephemeral_storage_kms_key_arn` | `""` | Reaches tasks at their next deployment |
| `required_tag_keys` | `[]` | Cost allocation keys that must be in `tags` |
| `acknowledged_checks` | `[]` | Advisory checks you have decided to live with |

## Contract outputs

| Output | For |
|---|---|
| `governance` | The posture as data: capacity per workload, what runs on Spot, unpinned images, shell access, writable root file systems, acknowledged checks |
| `network_contract` | The interface and gateway endpoints, egress and notes for the features actually used (Service Connect needs `ecs-agent` even on Fargate) |
| `kms_key_policy_requirements` | Contract v2 entries for every key in use: the log groups (the Logs service, the deployer that creates them, the execution roles that write, `log_readers`), secrets, environment files, ECS Exec (session, transcripts), Fargate ephemeral storage, managed EBS, dead-letter queues, the SNS topic. Feed them to `modules/kms` as a consumer |
| `notification_requirements` | The topic policy statements the alarms and rules need |
| `deployer_requirements` | `iam:PassRole` on exactly the module's roles, and the ECS and Application Auto Scaling service-linked roles |
| `run_task_commands` | The `aws ecs run-task` line for each `task` and `scheduled` workload |
| `run_task_requirements` | The IAM policy the pipeline that runs them needs: RunTask on those families on this cluster, PassRole on their roles |
| `verify_commands` | CloudShell checks: service state, events, stopped tasks with reasons, logs, exec, rollback, schedules |

## Limits

- **Never applied against real AWS in this repository.** Plans are tested
  against a mocked provider on aws 5.100.0 and 6.x. AWS accepting the
  requests, ECS returning container definitions without a diff, and the event
  patterns matching real events are reasoned from documentation and provider
  source, not observed.
- **ECS-native rolling deployments only.** CodeDeploy and external controllers
  are not supported, and neither are 6.x-only features (native blue/green,
  linear and canary strategies, `sigint_rollback`, S3 Files volumes), because
  the module supports both provider majors.
- **No Service Connect TLS, VPC Lattice, ECS Managed Instances or Windows-specific
  volumes (FSx).**
- **The execution role trust has no source condition.** AWS documents the
  `aws:SourceArn`/`aws:SourceAccount` scoping for task roles; for execution
  roles it is unverified here, and a wrong condition stops every task from
  starting.
- **No security groups are created.** Ingress from load balancers is the
  caller's to write.
- **Step scaling is not offered.** Target tracking (CPU, memory, ALB requests,
  any CloudWatch metric) and scheduled scaling are; build step policies on
  `service_names` if you need them.

## Versioning and support

Semantic versioning, tags `ecs-vX.Y.Z`. Breaking: removed or renamed inputs and
outputs, new required inputs, changed defaults, an update that becomes a
replacement, an address change, a raised Terraform or provider floor. A
deprecated input keeps working, with a warning in its description, for at
least one minor release before a major removes it. The previous major gets
security fixes for six months after a new major. `moved` blocks are never
deleted, so a workspace can skip versions.
Supported: Terraform 1.9 to latest; `hashicorp/aws` 5.100.0 to the newest 6.x.
[CHANGELOG.md](CHANGELOG.md), [COSTS.md](COSTS.md),
[docs/UPGRADE-1.0.md](docs/UPGRADE-1.0.md) for callers of the earlier,
unversioned `modules/ecs`.
