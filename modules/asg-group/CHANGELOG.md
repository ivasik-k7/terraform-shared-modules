# Changelog

All notable changes to the `asg-group` module are documented here. The format
follows [Keep a Changelog](https://keepachangelog.com/) and the module follows
[Semantic Versioning](https://semver.org/).

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
