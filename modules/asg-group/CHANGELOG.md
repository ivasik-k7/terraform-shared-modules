# Changelog: asg-group

All notable changes to this module. The format is
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the module follows
[semantic versioning](https://semver.org): see "Versioning and support" in
[README.md](README.md). Releases are tagged `asg-group-vX.Y.Z`.

Entries marked **BREAKING** change what an unchanged caller's plan does.

## [2.0.0] - unreleased

A rewrite to the repository's conventions. 1.x callers follow
[docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md).

### Added

- Attribute-based instance type selection (`instance_requirements`), on-demand
  allocation strategy, and an all-on-demand default for `purchase_options`.
- `instance_maintenance_policy`, `availability_zone_distribution` (including
  `reservations-then-balanced`), `max_instance_lifetime`,
  `capacity_reservation`, `service_linked_role_arn`.
- Instance refresh preferences: skip matching, auto rollback, checkpoints,
  alarm rollback, triggers, protected and standby instance handling.
- Warm pool instance reuse; lifecycle hooks as separate resources, with
  `initial` for first-launch hooks; `terminate_hook_abandon` (retain or
  terminate an instance whose drain hook abandons).
- Customized-metric target tracking; predictive scaling.
- Launch template: credit specification, auto recovery, bandwidth weighting,
  nested virtualization, placement groups by ID, tags on network interfaces.
- EventBridge rules for failed launches, failed terminations and failed or
  rolled-back refreshes; `alarm_actions` defaulting to `sns_topic_arn`.
- Contract outputs: `governance`, `kms_key_policy_requirements` (contract v2,
  the Auto Scaling service-linked role), `notification_requirements`,
  `deployer_requirements`, `network_contract`, `verify_commands`.
- Eleven advisory checks and `acknowledged_checks`; `required_tag_keys`.
- `aws_autoscaling_group.static` for a Terraform-owned instance count
  (`ignore_desired_capacity_changes = false`).

### Changed

- **BREAKING** `hashicorp/aws` `>= 6.57.1, < 7.0.0` (was `>= 5.40.0, < 6.0.0`).
- **BREAKING** Inputs reshaped to the repository's conventions: `""` and `-1`
  mean unset instead of `null`; root volume settings are `root_volume`; extra
  volumes are the map `ebs_volumes`; `spot` is `purchase_options`; the instance
  role is `instance_profile`. The mapping is in the upgrade guide.
- **BREAKING** Defaults: an instance role with Session Manager is created
  (was none); instance refresh is on with rollback (was off); alarms are on
  (was off); burstable fleets get standard CPU credits (was the AWS default,
  unlimited); more group metrics are collected (free); every resource is
  tagged `ManagedBy` and `Module`.
- **BREAKING** Every volume is encrypted, and `kms_key_arn` applies to all of
  them (`root_volume_encrypted` and per-volume keys are gone).
- **BREAKING** `name` is 1-36 letters, digits and hyphens.

### Removed

- **BREAKING** Security group management (`create_security_group`, `vpc_id`,
  `security_group_name`, `security_group_ingress_rules`,
  `security_group_egress_rules`, outputs `security_group_id` and
  `security_group_ids`); `security_group_ids` is now required.
- **BREAKING** `availability_zones` (subnets are required), `default_cooldown`,
  `metrics_granularity`, `min_elb_capacity`, `initial_lifecycle_hooks` (now
  `lifecycle_hooks`).

## [1.0.0] - 2026-07-01

Initial release — a universal, production-grade EC2 Auto Scaling Group module
(launch template + ASG + optional instance IAM + optional security group +
scaling + monitoring). Workload-agnostic: drive the AMI, user-data, IAM, tags,
and scaling to fit ECS EC2 capacity, web/app fleets, batch workers, or
self-managed Kubernetes nodes. Outputs the ASG ARN for consumers such as the
`ecs-orchestrator` capacity providers.

### Compute & storage
- Launch template with enforced **IMDSv2**, configurable IMDS hop limit, optional
  detailed monitoring (`enable_detailed_monitoring`), CPU options, placement, and
  tenancy.
- **Encrypted-by-default** root volume (gp3) and additional `ebs_block_devices`,
  with optional KMS keys.
- Optional public IP via a launch-template network interface
  (`associate_public_ip_address`), otherwise the subnet decides.

### IAM & security (secure by default)
- Optional instance role + profile with caller-supplied managed policies and an
  inline policy; or bring your own instance profile.
- Optional managed security group (no inbound by default, egress allow-all).
- **Fail-closed networking**: a security group is required — the plan fails rather
  than letting instances fall back to the permissive VPC default SG.

### Capacity & scaling
- `min`/`max`/`desired`, scale-in protection, capacity rebalancing.
- On-demand **or** mixed on-demand + Spot (multiple `instance_types`,
  per-type `instance_weights`, `spot_max_price`, allocation strategy / pools).
- Target-tracking scaling policies (CPU / network / ALB request count) and
  scheduled actions.
- Instance refresh, warm pool, and initial lifecycle hooks.
- Health checks (EC2/ELB), target-group registration, termination policies,
  suspended processes, and ELB-capacity waits.

### Observability
- ASG group metrics collection (on by default) and optional CloudWatch alarms
  (high CPU; low in-service instance count, gated on the metric being collected).

### Reliability & correctness
- `create` master toggle; `create = false` is a true no-op.
- `ignore_changes = [desired_capacity]` so an autoscaler / ECS capacity provider /
  scheduled action owns the live count without fighting Terraform.
- Comprehensive **fail-fast** validations and preconditions, e.g.: SG required;
  subnets **or** AZs (not both); `max_size >= min_size`; `desired_capacity` within
  `[min_size, max_size]`; `spot.on_demand_base_capacity <= max_size`;
  `iops`/`throughput` only on supporting volume types; `kms_key_id` requires
  encryption; IAM `name_prefix` truncated to its 38-char limit;
  `ALBRequestCountPerTarget` requires a resource label; `spot_instance_pools` only
  with `lowest-price`.

### Testing
- 31 offline `terraform test` checks (plan + mocked apply), run in CI. Mocks prove
  schema, wiring, and plan logic; a live apply in a sandbox is the final gate.

### Requirements
- Terraform `>= 1.9.0`; AWS provider `>= 5.40.0, < 6.0.0`.
