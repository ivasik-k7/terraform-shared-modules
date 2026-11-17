# Upgrading to 2.0

For workspaces on asg-group 1.x. A workspace starting fresh does not need this.

## Before the first plan

1. Upgrade the workspace to `hashicorp/aws` 6.57.1 or later; 2.x does not
   support aws 5.x.
2. If the module created a security group (`create_security_group = true`),
   declare it in the root and move it out of the module, or it is destroyed:

   ```hcl
   resource "aws_security_group" "fleet" {
     name_prefix = "<name>-" # copy name_prefix and description: changing either replaces it
     description = "Node group <name>"
     vpc_id      = var.vpc_id
   }

   moved {
     from = module.fleet.aws_security_group.this[0]
     to   = aws_security_group.fleet
   }
   ```

   Do the same for its rules (`aws_vpc_security_group_ingress_rule.this["<key>"]`
   and `aws_vpc_security_group_egress_rule.this["<key>"]`), then pass the group
   in `security_group_ids`.
3. If you used `initial_lifecycle_hooks`, set `initial = true` on each in
   `lifecycle_hooks`, and set `default_result` and `heartbeat_timeout` to what
   the group has now (2.0 sends `ABANDON` and `3600` unless told otherwise; read
   them with `aws autoscaling describe-lifecycle-hooks`). Any difference, and
   moving a hook off the group, changes `initial_lifecycle_hook`, which the
   provider treats as ForceNew: the group would be replaced.
4. If you used `iam_role_inline_policy`, give it a name in
   `instance_profile.policies` and move it:
   `module.fleet.aws_iam_role_policy.inline[0]` to `module.fleet.aws_iam_role_policy.inline["<name>"]`.

## What happens on the first plan

| Resource | What the plan does | Why |
|---|---|---|
| Launch template | New version | Tags, credit specification and metadata settings change |
| Auto Scaling group | Updated in place (same address, `aws_autoscaling_group.this[0]`); with instance refresh now on, the new template version rolls the fleet | The template version moves |
| Instance role and profile | Created, if 1.x had none | `instance_profile.create` defaults to true, with Session Manager |
| Alarms | Created, if 1.x had them off | `create_alarms` defaults to true |
| Event rules | Created, if `sns_topic_arn` is set | New |

Search the speculative plan for `must be replaced` on `aws_autoscaling_group`:
there should be none. Expect the refresh to replace every instance after the
apply; schedule the apply accordingly, or set `instance_refresh = { enabled = false }`
for the upgrade and turn it on afterwards.

## Inputs

| 1.x | 2.0 |
|---|---|
| `name` (1-64 of anything) | `name`: 1-36 letters, digits and hyphens |
| `availability_zones` | Removed; `subnet_ids` is required |
| `vpc_id`, `create_security_group`, `security_group_name`, `security_group_ingress_rules`, `security_group_egress_rules` | Removed; see step 2 |
| `security_group_ids` (additional) | `security_group_ids`, required |
| `ami = null`, `ami_ssm_parameter = null` | `""`; exactly one of the two |
| `key_name`, `user_data`, `user_data_base64`, `placement_group`, `tenancy` = `null` | `""` |
| `enable_detailed_monitoring` | `detailed_monitoring` |
| `ebs_optimized` (bool or null) | `ebs_optimized`: `""`, `"true"` or `"false"` |
| `metadata_tags_enabled` | `metadata_tags` |
| `cpu_options` (null) | `cpu_options = { core_count, threads_per_core, nested_virtualization }`, `-1`/`""` unset |
| `root_volume_size`, `_type`, `_iops`, `_throughput`, `_device_name` | `root_volume = { size_gib, type, iops, throughput, device_name }` |
| `root_volume_encrypted` | Removed: every volume is encrypted |
| `kms_key_id` (root only) | `kms_key_arn` (every volume) |
| `ebs_block_devices` (list) | `ebs_volumes`, a map keyed by device name; no per-volume `encrypted` or `kms_key_id` |
| `create_instance_profile` (default false), `instance_profile_name` | `instance_profile = { create (default true), name, ssm, policies, managed_policies }` |
| `iam_role_policies` | `instance_profile.managed_policies` (same keys, same addresses) |
| `iam_role_inline_policy` | `instance_profile.policies`, a map; see step 4 |
| `iam_permissions_boundary` | `permissions_boundary_arn` |
| `associate_public_ip_address` (null/true/false) | `public_ip` (`""`/`"assign"`/`"none"`) |
| `desired_capacity = null` | `desired_capacity = -1` |
| `default_instance_warmup = null` | `-1` |
| `wait_for_capacity_timeout = null`, `wait_for_elb_capacity = null` | `""`, `-1` |
| `default_cooldown`, `metrics_granularity`, `min_elb_capacity` | Removed |
| `spot = { ... }` (null: on-demand; `{}`: all Spot) | `purchase_options`, default all on-demand: set `on_demand_percentage_above_base_capacity` below 100 for Spot. A 1.x `spot = {}` was all Spot; to keep it, set `on_demand_percentage_above_base_capacity = 0` |
| `instance_refresh = null` (off) | `instance_refresh`, on by default; `{ enabled = false }` to keep it off |
| `warm_pool = null` | `warm_pool = { enabled = true, ... }` |
| `initial_lifecycle_hooks` (`lifecycle_transition` = `autoscaling:EC2_INSTANCE_...`) | `lifecycle_hooks` (`transition` = `LAUNCHING` or `TERMINATING`, `initial`) |
| `target_tracking_policies` (`resource_label = null`) | Same keys; `resource_label = ""`; `customized` metrics added |
| `scheduled_actions` (sizes `null`) | Sizes `-1`, times `""` |
| `create_cloudwatch_alarms` (default false) | `create_alarms` (default true) |
| `alarm_cpu_threshold` | `alarm_cpu_percent` |
| `alarm_min_in_service = null` | `-1`: the lowest count the group may run, scheduled actions included |

## Outputs

| 1.x | 2.0 |
|---|---|
| `security_group_id`, `security_group_ids` | Removed |
| Every other output | Unchanged |

`moved` blocks are never deleted, so a workspace can skip versions.
