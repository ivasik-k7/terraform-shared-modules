# Changelog: ecs

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `ecs-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [3.0.0] - unreleased

A rewrite. Callers of earlier versions follow
[docs/UPGRADE-3.0.md](docs/UPGRADE-3.0.md).

### Added

- One `services` map for every workload: `service`, `daemon` (EC2),
  `scheduled` (EventBridge Scheduler, own schedule group, retries and DLQ) and
  `task` (definition only, with `output.run_task_commands`).
- An image shortcut (`image`, `port`, `command`, `environment`, `secrets`,
  `health_check`) and full container definitions in `containers`, rendered
  without empty fields so plans do not show a permanent diff.
- Capacity presets (`on_demand`, `balanced`, `spot_preferred`, `spot_only`),
  EC2 capacity providers by key, explicit strategies, `default_capacity`.
- Per-workload task and execution roles; secrets scoped to exactly the
  workload's ARNs, KMS only through Secrets Manager and SSM; ECS Exec and EFS
  permissions derived from the configuration; bring-your-own roles.
- Service Connect, Cloud Map registries, load balancers with defaults from the
  image shortcut, managed EBS volumes with an infrastructure role, EFS with TLS
  and IAM authorisation by default.
- Autoscaling on CPU, memory, ALB requests and any CloudWatch metric, plus
  scheduled scaling with time zones.
- Alarms (CPU, memory, running tasks), and EventBridge rules for failed
  deployments, impaired services and failed scheduled or `task` workloads.
- Fargate ephemeral storage and managed storage keys, ECS Exec session key and
  log destination, `required_tag_keys`, `create`.
- Contract outputs: `governance`, `network_contract`,
  `kms_key_policy_requirements` (contract v2, including the CloudWatch Logs
  caller grants), `notification_requirements`, `deployer_requirements`,
  `run_task_requirements`, `verify_commands`.
- S3 grants scoped by `aws:ResourceAccount` (`trusted_s3_account_ids`); keys
  for environment files, ECS Exec transcripts and schedule dead-letter queues.
- Fifteen advisory checks and `acknowledged_checks`.
- `deployment.ignore_task_definition_changes`: an external pipeline owns the
  running revision (`aws_ecs_service.static_ignored` and
  `.autoscaled_ignored`, held identical to the other two by
  `tests/service_parity.py`).
- Per-workload `service_discovery` (creating the Cloud Map service, or using
  one; A or SRV) and `log_group` (own name, retention and key, or an existing
  group); log-key grants and contract entries per key.
- `external_capacity_providers`; `alarm_actions`, `ok_actions`,
  `alarm_period`, `alarm_evaluation_periods`, `alarms.min_running_tasks`.
- `verify_commands.deploy_latest` for pipeline-owned services.
- A `moved` block from `aws_ecs_service.static` to `.this`.

### Changed

- **BREAKING** Terraform `>= 1.9.0` (was `>= 1.3.0`), `hashicorp/aws`
  `>= 5.100.0, < 7.0.0` (was `>= 5.0`, unbounded).
- **BREAKING** `cluster_name` is now `name`; families are `<name>-<key>`
  instead of `task_definition_family`; roles are `<name>-<key>-task` and
  `<name>-<key>-exec`. Roles and task definitions are replaced on upgrade.
- **BREAKING** One execution role per workload instead of one shared role.
- **BREAKING** Autoscaled services are `aws_ecs_service.autoscaled[<key>]`
  and ignore `desired_count` after creation.
- **BREAKING** Defaults: circuit breaker and rollback on; `propagate_tags =
  "SERVICE"` with ECS managed tags; `force_new_deployment = true`; log
  retention 30 days (was 7); superseded task definitions kept ACTIVE.
- **BREAKING** The default capacity is on-demand Fargate (was FARGATE base 1,
  then 1:4 FARGATE:FARGATE_SPOT), and every service sends its strategy.
  Services that relied on the old default move off Spot, and cost more. To
  keep it: `capacity_provider_strategy = [{ capacity_provider = "FARGATE",
  base = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 4 }]`.
- **BREAKING** EFS volumes default to IAM authorisation (was `DISABLED`); a
  file system policy that does not allow the task role then refuses the mount.
  Set `iam_authorization = false` to keep the old behaviour.
- **BREAKING** Docker volumes default to `autoprovision = false` (was `true`).
- **BREAKING** On aws 5.x, a service the old module created with
  `launch_type` is replaced on upgrade; see the upgrade guide.

### Removed

- **BREAKING** `auto_scaling_policies` (replaced by `services[*].autoscaling`;
  step scaling is not offered), `capacity_providers` (replaced by
  `ec2_capacity_providers` and presets), `cluster_configuration`,
  `enable_container_insights` (now `container_insights`),
  `task_execution_role_arn`, `create_task_execution_role`,
  `task_execution_role_policies`, `task_role_policies`,
  `create_cloudwatch_log_groups`, `log_kms_key_id`, and the outputs that
  exposed them. The mapping is in the upgrade guide.
