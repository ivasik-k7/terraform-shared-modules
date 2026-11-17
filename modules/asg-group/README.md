# terraform-aws-asg-group

An EC2 Auto Scaling group for a regulated estate: a hardened launch template
(IMDSv2, encrypted volumes, no SSH, Session Manager), on-demand, mixed or
attribute-based Spot fleets, instance refresh with rollback, maintenance and
warm pools, target tracking and predictive scaling, and the signals for the
failures that leave an apply green: launches that fail on a KMS grant or a
quota, and refreshes that roll back.

**Stage:** 2.0.0 release candidate. Stable once a security review reports no
open Critical or High finding ([GOVERNANCE](../../docs/GOVERNANCE.md)).

```hcl
module "fleet" {
  source  = "app.terraform.io/<org>/asg-group/aws"
  version = "~> 2.0"

  name               = "orders-web"
  ami                = "ami-0123456789abcdef0" # pinned: a new image is a reviewed change
  subnet_ids         = var.private_subnet_ids # two AZs or more
  security_group_ids = [var.instance_sg_id]   # required; the module creates none
  min_size           = 2
  max_size           = 10

  kms_key_arn   = var.ebs_key_arn # hand output.kms_key_policy_requirements to its owner first
  sns_topic_arn = var.alerts_topic_arn

  target_tracking_policies = {
    cpu = { predefined_metric_type = "ASGAverageCPUUtilization", target_value = 60 }
  }
}
```

Re-export the contract outputs as root outputs of the workspace, or read them
with `tfe_outputs`: `kms_key_policy_requirements` goes to the key owners (or
into [`modules/kms`](../kms) as a consumer), `notification_requirements` to
whoever owns the topic, `deployer_requirements` to whoever owns the apply role,
and `network_contract` to the network team. `autoscaling_group_arn` is what an
ECS capacity provider takes ([`modules/ecs`](../ecs), `ec2_capacity_providers`).

## Requirements

| Component | Supported | What a workspace must do |
|---|---|---|
| Terraform | `>= 1.9.0` | Set the workspace's Terraform version to 1.9 or later |
| `hashicorp/aws` | `>= 6.57.1, < 7.0.0` | Upgrade the workspace to aws 6.x and commit the lock file. Unlike most modules here, 2.x does not support aws 5.x: it uses `instance_lifecycle_policy`, `reservations-then-balanced`, `network_performance_options` and placement groups by ID, which exist only in 6.x |
| Account | The Auto Scaling service-linked role | AWS creates `AWSServiceRoleForAutoScaling` on first use if the apply role may; `deployer_requirements` includes that permission |
| Network | Private subnets with the Session Manager endpoints | `network_contract` lists them |

## What the module refuses

These fail at plan, with a message naming the field.

| Refused | Because |
|---|---|
| No `security_group_ids` | Instances would fall back to the VPC's default group |
| Both `ami` and `ami_ssm_parameter`, or neither | The image would be ambiguous or missing |
| A warm pool with Spot or instance weights | AWS does not support either with warm pools ([warm pools](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-warm-pools.html)) |
| Scaling policies or scheduled `desired_capacity` with `ignore_desired_capacity_changes = false` | Every apply would set the count back, fighting the scaler |
| `instance_weights` for a type not in the fleet, or with `instance_requirements` | The weight would silently apply to nothing |
| `instance_refresh.alarm_names` without `auto_rollback`; checkpoints not ascending or not ending at 100; `launch_template` as a trigger | AWS rejects them, or the provider warns the trigger is implicit |
| `terminate_hook_abandon` without a TERMINATING hook | It would never apply |
| An `initial` TERMINATING hook | Only launch hooks need to see the first instances |
| `spot_instance_pools` with anything but `lowest-price`; `max_capacity_buffer` while honoring max | AWS rejects them |
| `iops` or `throughput` on a volume type without them; an extra volume on the root device | The launch template is rejected, or a volume is lost |
| A `required_tag_keys` key missing or empty in `tags` | Instances would be unattributable in Cost Explorer and invisible to tag-based SCPs |
| A `name` over 36 characters | The instance role's `name_prefix` is capped at 38 |

### Advisory checks

Eleven `check` blocks warn without refusing. Each is silenced by naming it in
`acknowledged_checks`, and the decision is then listed in `output.governance`.
All are silent when `create = false`.

