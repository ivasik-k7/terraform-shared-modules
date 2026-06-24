# Bastion (Isolated)

A hardened, scalable bastion for **fully isolated environments**, built around a
**bring-your-own AMI** model. Unlike the general-purpose [`bastion`](../bastion)
module, this one:

- **Never looks up or builds an AMI** and **does not depend on user-data**. In
  isolated/air-gapped accounts cloud-init usually won't run, so the image is
  expected to be pre-baked by another team. You data-source the AMI in your
  caller and pass `ami_id` in.
- Is **Auto Scaling Group–based** for self-healing and horizontal scale.
- Ships **first-class auto-shutdown** (scheduled scaling) for non-working hours.
- Defaults to **SSM Session Manager access** — no inbound ports, no SSH keys.

It is intentionally separate so the existing bastion's "main flow" is untouched.

## Highlights

- **BYO AMI** — `ami_id` is required and used verbatim; no `aws_ami` data source.
- **Secure by default** — IMDSv2 required, encrypted root volume, no inbound
  rules (SSM-only), least-privilege IAM role with `AmazonSSMManagedInstanceCore`.
- **Auto-shutdown** — `auto_shutdown` scales the ASG to 0 outside working hours
  and back during them (cron + timezone); `scheduled_actions` for full control.
- **Scalable & flexible** — `min/max/desired`, multi-AZ, optional Spot via a
  mixed-instances policy, instance refresh on AMI changes.
- **Composable** — create or bring your own security group and IAM profile;
  arbitrary ingress/egress and SSH convenience rules; `create` master toggle.

## Usage — isolated, SSM-only, auto-shutdown

```hcl
# You (or another team) resolve the pre-baked AMI:
data "aws_ami" "bastion" {
  owners      = ["123456789012"] # your image-builder account
  most_recent = true
  filter {
    name   = "name"
    values = ["hardened-bastion-*"]
  }
}

module "bastion" {
  source = "../../modules/bastion-isolated"

  name       = "platform"
  ami_id     = data.aws_ami.bastion.id
  vpc_id     = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids # private — access via SSM

  instance_type = "t3.micro"

  # Shut down weekday evenings, start weekday mornings (London time).
  auto_shutdown = {
    scale_down_recurrence = "0 19 * * MON-FRI"
    scale_up_recurrence   = "0 7 * * MON-FRI"
    time_zone             = "Europe/London"
  }

  tags = { Environment = "prod" }
}
```

Connect with **no open ports**:

```bash
aws ssm start-session --target <instance-id>
```

> **Isolated networking:** SSM requires the `ssm`, `ssmmessages`, and
> `ec2messages` VPC interface endpoints (and `s3` gateway endpoint) to be present
> in an account with no internet egress.

## Access patterns

| Mode                                  | How                     | Config                                      |
| ------------------------------------- | ----------------------- | ------------------------------------------- |
| **SSM Session Manager** (recommended) | `aws ssm start-session` | default — nothing to open                   |
| SSH from a CIDR                       | port 22 ingress         | `ssh_allowed_cidr_blocks = ["10.0.0.0/16"]` |
| SSH from a security group             | port 22 ingress         | `ssh_allowed_security_group_ids = [...]`    |
| Fully custom                          | arbitrary rules         | `security_group_ingress_rules = { ... }`    |

## Auto-shutdown

`auto_shutdown` generates two `aws_autoscaling_schedule` actions:

- **scale-down** at `scale_down_recurrence` → `off_*` capacity (default `0`)
- **scale-up** at `scale_up_recurrence` → your `min/max/desired_capacity`

Because runtime capacity is managed by these schedules, the ASG's
`desired_capacity` is under `ignore_changes` — Terraform sets it once and does
not fight the scheduler on later applies. For anything more elaborate (weekends,
multiple windows, holidays), use the generic `scheduled_actions` map; both merge.

```hcl
scheduled_actions = {
  weekend-off = { recurrence = "0 0 * * SAT", min_size = 0, max_size = 0, desired_capacity = 0 }
  monday-on   = { recurrence = "0 7 * * MON", min_size = 1, max_size = 1, desired_capacity = 1 }
}
```

## Scaling & Spot

```hcl
min_size         = 1
max_size         = 3
desired_capacity = 1

# Cost-optimised, interruption-tolerant capacity:
instance_types = ["t3.micro", "t3a.micro", "t3.small"]
spot_enabled   = true

# Roll the fleet automatically when the AMI changes:
instance_refresh = { min_healthy_percentage = 100 }
```

## Key inputs

| Name                                                                                         | Description                                    | Default           |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------- | ----------------- |
| `name`                                                                                       | Resource name prefix                           | n/a (required)    |
| `ami_id`                                                                                     | Pre-built AMI id (BYO; no lookup)              | n/a (required)    |
| `vpc_id`                                                                                     | VPC id (required with `create_security_group`) | `null`            |
| `subnet_ids`                                                                                 | Subnets for the ASG (use private for SSM-only) | n/a (required)    |
| `instance_type` / `instance_types`                                                           | Primary type / mixed-policy override list      | `t3.micro` / `[]` |
| `min_size` / `max_size` / `desired_capacity`                                                 | Working-hours capacity                         | `1` / `1` / `1`   |
| `auto_shutdown`                                                                              | Off-hours scheduled scaling (object)           | `null`            |
| `scheduled_actions`                                                                          | Arbitrary scheduled scaling (map)              | `{}`              |
| `spot_enabled`                                                                               | Use Spot via mixed instances policy            | `false`           |
| `instance_refresh`                                                                           | Rolling refresh on launch-template change      | `null`            |
| `root_block_device` / `ebs_block_devices`                                                    | Root EBS config / extra volumes (encrypted)    | `{}` / `{}`       |
| `metadata_options`                                                                           | IMDS options (IMDSv2 enforced by default)      | `{}`              |
| `create_security_group` / `security_group_ids`                                               | Create SG / attach existing                    | `true` / `[]`     |
| `ssh_allowed_cidr_blocks` / `..._ipv6_..` / `..._security_group_ids` / `..._prefix_list_ids` | SSH convenience ingress                        | `[]`              |
| `security_group_ingress_rules` / `security_group_egress_rules`                               | Arbitrary SG rules                             | `{}` / allow-all  |
| `create_iam_role` / `iam_instance_profile_name`                                              | Create role+profile / BYO profile              | `true` / `null`   |
| `enable_ssm` / `attach_cloudwatch_agent_policy`                                              | Managed policy toggles                         | `true` / `false`  |
| `create_cloudwatch_alarms` / `alarm_actions`                                                 | StatusCheckFailed alarm + notify targets       | `false` / `[]`    |
| `iam_role_additional_policy_arns`                                                            | Extra managed policies (map)                   | `{}`              |
| `associate_public_ip`                                                                        | Public IP (keep false for isolated)            | `false`           |
| `create`                                                                                     | Master switch                                  | `true`            |

See [`variables.tf`](./variables.tf) for the complete set and object schemas.

## Outputs

| Name                                              | Description                            |
| ------------------------------------------------- | -------------------------------------- |
| `autoscaling_group_name` / `_arn` / `_id`         | The bastion ASG                        |
| `launch_template_id` / `_arn` / `_latest_version` | The launch template                    |
| `security_group_id` / `_arn`                      | Created SG (null if not created)       |
| `iam_role_arn` / `_name`                          | Created role (null when BYO profile)   |
| `iam_instance_profile_name` / `_arn`              | Instance profile (created or provided) |
| `scheduled_action_names`                          | All scheduled scaling actions          |
| `auto_shutdown_enabled`                           | Whether auto-shutdown is active        |
