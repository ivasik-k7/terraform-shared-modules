# Upgrading to 1.0

For workspaces that call the earlier, unversioned `modules/ecs` (by path, at
commit `bbbc35c` or later). A workspace starting fresh does not need this.

## What happens on the first plan

| Resource | What the plan does | Why |
|---|---|---|
| Cluster, cluster capacity providers, EC2 capacity providers | Moved by the module's `moved` blocks; updated in place | Addresses gained `[0]` or were renamed |
| Log groups `/ecs/<cluster>/<service>` | Updated in place (retention, tags) | Same address and name |
| Task definitions | New revision per service | The family becomes `<name>-<key>` and the container definitions are rendered differently |
| Task roles | Replaced | Named `<name>-<key>-task` |
| Shared execution role | Destroyed; one `<name>-<key>-exec` per service created | Each workload reads only its own secrets |
| Services without autoscaling | Updated in place: a rolling deployment to the new revision, except a `launch_type` service on aws 5.x (below) | Same address, `aws_ecs_service.this[<key>]` |
| Services with autoscaling | **Destroyed and created unless you add the `moved` block below** | They are now `aws_ecs_service.autoscaled[<key>]` |
| Scaling targets and policies | Replaced, unless you move the targets | Keyed by service instead of by policy name |
| Step-scaling policies and their alarms | Destroyed | Step scaling is not offered |

Search the speculative plan for `must be replaced` and `will be destroyed` on
`aws_ecs_service`: there should be none, with one exception below.

**A service the old module created with `launch_type` is replaced on aws 5.x.**
The old module sent `launch_type` when a service had no
`capacity_provider_strategy`; this one always sends a strategy. At 5.100.0 the
provider forces replacement when a strategy goes from empty to set, even with
`force_new_deployment` (`internal/service/ecs/service.go`,
`capacityProviderStrategyCustomizeDiff`), and a fixed service name means the
old service is deleted before the new one exists. Either upgrade the workspace
to aws 6.x first, where the change is an update, or switch each such service
out of band before the plan:

```
aws ecs update-service --cluster <name> --service <key> \
  --capacity-provider-strategy capacityProvider=FARGATE,weight=1,base=0 --force-new-deployment
```

then let the next plan refresh it.

## Moves only you can write

Service keys are yours, so these go in the calling root, next to the module
call. One per autoscaled service:

```hcl
moved {
  from = module.ecs.aws_ecs_service.this["api"]
  to   = module.ecs.aws_ecs_service.autoscaled["api"]
}

# The old target was keyed by the auto_scaling_policies key.
moved {
  from = module.ecs.aws_appautoscaling_target.this["api-scaling"]
  to   = module.ecs.aws_appautoscaling_target.this["api"]
}
```

`moved` blocks are never deleted, so a workspace can skip versions.

## Inputs