| Check | Warns when |
|---|---|
| `somebody_hears_a_failure` | no topic and no alarm actions, or both alarms and event rules are off |
| `fleet_survives_an_az` | one subnet, or a capacity floor (min_size or a scheduled one) below two |
| `spot_fleets_keep_an_on_demand_floor` | the whole fleet is Spot |
| `volumes_use_a_customer_key` | `kms_key_arn` is empty |
| `burstable_credits_are_bounded` | `cpu_credits = "unlimited"` on a burstable fleet |
| `instances_are_reached_without_ssh_keys` | `key_name` is set |
| `instances_have_no_public_ip` | `public_ip = "assign"` |
| `launch_template_changes_reach_the_fleet` | instance refresh is off |
| `containers_cannot_reach_instance_credentials` | `metadata_hop_limit` above 1 |
| `ami_is_pinned` | the AMI comes from `ami_ssm_parameter` |
| `retained_instances_are_cleaned_up` | `terminate_hook_abandon = "retain"` |

## Behaviour to know about

**Volumes under a customer key need the service-linked role in the key
policy.** Auto Scaling launches with `AWSServiceRoleForAutoScaling` (or the
custom-suffix role in `service_linked_role_arn`), which has no access to
customer keys. Without the two statements in `kms_key_policy_requirements`,
every launch fails with `Client.InternalError: Client error on launch` while
the apply stays green
([troubleshooting](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ts-as-instancelaunchfailure.html)).
The `launch-failed` event rule reports it.

**Who owns the instance count.** With `ignore_desired_capacity_changes = true`
(the default) the group is `aws_autoscaling_group.this` and ignores
`desired_capacity` after creation, so scaling policies, scheduled actions and
an ECS capacity provider own it. With `false` it is `aws_autoscaling_group.static`
and every apply sets the count. Flipping it on an existing group moves the
group between the two addresses; write a root `moved` block
(`module.<call>.aws_autoscaling_group.this[0]` to `.static[0]` or back), or the
group is replaced.

**Scheduled actions that change `min_size` or `max_size` are undone by the
next apply.** Terraform owns both bounds. An apply at night, after a schedule
lowered `min_size`, raises it again. Schedule `desired_capacity`, or apply
outside those windows.

**Initial lifecycle hooks replace the group when they change.** The provider
treats `initial_lifecycle_hook` as ForceNew (`internal/service/autoscaling/group.go`
at 6.71.0), and a new group means new instances and, behind an ECS capacity
provider, a new capacity provider. Hooks are therefore separate resources,
updated in place; `initial = true` is for a launch hook that must also hold the
instances launched when the group is created.

**Instance refresh is on by default, with rollback.** Any change to the launch
template (a new AMI, user data, a tag on instances) or to the instance mix
starts a rolling refresh that skips instances already up to date and rolls back
on failure or on `alarm_names`. An apply that changes the template while a
refresh runs cancels it and starts a new one (provider `startInstanceRefresh`).
The group launches the template's numbered latest version, which rollback
requires.

