# terraform-aws-ecs

Amazon ECS for a regulated estate: one cluster, and every workload on it from a
single `services` map. Long-running services, daemons, scheduled jobs and
pipeline-run tasks; Fargate, Fargate Spot, EC2 and ECS Managed Instances
capacity; rolling, blue/green, linear and canary deployments with Lambda
lifecycle hooks; Service Connect, load balancers, EFS and managed EBS volumes;
autoscaling; per-workload IAM; alarms, and EventBridge rules for the failures
that leave an apply green.

**Stage:** 3.0.0 release candidate. Stable once a security review reports no
open Critical or High finding ([GOVERNANCE](../../docs/GOVERNANCE.md)).

```hcl
module "ecs" {
  source  = "app.terraform.io/<org>/ecs/aws"
  version = "~> 3.0"

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
| `hashicorp/aws` | `>= 6.57.1, < 7.0.0` | Commit the `.terraform.lock.hcl`, and run `terraform init -upgrade` if it pins anything older. The floor is the one `modules/asg-group` uses, so the two share a workspace |
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
| A capacity strategy mixing Fargate, Auto Scaling group and Managed Instances providers, more than one `base`, no positive weight | ECS rejects the strategy; it holds one kind of provider ([Managed Instances](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ManagedInstances.html)) |
| A `name` starting with `aws`, `ecs` or `fargate` when the module registers capacity providers | Providers are named `<name>-<key>`, and `CreateCapacityProvider` refuses those prefixes |
| On Managed Instances: a network mode other than `awsvpc` or `host`; a storage size outside 30-16,384 GiB | Managed Instances support neither |
| `load_balancers` on a `BLUE_GREEN`, `LINEAR` or `CANARY` service without `alternate_target_group_arn` and `production_listener_rule_arn`, or with the alternate equal to the primary; those fields on a `ROLLING` service | ECS starts the new revision behind the alternate target group and moves traffic by rewriting the production rule; without them there is nothing to move, and on a rolling service they do nothing |
| `sigint_rollback` without `wait_for_steady_state` | The provider only watches for a cancelled run while it waits for the deployment, so the flag would do nothing |
| A lifecycle hook that is not a Lambda function, has no stage or an unknown one, or details that are not JSON | `CreateService` and `UpdateService` reject them |
| Service Connect `access_logs` with `log_proxy = false`; a `test_traffic_header` on a rolling service or on a port without `app_protocol` | Access logs are written through the proxy's log configuration; header rules need an HTTP or gRPC port and a traffic-shifting deployment |
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
| Cloud Map A records on bridge or host networking; SRV without a port | Those tasks share the instance's IP, so only an SRV record carries where they listen |
| Two workloads creating the same `log_group.name`; retention on a group the module does not create | Two resources would fight over one group, or a setting would be silently ignored |

### Advisory checks

Sixteen `check` blocks warn without refusing. Each is silenced by naming it in
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
| `spot_services_keep_an_on_demand_floor` | a service is on Fargate Spot, or a `SPOT` Managed Instances provider, with no on-demand share. ECS does not fall back to on-demand |
| `shell_access_is_intended` | a workload has `enable_execute_command` |
| `task_costs_are_attributable` | a workload has `propagate_tags = "NONE"` |
| `running_task_alarms_have_data` | alarms are on and `container_insights = "disabled"`, so no running-task alarm can exist |
| `failed_schedules_are_kept` | a scheduled workload has no `dead_letter_queue_arn` |
| `shell_sessions_are_recorded` | ECS Exec is on and `execute_command.logging = "NONE"` |
| `containers_stay_on_their_side` | a container is privileged, adds capabilities, mounts a host path, or shares the host's network, pid or ipc namespace (`governance.host_access`) |
| `roles_are_not_administrators` | a workload role has `AdministratorAccess`, `IAMFullAccess`, `PowerUserAccess`, or an inline `"Action": "*"` or `"iam:*"` |
| `secrets_are_not_in_environment` | an environment variable is named like a secret (`*PASSWORD`, `*TOKEN`, `*API_KEY`...): it would be in state and in `DescribeTaskDefinition` |
| `managed_instance_volumes_are_encrypted` | Managed Instances providers exist and EBS encryption by default is off in the account and region: their data volumes are created unencrypted, because the provider has no encryption setting of its own |

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

**Capacity.** `capacity` is a preset, an `ec2_capacity_providers` key or a
`managed_instances_capacity_providers` key; `capacity_provider_strategy`
overrides it. Fargate workloads without either use `default_capacity` when
that is a preset, otherwise `on_demand`; EC2 and Managed Instances workloads
name their capacity.

| Preset | Strategy | For |
|---|---|---|
| `on_demand` | FARGATE | Anything that must not be interrupted |
| `balanced` | FARGATE base 1, then 1:3 FARGATE:FARGATE_SPOT | Services that tolerate interruption above one task |
| `spot_preferred` | 1:4 FARGATE:FARGATE_SPOT | Workers and jobs that retry |
| `spot_only` | FARGATE_SPOT | Jobs that can wait for capacity |

**Managed Instances.** An entry of `managed_instances_capacity_providers` is a
capacity provider on this cluster only; AWS chooses, launches, patches and
replaces the instances (each lives at most 14 days), and several tasks share
an instance. Services use it with `launch = "MANAGED_INSTANCES"` and the key
as `capacity`. With no `instance_requirements`, ECS picks cost-optimized
general-purpose types; `vcpu_min` above 0 narrows them by attributes, the same
fields `modules/asg-group` takes, plus accelerators. The module creates the
instance role `ecsInstanceRole-<name>` and its profile (the managed
infrastructure policy passes only roles named `ecsInstanceRole*`), or uses
`instance_profile_arn` and grants its role by ARN instead, whatever it is
called. The instances are tagged with the module's tags.

**Deployments.** `deployment.strategy` is `ROLLING` (the default), or one of
the strategies where ECS starts the new revision beside the old one and moves
traffic to it:

| Strategy | Traffic | Fields |
|---|---|---|
| `BLUE_GREEN` | All at once | `bake_time_minutes` (10): both revisions run this long after the shift, then the old one stops |
| `CANARY` | `canary_percent` (5), then the rest after `canary_bake_minutes` (10) | and `bake_time_minutes` |
| `LINEAR` | `linear_step_percent` (10) every `linear_step_bake_minutes` (6) | and `bake_time_minutes` |

With `load_balancers`, each one names the second target group
(`alternate_target_group_arn`), the production listener rule (ALB) or listener
(NLB), and optionally a test rule; ECS rewrites them with the module's
infrastructure role. With Service Connect, a `test_traffic_header` sends
matching requests to the new revision before production traffic moves. A
service with neither still deploys side by side, but nothing moves traffic.
`lifecycle_hooks` invoke Lambda functions at the stages named, and their
answer continues or rolls back the deployment; `alarm_names` roll it back too.
`sigint_rollback` (with `wait_for_steady_state`) rolls a deployment back when
the run is cancelled: in HCP Terraform, cancelling an apply sends the
interrupt. `verify_commands.deployments` lists a service's deployments and
`stop_deployment` rolls back the one in progress.

**Service Connect.** `service_connect = {}` on an image-shortcut service with
a `port` publishes that port under the service name in the cluster's
namespace. With `containers`, name the ports to publish in `expose` (keyed by
`port_mappings[*].name`); an empty `expose` makes the service a client only.
The proxy logs to the workload's log group; `access_logs` adds a line per
request there (`JSON` by default; query strings only with
`include_query_parameters`), billed as log ingestion.

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
The infrastructure role `<name>-ecs-infrastructure` exists only when something
uses it, and carries one managed policy per use (volumes, load balancers,
Managed Instances) and `lambda:InvokeFunction` on exactly the hook functions.
Bring your own role with `create = false` and `arn`.

## Services fields

Every field of a `services` entry. Empty strings and `0` mean unset unless a
row says otherwise.

**Shape and placement**

| Field | Default | Effect |
|---|---|---|
| `workload` | `"service"` | `service`, `daemon`, `scheduled` or `task` ([Workloads](#workloads)) |
| `launch` | `"FARGATE"` | `FARGATE`, `EC2` or `MANAGED_INSTANCES`; the task definition's `requiresCompatibilities` |
| `capacity`, `capacity_provider_strategy` | `""`, `[]` | Preset, EC2 or Managed Instances provider key; an explicit strategy wins. Never set on a daemon |
| `cpu`, `memory` | `256`, `512` | Task size in CPU units and MiB; Fargate pairs are validated. $0.04656 per vCPU-hour, $0.00511 per GB-hour in eu-west-2 |
| `cpu_architecture`, `operating_system_family` | `"X86_64"`, `"LINUX"` | `ARM64` is 20% cheaper on Fargate |
| `network_mode` | `"awsvpc"` | Fargate requires `awsvpc`; Managed Instances take `awsvpc` or `host` |
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
| `load_balancers` | `[]` | `container_name` and `container_port` default from the shortcut, or from a container's only port. `alternate_target_group_arn`, `production_listener_rule_arn`, `test_listener_rule_arn` for traffic-shifting strategies |
| `health_check_grace_period_seconds` | `0` | 60 when the service has a load balancer |
| `deployment.minimum_healthy_percent` | unset | 100 for a service, 0 for a daemon (the API's defaults) |
| `deployment.maximum_percent` | `200` | 100 turns AZ rebalancing off |
| `deployment.strategy` | `"ROLLING"` | `BLUE_GREEN`, `LINEAR` or `CANARY` on a service ([Deployments](#workloads)); both revisions run, and are billed, until `bake_time_minutes` after the shift |
| `deployment.bake_time_minutes`, `canary_percent`, `canary_bake_minutes`, `linear_step_percent`, `linear_step_bake_minutes` | `10`, `5`, `10`, `10`, `6` | Sent only for the strategy that uses them; the API's ranges are validated |
| `deployment.lifecycle_hooks` | `{}` | By name: `function_arn` (a Lambda function, alias or version), `stages`, `details` (JSON passed to the function) |
| `deployment.sigint_rollback` | `false` | Needs `wait_for_steady_state`; a cancelled run rolls the deployment back |
| `deployment.circuit_breaker`, `rollback` | `true`, `true` | Services only |
| `deployment.alarm_names` | `[]` | CloudWatch alarms that fail and roll back a deployment |
| `deployment.wait_for_steady_state` | `false` | The apply waits for the deployment |
| `deployment.availability_zone_rebalancing` | `true` | Sent only where ECS supports it |
| `deployment.ignore_task_definition_changes` | `false` | An external pipeline owns the running revision: Terraform still registers revisions, but never moves the service to one (see "Who deploys the image") |
| `autoscaling` | none | `min` 1, `max` required, `cpu_target` 70, `memory_target` 0, `requests_per_target` 0 with `alb_resource_label`, `custom` metrics, cooldowns 300/60, `disable_scale_in`, `schedules` with a timezone |
| `schedule` | none | `expression`, `timezone` UTC, `enabled`, `task_count` 1, `flexible_window_minutes` 0, `maximum_retry_attempts` 2, `maximum_event_age_seconds` 3600, `dead_letter_queue_arn`, `dead_letter_queue_kms_key_arn` |
| `service_connect` | none | `namespace_arn` (else the cluster's), `log_proxy` true, `access_logs` (`format` JSON or TEXT, `include_query_parameters`), `expose` keyed by port name with `discovery_name`, `dns_name`, `port`, `ingress_port_override`, timeouts, `test_traffic_header` (`name`, `value`) |
| `service_discovery` | none | `namespace_id` (the module creates the Cloud Map service, `name` defaulting to the key) or `registry_arn` (an existing one); `dns_record_type` A (awsvpc) or SRV (required for bridge and host, with `container_name`/`container_port`), `ttl` 10, `routing_policy` MULTIVALUE |
| `log_group` | created | `name` (default `/ecs/<name>/<key>`), `retention_days` (default `log_retention_days`), `kms_key_arn` (default `log_kms_key_arn` for a created group); `create = false` with `name` writes to an existing group the module does not manage, and `kms_key_arn` is then the key its owner set, so the execution role can write under it |
| `enable_execute_command` | `false` | Warned (`shell_access_is_intended`) |
| `propagate_tags` | `"SERVICE"` | `NONE` is warned for services |
| `force_delete` | `false` | Delete the service without scaling it to zero first |
| `task_role`, `execution_role` | created | `create = false` with `arn` to bring your own; `policies` (inline, by name) and `managed_policies` (by name) on created roles |
| `alarms` | on | `enabled`, `cpu_percent` and `memory_percent` (`0` is the module default), `min_running_tasks` (unset: the lowest count the workload may run; `0`: no running-task alarm) |
| `tags` | `{}` | Added to the workload's resources and tasks; `ManagedBy` and `Module` stay the module's |

## Behaviour to know about

**Every service update is a deployment.** `force_new_deployment` is always
`true`, because the provider refuses a change of `capacity_provider_strategy`
without it (`internal/service/ecs/service.go`,
`capacityProviderStrategyCustomizeDiff`, at v6.57.1). So a change between two
capacity strategies is an update, and an update to anything but tags (a grace
period, a count on a static service) also replaces the tasks, by a deployment
of the service's strategy.

**The strategy is always sent.** A service sends `strategy = "ROLLING"` too,
because `deployment_configuration` is computed: leaving it out would keep
whatever strategy was applied last.

**Capacity providers are replaced, and ECS will not delete one in use.**
`auto_scaling_group_arn` (EC2) and `capacity_option_type` (Managed Instances)
force a new capacity provider, and ECS refuses to delete one that a service
still uses. To change them, add a provider under a new key, move the services
to it, apply, then remove the old key. Other Managed Instances settings
(subnets, instance requirements, storage, monitoring) update in place
(provider source at v6.57.1: only `cluster`, `name` and
`capacity_option_type` are ForceNew).

**An autoscaled service is a different resource.** `aws_ecs_service.autoscaled`
ignores `desired_count` after creation, so an apply does not undo the scaler;
it starts at `autoscaling.min` when `desired_count` is below it. Adding or
removing `autoscaling` on an existing service moves it between
`aws_ecs_service.this` and `.autoscaled`: write a `moved` block in the root
(`docs/UPGRADE-3.0.md` shows it), or the service is destroyed and created.

**Who deploys the image.** By default the task definition is the deployment:
a new image is a new `image` value in a reviewed run (a workspace variable the
pipeline sets), and a pipeline that calls `update-service` behind Terraform's
back is undone by the next apply. With
`deployment.ignore_task_definition_changes = true` the pipeline owns the
running revision instead: Terraform registers the first revision and keeps
registering new ones when its own container settings change, but never moves
the service to them, so a changed secret or environment value in Terraform
reaches the tasks only when the pipeline next deploys.
`governance.externally_deployed` lists those services. Switching the flag on an
existing service moves it between resources: write a root `moved` block from
`aws_ecs_service.this` to `.static_ignored` (or `.autoscaled` to
`.autoscaled_ignored`). `verify_commands.deploy_latest` moves a pipeline-owned
service to its family's latest revision. `verify_commands.roll_back` lists revisions; with
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

**Cloud Map services are replaced, not updated, when `name`, `namespace_id`,
`dns_record_type` or `routing_policy` changes** (ForceNew in the provider). `force_destroy` deregisters the running instances so the replacement
goes through, and DNS for that service is empty until the tasks register again
in the new one; change those in a window. TTL is an in-place update.

**Alarms and the topic.** `alarm_actions` and `ok_actions` can point anywhere
(SNS, Lambda, incident plans); the event rules always publish to
`sns_topic_arn`. `notification_requirements` asks the topic's owner to admit
CloudWatch only when the alarms actually publish to that topic.

**Storage keys reach tasks at their next deployment.** Changing
`fargate_ephemeral_storage_kms_key_arn` updates the cluster in place; running
tasks keep the key they started with until their service deploys again.

## Examples

| Example | Shows |
|---|---|
| [`basic`](examples/basic) | The smallest call: one Fargate service of two tasks |
| [`complete`](examples/complete) | Every module-level input and every workload kind: an autoscaled API behind an ALB, released as a canary with a smoke-test hook, with Service Connect access logs and EFS, a Spot queue worker, a nightly job with a DLQ, a pipeline-run migration, a service on a managed EBS volume, a renderer on Managed Instances, a daemon on EC2 capacity |

## Most-used inputs

The registry's Inputs tab is the reference; descriptions in `variables.tf` are
written to be read there.

| Name | Default | Notes |
|---|---|---|
| `name` | required | Cluster name and resource prefix; changing it replaces everything |
| `services` | `{}` | The workloads; see [Workloads](#workloads) |
| `subnet_ids`, `security_group_ids` | `[]` | Defaults for every awsvpc workload; a workload can set its own |
| `sns_topic_arn` | `""` | Where alarms and event rules publish |
| `alarm_actions`, `ok_actions`, `alarm_period`, `alarm_evaluation_periods` | the topic, 60 s × 3 | Alarm targets beyond the topic, and the alarm window |
| `log_retention_days`, `log_kms_key_arn` | `30`, `""` | `0` keeps logs forever; a customer key for the groups the module creates |
| `container_insights` | `"enabled"` | Needed for the running-task alarm; billed per metric and per GB |
| `default_capacity` | `"on_demand"` | Preset, or an EC2, Managed Instances or external provider |
| `ec2_capacity_providers`, `external_capacity_providers` | `{}`, `[]` | Auto Scaling groups you own as capacity; Auto Scaling group providers created elsewhere, to register |
| `managed_instances_capacity_providers` | `{}` | EC2 capacity AWS runs for you; billed per instance plus a management fee (COSTS.md) |
| `global_environment`, `global_secrets`, `secrets_kms_key_arns` | `{}`, `{}`, `[]` | For every container; keys of the referenced secrets |
| `execute_command` | `DEFAULT` logging | ECS Exec session key and log destination |
| `fargate_ephemeral_storage_kms_key_arn` | `""` | Reaches tasks at their next deployment |
| `required_tag_keys` | `[]` | Cost allocation keys that must be in `tags` |
| `acknowledged_checks` | `[]` | Advisory checks you have decided to live with |

## Contract outputs

| Output | For |
|---|---|
| `governance` | The posture as data: capacity per workload, what runs on Spot, deployment strategies and hooks, Managed Instances and how their volumes are encrypted, unpinned images, shell access, writable root file systems, acknowledged checks |
| `network_contract` | The interface and gateway endpoints, egress and notes for the features actually used (Service Connect needs `ecs-agent` even on Fargate) |
| `kms_key_policy_requirements` | Contract v2 entries for every key in use: the log groups (the Logs service, the deployer that creates them, the execution roles that write, `log_readers`), secrets, environment files, ECS Exec (session, transcripts), Fargate ephemeral storage, managed EBS, dead-letter queues, the SNS topic. Feed them to `modules/kms` as a consumer |
| `notification_requirements` | The topic policy statements the alarms and rules need |
| `deployer_requirements` | `iam:PassRole` on exactly the module's roles (task, execution, infrastructure, Managed Instances instance roles), `iam:GetInstanceProfile` on supplied profiles, and the ECS and Application Auto Scaling service-linked roles |
| `run_task_commands` | The `aws ecs run-task` line for each `task` and `scheduled` workload |
| `run_task_requirements` | The IAM policy the pipeline that runs them needs: RunTask on those families on this cluster, PassRole on their roles |
| `verify_commands` | CloudShell checks: service state, events, deployments and how to roll one back, stopped tasks with reasons, logs, exec, revisions, schedules, Managed Instances providers |

## Limits

- **Never applied against real AWS in this repository.** Plans are tested
  in CI against a mocked provider on the newest 6.x; the 6.57.1 floor is not a
  CI leg (`scripts/ci_matrix.py` adds a provider leg only for a range that
  spans two majors). AWS accepting the
  requests, ECS returning container definitions without a diff, and the event
  patterns matching real events are reasoned from documentation and provider
  source, not observed. Not checked against AWS in particular: whether the
  circuit breaker acts on `BLUE_GREEN`, `LINEAR` and `CANARY` deployments (the
  API documents it for the ECS controller); who writes `awslogs` lines on
  Managed Instances, and so which role a customer log key must admit there;
  and which service the deployer passes a Managed Instances instance role to
  (the `PassManagedInstanceRoles` grant has no `iam:PassedToService`).
- **Removing the last lifecycle hook may leave it on the service.** At
  v6.57.1 the provider sends no hook list when the set is empty
  (`internal/service/ecs/service.go`, update path). Remove hooks in a release
  that keeps at least one, or check `DescribeServices` afterwards.
- **Not offered: features newer than the 6.57.1 floor.** Pause lifecycle
  hooks (6.66.0); Managed Instances capacity reservations and local storage
  (6.58.0) and auto repair (6.64.0). Also not offered: CodeDeploy and external
  deployment controllers, S3 Files volumes, Service Connect TLS, VPC Lattice,
  daemons on Managed Instances, and Windows-specific volumes (FSx).
- **The execution role trust has no source condition.** AWS documents the
  `aws:SourceArn`/`aws:SourceAccount` scoping for task roles; for execution
  roles it is unverified here, and a wrong condition stops every task from
  starting.
- **Log groups a workload only points at** (`log_group.create = false`) are
  their owner's: retention, policy, and the Logs service grant on their key.
  The module only asks that key's owner to let the writing execution roles in
  (`LogWriters<n>`), when `log_group.kms_key_arn` names it.
- **No security groups are created.** Ingress from load balancers, and the
  task groups themselves, are the caller's.
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
Supported: Terraform 1.9 to latest; `hashicorp/aws` 6.57.1 to the newest 6.x.
[CHANGELOG.md](CHANGELOG.md), [COSTS.md](COSTS.md),
[docs/UPGRADE-3.0.md](docs/UPGRADE-3.0.md) for callers of earlier versions.