| Before | Now |
|---|---|
| `cluster_name` | `name`: lowercase letters, digits and hyphens, 2-31 characters; it also prefixes roles, alarms and the schedule group. A current name outside that (capitals, underscores, longer) cannot be kept: the cluster and every service in it are replaced, so rename in a window |
| `enable_container_insights = true` | `container_insights = "enabled"` (or `"enhanced"`, `"disabled"`) |
| `cluster_configuration.enable_execute_command`, `.kms_key_id`, `.log_configuration` | `execute_command = { kms_key_arn, logging, log_group_name, s3_bucket_name, s3_key_prefix }`; turn exec on per service with `enable_execute_command` |
| `capacity_providers` with `type = "FARGATE"`/`"FARGATE_SPOT"` | Always registered; the default strategy is `default_capacity` (a preset). **The old default, FARGATE base 1 then 1:4 Spot, is not a preset**: services that relied on it move to on-demand unless they set `capacity_provider_strategy = [{ capacity_provider = "FARGATE", base = 1 }, { capacity_provider = "FARGATE_SPOT", weight = 4 }]` |
| `capacity_providers` with `type = "EC2"` | `ec2_capacity_providers`, same keys, so the `moved` block keeps them |
| `services[*].task_definition_family` | Removed: the family is `<name>-<key>` |
| `services[*].task_cpu`, `task_memory` (strings) | `cpu`, `memory` (numbers, validated against Fargate's sizes) |
| `services[*].requires_compatibilities`, `launch_type` | `launch = "FARGATE"` or `"EC2"`; the service always sends a capacity strategy |
| `services[*].container_definitions` (list) | `containers` (map keyed by container name), or `image` for one container |
| container `environment` (list of `{ name, value }`) | `environment` map; the same for `secrets` (`name => arn`, and only ARNs: a name or partial name is refused) |
| container `depends_on` (list of `{ container_name, condition }`) | `depends_on` map `container => condition` |
| container `log_configuration` | `log_driver`, `log_options`, `log_secret_options`; the default is still `awslogs` to `/ecs/<name>/<key>` |
| `services[*].volumes` (list) | `volumes` map keyed by name: `efs_volume_configuration` becomes `efs` (`transit_encryption` a bool, `authorization_config.iam` becomes `iam_authorization`, now default `true`; `transit_encryption_port` removed), `docker_volume_configuration` becomes `docker` (`autoprovision` now default `false`) |
| `services[*].network_configuration` | `subnet_ids`, `security_group_ids`, `assign_public_ip` (module-level defaults available) |
| `services[*].load_balancers` | Same, `container_name`/`container_port` optional with the image shortcut |
| `services[*].service_registries` | `service_registry_arn`. `port`, `container_name` and `container_port` are not supported, so Cloud Map services with SRV records cannot be expressed: keep such services outside the module |
| `services[*].deployment_configuration` | `deployment = { minimum_healthy_percent, maximum_percent, circuit_breaker, rollback, alarm_names }` |
| `services[*].wait_for_steady_state` | `deployment.wait_for_steady_state` |
| `services[*].scheduling_strategy = "DAEMON"` | `workload = "daemon"` |
| `services[*].force_new_deployment` | Removed: always on (see README, "Every service update is a deployment") |
| `auto_scaling_policies[*]` target tracking | `services[*].autoscaling = { min, max, cpu_target, memory_target, requests_per_target, custom }` |
| `auto_scaling_policies[*].scheduled_actions` | `services[*].autoscaling.schedules` |
| `auto_scaling_policies[*].step_scaling_policies` | Removed. Build step policies outside the module on `output.service_names` |
| `task_execution_role_arn`, `create_task_execution_role` | `services[*].execution_role = { create = false, arn }` |
| `task_execution_role_policies` | `services[*].execution_role.managed_policies` (a map) |
| `task_role_policies[<service>]` | `services[*].task_role.managed_policies` (a map), or inline `task_role.policies` |
| `create_cloudwatch_log_groups` | Removed: every workload has a log group |
| `log_retention_in_days` (default 7) | `log_retention_days` (default 30) |
| `log_kms_key_id` | `log_kms_key_arn` |

## Outputs

| Before | Now |
|---|---|
| `cluster_id` | `cluster_arn` (the cluster's ID is its ARN) |
| `capacity_provider_arns`, `capacity_provider_ids` | `capacity_provider_names` |
| `service_ids`, `service_arns` | `service_arns` (the old one returned IDs, which are ARNs) |
| `task_definition_revisions` | `task_definition_arns` (the revision is the ARN's suffix) |
| `task_execution_role_arn`, `task_execution_role_name` | `execution_role_arns` (one per workload) |
| `autoscaling_target_ids`, `autoscaling_policy_arns`, `autoscaling_step_policy_arns` | Removed |
| `summary` | Removed; `governance` carries the posture |

## In HCP Terraform

1. Raise the workspace's Terraform version to 1.9 or later, and let the lock
   file move to `hashicorp/aws` 5.100.0 or later.
2. Change the call to the inputs above and add the root `moved` blocks.
3. Open a pull request; read the speculative plan for replacements of
   `aws_ecs_service` (none, once `launch_type` services are dealt with) and for
   the role and task definition replacements listed above.
4. Apply in a window: every service rolls to a new revision with new roles.
