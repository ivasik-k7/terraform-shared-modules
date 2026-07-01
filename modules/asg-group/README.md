# Auto Scaling Group

A universal Amazon EC2 **Auto Scaling Group** module — launch template + ASG +
optional instance IAM + optional security group + scaling + monitoring. It is
**workload-agnostic**: you drive the AMI, user-data, IAM policies, tags, and
scaling to fit whatever runs on the fleet.

Use it for ECS EC2 capacity, a web/app fleet behind an ALB, batch workers, or
self-managed Kubernetes nodes — anything that is "a group of EC2 instances that
scales." It outputs the **ASG ARN**, so consumers like the `ecs-orchestrator`
capacity providers can reference it directly.

> Not a NAT/router fleet: `source_dest_check` can't be set via a launch template,
> so forwarding appliances need a different pattern (a lifecycle hook or the
> dedicated `ec2` module).

> No ECS coupling is baked in. ECS is just one consumer — see *ECS compatibility*
> below for the four generic knobs that make the ASG ECS-ready.

## Design principles

- **Universal, not opinionated about the workload.** AMI, `user_data`, IAM
  policies, and tags are all caller-supplied. The module builds the *fleet*; what
  runs on it is your business.
- **Secure by default.** IMDSv2 enforced, encrypted root (and extra) volumes, no
  inbound on the managed SG, no IAM role unless you ask for one.
- **Comprehensive.** Mixed on-demand + Spot, target-tracking + scheduled scaling,
  instance refresh, warm pools, lifecycle hooks, ALB/NLB target-group
  registration, ASG metrics, and CloudWatch alarms — all optional.
- **Stable & composable.** A single `create` toggle, keyed maps for collections,
  `ignore_changes = [desired_capacity]` so an autoscaler/capacity provider owns
  the live count without fighting Terraform.

## Secure defaults

- **IMDSv2 enforced** (`http_tokens = required`); set `metadata_hop_limit = 2` for
  containerized workloads that reach IMDS through the host.
- **Encrypted root volume** (gp3) and encrypted `ebs_block_devices` by default.
- **Managed SG ships zero inbound** (egress allow-all so hosts reach repos/SSM).
- **No implicit default SG.** A security group is required — pass
  `security_group_ids` or set `create_security_group = true`. The plan **fails**
  rather than letting instances fall back to the permissive VPC default SG.
- **No IAM role unless requested** — `create_instance_profile = false` by default;
  attach exactly the policies you need via `iam_role_policies`.