**The AMI is resolved at plan, not at launch.** `ami_ssm_parameter` is read at
every plan, so the template always holds an AMI ID. A template that resolves
`resolve:ssm:` at launch rules out rollback, skip matching, warm pools and
attribute-based selection
([SSM parameters](https://docs.aws.amazon.com/autoscaling/ec2/userguide/using-systems-manager-parameters.html)).
With the parameter, a new image published by AWS moves the template at the next
unrelated apply; pin `ami` to take images deliberately.

**Retained instances keep billing.** With `terminate_hook_abandon = "retain"`,
an instance whose drain hook ends in ABANDON stays, out of service and billed,
while a replacement launches; refresh and `max_instance_lifetime` ignore it. It
goes only when someone calls `TerminateInstanceInAutoScalingGroup` and completes
the hook again ([instance lifecycle policy](https://docs.aws.amazon.com/autoscaling/ec2/userguide/instance-lifecycle-policy.html)).

**Burstable fleets default to standard credits.** AWS's default for T3 is
unlimited, which bills surplus credits with no ceiling. The module sends
`standard` when every type is burstable, and nothing otherwise.

**The deployer needs more than Auto Scaling permissions.** Creating or updating
a group with a launch template is authorized as `ec2:RunInstances` and
`ec2:CreateTags`, and handing over the instance role as `iam:PassRole`
([launch template permissions](https://docs.aws.amazon.com/autoscaling/ec2/userguide/ec2-auto-scaling-launch-template-permissions.html)).
`deployer_requirements` is known at plan; it names the role by its `<name>-`
prefix, because IAM adds the suffix at creation.

## Examples

| Example | Shows |
|---|---|
| [`basic`](examples/basic) | The smallest call: two instances across two AZs from a pinned AMI |
| [`complete`](examples/complete) | Every module-level input, as a web fleet behind an ALB: mixed on-demand and Spot, target tracking and predictive scaling, refresh checkpoints with alarm rollback, an initial launch hook and a draining hook |
| [`ecs-capacity`](examples/ecs-capacity) | EC2 capacity for `modules/ecs`: attribute-based Spot with one on-demand instance, protected from scale-in, from the ECS-optimized image |

## Most-used inputs

The registry's Inputs tab is the reference; descriptions in `variables.tf` are
written to be read there.

| Name | Default | Notes |
|---|---|---|
| `name`, `subnet_ids`, `security_group_ids` | required | Up to 36 characters; two AZs or more; your groups |
| `ami`, `ami_ssm_parameter` | `""` | Exactly one; pin `ami` for deliberate image changes |
| `instance_type`, `instance_types`, `instance_requirements` | `t3.medium`, `[]`, off | One type, a list in preference order, or attribute-based selection |
| `purchase_options` | all on-demand | On-demand base, percentage above it, Spot strategy |
| `min_size`, `max_size`, `desired_capacity` | `1`, `3`, `-1` (min) | `max_size` is the ceiling of the bill |
| `ignore_desired_capacity_changes` | `true` | `false`: Terraform owns the count |
| `instance_profile` | created, with Session Manager | `create = false` with `name` to bring your own |
| `kms_key_arn`, `service_linked_role_arn` | `""` | Customer key for every volume, and the role it must admit |
| `root_volume`, `ebs_volumes` | 30 GiB gp3 | Always encrypted |
| `instance_refresh` | on, rollback, skip matching | Checkpoints, alarm rollback, triggers |
| `instance_maintenance_policy` | AWS default | `100`/`110` launches before it terminates |
| `lifecycle_hooks`, `terminate_hook_abandon` | `{}`, `""` | Separate resources; `initial` for first-launch hooks |
| `target_tracking_policies`, `predictive_scaling`, `scheduled_actions` | none | Predefined or customized metrics; forecast before scaling |
| `sns_topic_arn`, `alarm_actions` | `""`, `[]` | Where failures and alarms go |
| `acknowledged_checks` | `[]` | Advisory checks you have decided to live with |

## Contract outputs

| Output | For |
|---|---|
| `governance` | The posture as data: who owns the count, the instance mix, Spot share, AMI source, refresh settings, keys, SSH, public IP, hop limit, initial hooks, acknowledged checks |
| `kms_key_policy_requirements` | Contract v2 entries: the service-linked role's use of and grants on the volume key, and the topic key's publishers. Feed them to `modules/kms` as a consumer |
| `notification_requirements` | The topic policy statements the alarms and event rules need |
| `deployer_requirements` | `ec2:RunInstances`, `ec2:CreateTags`, `iam:PassRole` on the instance role, and the service-linked role, as a policy known at plan |
| `network_contract` | The Session Manager endpoints and the S3 gateway the instances need |
| `verify_commands` | CloudShell checks: the group, its instances, failed launches, refresh status, a session on an instance, warm pool, forecast, retained instances |

## Limits

- **Never applied against real AWS in this repository.** Plans are tested
  against a mocked provider on the newest aws 6.x, and one mocked apply proves
  the resources assemble. AWS accepting the requests, the launch template
  rendering without a diff, and the event patterns matching real events are
  reasoned from documentation and provider source, not observed.
- **aws 6.x only.** Workspaces on aws 5.x stay on asg-group 1.x.
- **No security groups are created.** The group's instances use yours.
- **No launch-time AMI resolution, step scaling, Classic Load Balancers, VPC
  Lattice traffic sources, secondary network interfaces or ENA queue tuning.**
- **The execution of user data is not checked.** A script that fails leaves
  the instance InService unless the load balancer's health check catches it;
  use `health_check_type = "ELB"` behind a load balancer.

## Versioning and support

Semantic versioning, tags `asg-group-vX.Y.Z`. Breaking: removed or renamed
inputs and outputs, new required inputs, changed defaults, an update that
becomes a replacement, an address change, a raised Terraform or provider
floor. A deprecated input keeps working for at least one minor release before
a major removes it. The previous major gets security fixes for six months after
a new major. [CHANGELOG.md](CHANGELOG.md), [COSTS.md](COSTS.md),
[docs/UPGRADE-2.0.md](docs/UPGRADE-2.0.md) for 1.x callers.