- **ASG group metrics on** by default (free, 1-minute) so the fleet is observable.
- **Egress is allow-all by default** (so hosts reach package repos / SSM / ECR).
  To lock it down, override `security_group_egress_rules` (e.g. 443 to your VPC
  endpoints' prefix list).

## Operational notes

- **`desired_capacity` is write-once.** Changes are ignored after create
  (`ignore_changes`) so an autoscaler / ECS capacity provider / scheduled action
  owns the live count. For a static fleet, control size with `min_size`/`max_size`
  or `scheduled_actions` — editing `desired_capacity` later is a no-op.
- **Spot defaults to 100% Spot.** Opting into `spot` with no other settings means
  the whole fleet can be reclaimed at once — set `on_demand_base_capacity >= 1`
  for an always-on baseline, and list several `instance_types` for Spot depth.
- **Public IPs / placement.** Set `associate_public_ip_address` to force it via a
  network interface; otherwise the subnet's `map_public_ip_on_launch` decides.
  Use `subnet_ids` **or** `availability_zones`, never both.

## Quick start (generic fleet)

```hcl
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "fleet" {
  source = "../../modules/asg-group"

  name              = "workers"
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  subnet_ids        = data.aws_subnets.default.ids

  # a security group is required (fail-closed): create one or pass your own
  create_security_group = true
  vpc_id                = data.aws_vpc.default.id

  instance_type = "t3.medium"
  min_size      = 2
  max_size      = 10
}
```

## Examples

| #   | Scenario          | Shows                                                                           |
| --- | ----------------- | ------------------------------------------------------------------------------- |
| 1   | Web fleet + ALB   | SSM AMI, ALB target-group registration, CPU + request-count tracking, schedule, alarms |
| 2   | Spot mixed fleet  | mixed on-demand + Spot across instance types                                     |
| 3   | ECS capacity      | the generic knobs that make the ASG an ECS capacity provider                     |

Runnable: [`examples/asg-group`](../../examples/asg-group) (web fleet) and
[`examples/ecs-orchestrator-capacity-provider`](../../examples/ecs-orchestrator-capacity-provider)
(ECS). The key snippets are inlined below.

### 1. Web fleet behind an ALB (target tracking + schedule + alarms)

```hcl
module "fleet" {
  source = "../../modules/asg-group"

  name              = "web-fleet"
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  subnet_ids        = var.private_subnet_ids
  security_group_ids = [aws_security_group.web.id]

  instance_type = "t3.small"
  min_size      = 2
  max_size      = 12

  create_instance_profile = true
  iam_role_policies = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  user_data = <<-EOT
    #!/bin/bash
    dnf install -y nginx
    systemctl enable --now nginx
  EOT

  # register with the ALB and let ELB health replace bad hosts
  target_group_arns = [module.alb.target_group_arns["web"]]
  health_check_type = "ELB"

  target_tracking_policies = {
    cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 55 }
    reqs = {
      predefined_metric_type = "ALBRequestCountPerTarget"
      target_value           = 1000
      resource_label         = "${module.alb.arn_suffix}/${module.alb.target_group_arn_suffixes["web"]}"
    }
  }

  scheduled_actions = {
    business_hours = { recurrence = "0 8 * * MON-FRI", min_size = 4 }
    off_hours      = { recurrence = "0 20 * * *", min_size = 2 }
  }

  instance_refresh         = { min_healthy_percentage = 90 }
  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]
}
```

### 2. Spot mixed-instances fleet

```hcl
module "batch" {
  source = "../../modules/asg-group"

  name              = "batch"
  ami_ssm_parameter = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
  subnet_ids        = var.private_subnet_ids

  instance_type  = "c6i.large"
  instance_types = ["c6i.large", "c6a.large", "c5.large"] # diversify for spot depth
  min_size       = 0
  max_size       = 50

  spot = {
    on_demand_base_capacity                  = 1  # one always-on host
    on_demand_percentage_above_base_capacity = 0  # the rest all spot
  }
  # capacity_rebalance is forced on automatically when spot is set
}
```

### 3. ECS capacity (compatibility via generic knobs)

The module has no ECS code. You make the ASG an ECS capacity provider with four
plain inputs, then hand the ARN to `ecs-orchestrator`:

```hcl
module "nodes" {
  source = "../../modules/asg-group"

  name              = "platform-cp-nodes"
  ami_ssm_parameter = "/aws/service/ecs/optimized-ami/amazon-linux-2023/recommended/image_id"
  subnet_ids        = var.private_subnet_ids
  vpc_id            = var.vpc_id

  metadata_hop_limit = 2 # containers reach IMDS through the host

  user_data = "#!/bin/bash\necho ECS_CLUSTER=platform-cp >> /etc/ecs/ecs.config\n"

  create_instance_profile = true
  iam_role_policies = {
    ecs = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
  }
  create_security_group = true

  protect_from_scale_in  = true                       # for managed termination protection
  autoscaling_group_tags = { AmazonECSManaged = "" }  # so the capacity provider claims it
}

module "ecs" {
  source       = "../../modules/ecs-orchestrator"
  cluster_name = "platform-cp"
  ec2_capacity_providers = {
    ec2 = {
      auto_scaling_group_arn         = module.nodes.autoscaling_group_arn
      managed_termination_protection = "ENABLED" # safe: protect_from_scale_in above
    }
  }
  # services use capacity_provider_strategy (NOT launch_type) + requires_compatibilities ["EC2"]
}
```

The four ECS-enabling knobs: `user_data` (join the cluster), `iam_role_policies`
(agent permissions), `autoscaling_group_tags = { AmazonECSManaged = "" }`,
`protect_from_scale_in = true`.

---

# Inputs

### General

| Name                     | Description                                                                 | Type          | Default | Required |
| ------------------------ | --------------------------------------------------------------------------- | ------------- | ------- | :------: |
| `name`                   | Name prefix for the LT, ASG, IAM role, and SG. 1–200 chars.                 | `string`      | n/a     | **yes**  |
| `create`                 | Master switch. When `false` nothing is created.                             | `bool`        | `true`  |    no    |
| `tags`                   | Tags on every resource, propagated to instances.                            | `map(string)` | `{}`    |    no    |
| `autoscaling_group_tags` | Extra ASG-only tags (e.g. `{ AmazonECSManaged = "" }`), propagated.         | `map(string)` | `{}`    |    no    |

### Placement & image

| Name                 | Description                                                              | Type           | Default       | Required |
| -------------------- | ---------------------------------------------------------------------- | -------------- | ------------- | :------: |
| `subnet_ids`         | Subnets the ASG launches into (`vpc_zone_identifier`).                  | `list(string)` | `[]`          |    no    |
| `vpc_id`             | VPC for the managed SG. Required when `create_security_group = true`.   | `string`       | `null`        |    no    |
| `availability_zones` | AZs for the ASG (usually leave null; subnets decide).                   | `list(string)` | `null`        |    no    |
| `ami`                | AMI ID. One of `ami`/`ami_ssm_parameter` is required.                   | `string`       | `null`        |    no    |
| `ami_ssm_parameter`  | SSM parameter resolving to an AMI ID. Used when `ami` is null.          | `string`       | `null`        |    no    |
| `instance_type`      | Instance type (single-type, or first override with `spot`).            | `string`       | `t3.medium`   |    no    |
| `instance_types`     | Instance types for a mixed-instances policy. Empty = `[instance_type]`. | `list(string)` | `[]`          |    no    |
| `instance_weights`   | Per-type `weighted_capacity` for the mixed policy, e.g. `{ "m6i.2xlarge" = 4 }`. | `map(number)` | `{}`     |    no    |
| `associate_public_ip_address` | Force public-IP on/off via a network interface. Null = subnet decides. | `bool`  | `null`        |    no    |
| `key_name`           | EC2 key pair. Prefer SSM Session Manager.                              | `string`       | `null`        |    no    |

### Instance config

| Name                    | Description                                                          | Type     | Default      | Required |
| ----------------------- | ------------------------------------------------------------------ | -------- | ------------ | :------: |
| `user_data`             | Plain-text user data (module base64-encodes it). Sensitive.        | `string` | `null`       |    no    |
| `user_data_base64`      | Pre-encoded user data. Conflicts with `user_data`. Sensitive.      | `string` | `null`       |    no    |
| `enable_detailed_monitoring` | Detailed (1-minute) EC2 monitoring (extra cost).             | `bool`   | `false`      |    no    |
| `ebs_optimized`         | EBS-optimized. Null = instance-type default.                       | `bool`   | `null`       |    no    |
| `metadata_hop_limit`    | IMDS hop limit (1–64). Use 2 for containers.                       | `number` | `1`          |    no    |
| `metadata_tags_enabled` | Expose instance tags via IMDS.                                     | `bool`   | `false`      |    no    |
| `placement_group`       | Placement group name.                                              | `string` | `null`       |    no    |
| `tenancy`               | `default` / `dedicated` / `host`.                                  | `string` | `null`       |    no    |
| `cpu_options`           | `{ core_count, threads_per_core }` (1 disables hyperthreading).    | `object` | `null`       |    no    |

### Storage

| Name                      | Description                                                | Type           | Default      | Required |
| ------------------------- | --------------------------------------------------------- | -------------- | ------------ | :------: |
| `root_volume_size`        | Root volume size (GiB).                                   | `number`       | `30`         |    no    |
| `root_volume_type`        | gp2/gp3/io1/io2.                                          | `string`       | `gp3`        |    no    |
| `root_volume_iops`        | Root IOPS (io1/io2/gp3).                                  | `number`       | `null`       |    no    |
| `root_volume_throughput`  | Root throughput MiB/s (gp3).                             | `number`       | `null`       |    no    |
| `root_volume_encrypted`   | Encrypt root volume.                                      | `bool`         | `true`       |    no    |
| `root_volume_device_name` | Root device name (`/dev/xvda` AL, `/dev/sda1` Ubuntu).   | `string`       | `/dev/xvda`  |    no    |
| `kms_key_id`              | KMS key ARN for volume encryption.                       | `string`       | `null`       |    no    |
| `ebs_block_devices`       | Additional volumes baked into the LT (encrypted).        | `list(object)` | `[]`         |    no    |

`ebs_block_devices[*]`: `device_name` (req), `volume_size=8`, `volume_type="gp3"`, `iops`, `throughput`, `encrypted=true`, `kms_key_id`, `snapshot_id`, `delete_on_termination=true`.

### IAM (optional)

| Name                       | Description                                                       | Type          | Default | Required |
| -------------------------- | ---------------------------------------------------------------- | ------------- | ------- | :------: |
| `create_instance_profile`  | Create instance role + profile. Ignored if a profile is given.   | `bool`        | `false` |    no    |
| `instance_profile_name`    | Existing instance profile to use. Overrides the create flag.     | `string`      | `null`  |    no    |
| `iam_role_policies`         | Managed policy ARNs to attach, keyed by name.                    | `map(string)` | `{}`    |    no    |
| `iam_role_inline_policy`   | Inline policy JSON for the created role.                          | `string`      | `null`  |    no    |
| `iam_permissions_boundary` | Permissions boundary ARN for the created role.                   | `string`      | `null`  |    no    |

### Security group (optional)

| Name                           | Description                                       | Type          | Default   | Required |
| ------------------------------ | ------------------------------------------------- | ------------- | --------- | :------: |
| `create_security_group`        | Create a dedicated SG.                            | `bool`        | `false`   |    no    |
| `security_group_ids`           | Additional SGs to attach.                         | `list(string)`| `[]`      |    no    |
| `security_group_name`          | Name prefix (defaults to `name`).                 | `string`      | `null`    |    no    |
| `security_group_ingress_rules` | Ingress rules (keyed map). Empty by default.      | `map(object)` | `{}`      |    no    |
| `security_group_egress_rules`  | Egress rules (keyed map). Allow-all by default.   | `map(object)` | allow-all |    no    |

Each rule: `{ from_port, to_port, ip_protocol, cidr_ipv4, cidr_ipv6, referenced_security_group_id, prefix_list_id, description }`.

### Capacity & health

| Name                        | Description                                                              | Type           | Default       | Required |
| --------------------------- | ---------------------------------------------------------------------- | -------------- | ------------- | :------: |
| `min_size` / `max_size`     | ASG bounds (`max_size >= min_size`).                                    | `number`       | `1` / `3`     |    no    |
| `desired_capacity`          | Initial desired count. **Write-once** — ignored after create (see Operational notes). | `number` | `null`   |    no    |
| `protect_from_scale_in`     | Protect instances from scale-in (needed for ECS managed termination).  | `bool`         | `false`       |    no    |
| `capacity_rebalance`        | Proactive Spot replacement. Forced on with `spot`.                     | `bool`         | `false`       |    no    |
| `health_check_type`         | `EC2` or `ELB`.                                                         | `string`       | `EC2`         |    no    |
| `health_check_grace_period` | Grace seconds before health checks.                                     | `number`       | `300`         |    no    |
| `default_cooldown`          | Cooldown between scaling activities.                                    | `number`       | `null`        |    no    |
| `default_instance_warmup`   | Warmup before an instance counts toward metrics.                        | `number`       | `null`        |    no    |
| `termination_policies`      | e.g. `["OldestInstance"]`.                                              | `list(string)` | `["Default"]` |    no    |
| `target_group_arns`         | ALB/NLB target groups to register with.                                | `list(string)` | `[]`          |    no    |
| `suspended_processes`       | ASG processes to suspend (e.g. `AZRebalance`).                         | `list(string)` | `[]`          |    no    |
| `enabled_metrics`           | ASG group metrics to collect (free).                                    | `list(string)` | all Group*    |    no    |
| `metrics_granularity`       | Granularity of collected metrics (only `1Minute`).                      | `string`       | `1Minute`     |    no    |
| `wait_for_capacity_timeout` | How long TF waits for healthy capacity (`"0"` to skip).                 | `string`       | `null`        |    no    |
| `min_elb_capacity`          | Wait for N healthy ELB/target-group instances on create.               | `number`       | `null`        |    no    |
| `wait_for_elb_capacity`     | Like `min_elb_capacity`, enforced on create **and** update.            | `number`       | `null`        |    no    |

### Spot, refresh, warm pool, lifecycle hooks

- **`spot`** — `{ on_demand_base_capacity=0, on_demand_percentage_above_base_capacity=0, allocation_strategy="price-capacity-optimized", spot_max_price, spot_instance_pools }`. Null = 100% on-demand single type. `spot_instance_pools` is only valid with `allocation_strategy = "lowest-price"`. ⚠️ defaults = 100% Spot — set `on_demand_base_capacity >= 1` for a baseline.
- **`instance_refresh`** — `{ strategy="Rolling", min_healthy_percentage=90, max_healthy_percentage, instance_warmup, auto_rollback }`. Null = changes apply to new instances only.
- **`warm_pool`** — `{ pool_state="Stopped", min_size=0, max_group_prepared_capacity }`. Null disables.
- **`initial_lifecycle_hooks`** — keyed map: `{ lifecycle_transition (req), default_result, heartbeat_timeout, notification_target_arn, role_arn, notification_metadata }`.

### Scaling policies

- **`target_tracking_policies`** — keyed map: `{ predefined_metric_type (req), target_value (req), resource_label, disable_scale_in=false, estimated_instance_warmup }`. Metric ∈ {`ASGAverageCPUUtilization`, `ASGAverageNetworkIn`, `ASGAverageNetworkOut`, `ALBRequestCountPerTarget`}; the ALB one requires `resource_label`.
- **`scheduled_actions`** — keyed map: `{ min_size, max_size, desired_capacity, recurrence (cron), start_time, end_time, time_zone }`. Omit a size field to leave it unchanged.

### CloudWatch alarms (optional)

| Name                       | Description                                                  | Type           | Default | Required |
| -------------------------- | ------------------------------------------------------------ | -------------- | ------- | :------: |
| `create_cloudwatch_alarms` | High-CPU (across the group) + low in-service-instance alarms.| `bool`         | `false` |    no    |
| `alarm_cpu_threshold`      | Average CPU (%) for the high-CPU alarm.                       | `number`       | `85`    |    no    |
| `alarm_min_in_service`     | Low-in-service threshold. Null = `min_size`.                  | `number`       | `null`  |    no    |
| `alarm_evaluation_periods` | Evaluation periods.                                          | `number`       | `3`     |    no    |
| `alarm_period`             | Period (seconds).                                            | `number`       | `60`    |    no    |
| `alarm_actions`            | ARNs notified on ALARM.                                       | `list(string)` | `[]`    |    no    |
| `ok_actions`               | ARNs notified on OK.                                          | `list(string)` | `[]`    |    no    |

---

# Outputs

| Name                            | Description                                                              |
| ------------------------------- | ---------------------------------------------------------------------- |
| `autoscaling_group_arn`         | ASG ARN — pass to `ecs-orchestrator`'s `ec2_capacity_providers`, or any consumer. |
| `autoscaling_group_name`        | ASG name.                                                              |
| `autoscaling_group_id`          | ASG id.                                                                |
| `launch_template_id`            | Launch template id.                                                    |
| `launch_template_latest_version`| Latest LT version.                                                     |
| `iam_role_arn` / `iam_role_name`| Created instance role (null when not created).                        |
| `instance_profile_name`         | Instance profile attached (created or provided).                       |
| `instance_profile_arn`          | Created instance profile ARN (null when not created).                 |
| `security_group_id`             | Created SG id (null when not created).                                |
| `security_group_ids`            | All SG IDs attached (created + provided).                             |
| `target_tracking_policy_arns`   | Map: policy key → scaling policy ARN.                                 |
| `cloudwatch_alarm_names`        | Names of created alarms (empty when disabled).                        |

---

# ECS compatibility

This module is intentionally ECS-agnostic. To use the ASG as an ECS capacity
provider, supply four generic inputs and pass the ARN to `ecs-orchestrator`:

| Need | Input |
|------|-------|
| Host joins the cluster | `user_data = "#!/bin/bash\necho ECS_CLUSTER=<name> >> /etc/ecs/ecs.config\n"` |
| Agent permissions | `iam_role_policies = { ecs = ".../AmazonEC2ContainerServiceforEC2Role" }` (+ `create_instance_profile = true`) |
| Capacity provider can claim the ASG | `autoscaling_group_tags = { AmazonECSManaged = "" }` |
| Managed termination protection is safe | `protect_from_scale_in = true` |

Then: `ec2_capacity_providers = { ec2 = { auto_scaling_group_arn = module.nodes.autoscaling_group_arn, managed_termination_protection = "ENABLED" } }`. Services must use `capacity_provider_strategy` (not `launch_type`) and include `"EC2"` in `requires_compatibilities`.

---

# Testing

Two offline suites — fully mocked, no AWS credentials, no billable resources:

```bash
cd modules/asg-group
terraform init -backend=false
terraform fmt -check -recursive
terraform validate
terraform test                                        # all suites
terraform test -filter=tests/asg_group.tftest.hcl    # plan-level
terraform test -filter=tests/apply.tftest.hcl         # mocked-provider apply
```

- **`tests/asg_group.tftest.hcl`** — plan-level: `basic_on_demand` (minimal,
  no IAM/SG), `comprehensive` (IAM + SG + extra EBS + target tracking + schedule
  + alarms), `alb_request_tracking`, `ami_from_ssm` (`override_data`),
  `spot_mixed`, `ecs_compatible` (the four ECS knobs), `create_false`. Each
  guardrail has a paired `expect_failures` run: `max_below_min`, `sg_without_vpc`,
  `invalid_root_volume_type`, `invalid_ami`, `alb_tracking_without_label`,
  `invalid_spot_percentage`, `user_data_conflict`.
- **`tests/apply.tftest.hcl`** — `command = apply` against a mocked provider:
  `full_apply` (spot mixed + IAM + SG + extra EBS + refresh + tracking + alarms)
  and `on_demand_minimal_apply`.

> **Scope of the mocks.** These prove schema, wiring, plan logic, and the
> dynamic-block selection (on-demand vs mixed). They do **not** call the real
> EC2/Auto Scaling APIs — a live `terraform apply` against a sandbox account is
> the final gate.
