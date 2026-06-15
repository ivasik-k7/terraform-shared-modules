# EBS Terraform Module

A comprehensive, flexible Terraform module for provisioning AWS Elastic Block Store (EBS) volumes with encryption, instance attachment, automated snapshot lifecycle management (DLM), and CloudWatch alarms.

Designed to be called frequently — manage one or many volumes per call and attach them to ECS/EC2 instances — while keeping encryption, backups, and monitoring consistent and resilient by default.

## What This Module Does

- Creates one or many EBS volumes from a single `volumes` map, each independently configurable
- Encrypts volumes by default, using either a module-created customer-managed KMS key, a supplied key, or the AWS-managed `aws/ebs` key
- Optionally creates a dedicated CMK with automatic key rotation and a least-privilege key policy
- Attaches volumes to EC2/ECS instances with safe-detach controls, including io1/io2 **Multi-Attach** to several instances at once
- Manages automated, scheduled snapshots via a Data Lifecycle Manager (DLM) policy, including retention and cross-region copy for disaster recovery
- Creates (or reuses) the IAM role DLM requires, including the KMS permissions needed to snapshot **encrypted** volumes (customer-managed CMK or the default `aws/ebs` key)
- Provisions CloudWatch alarms for volume health (BurstBalance) and idle/cost signals
- Supports gp3 tuning (IOPS + throughput), io1/io2 provisioned IOPS, Multi-Attach, st1/sc1, and snapshot restore
- Validates inputs at plan time: volume type, IOPS required for io1/io2, throughput range/applicability, Multi-Attach rules, duplicate-instance attachment, st1/sc1 minimum size, attachment requirements, and missing AZ
- Ships a native `terraform test` suite (plan + mocked-provider apply runs) — run `terraform test` in the module directory

## Design Philosophy

Resources are **opt-in via toggles** so you only create what you need:

| Capability | Toggle | Default |
|---|---|---|
| Volume encryption | `encrypted` | `true` |
| Dedicated KMS CMK | `create_kms_key` | `false` (uses `aws/ebs`) |
| Automated snapshots | `create_lifecycle_policy` | `false` |
| DLM IAM role | `create_dlm_role` | `true` (when lifecycle enabled) |
| CloudWatch alarms | `create_cloudwatch_alarms` | `false` |

## Basic Usage

### Minimal — a single encrypted volume

```hcl
module "ebs" {
  source = "../../modules/ebs"

  name              = "app-data"
  availability_zone = "us-east-1a"

  volumes = {
    data = {
      size = 100
      type = "gp3"
    }
  }
}
```

### Attached to an ECS/EC2 instance

```hcl
module "ebs" {
  source = "../../modules/ebs"

  name              = "app-data"
  availability_zone = "us-east-1a"

  volumes = {
    data = {
      size        = 100
      type        = "gp3"
      iops        = 3000
      throughput  = 250
      instance_id = aws_instance.ecs.id
      device_name = "/dev/sdf"
    }
  }

  tags = { Environment = "prod" }
}
```

### Full resilience — dedicated CMK, scheduled snapshots, DR copy, alarms

```hcl
module "ebs" {
  source = "../../modules/ebs"

  name              = "app-data"
  availability_zone = "us-east-1a"

  create_kms_key = true   # rotated, customer-managed CMK
  encrypted      = true

  volumes = {
    data = { size = 200, type = "gp3", instance_id = aws_instance.ecs.id, device_name = "/dev/sdf" }
    logs = { size = 500, type = "st1" }
  }

  create_lifecycle_policy = true
  snapshot_schedules = {
    daily = {
      interval     = 24
      times        = ["03:00"]
      retain_count = 14
      cross_region_copy = [{
        target       = "us-west-2"
        encrypted    = true
        retain_count = 7
      }]
    }
  }

  create_cloudwatch_alarms = true
  alarm_actions            = [aws_sns_topic.alerts.arn]

  tags = { Environment = "prod" }
}
```

### Multi-Attach (io1/io2) across several instances

```hcl
module "ebs" {
  source = "../../modules/ebs"

  name              = "cluster"
  availability_zone = "us-east-1a"

  volumes = {
    shared = {
      size                 = 200
      type                 = "io2"
      iops                 = 10000
      multi_attach_enabled = true
      attachments = [
        { instance_id = aws_instance.node_a.id, device_name = "/dev/sdg" },
        { instance_id = aws_instance.node_b.id, device_name = "/dev/sdg" },
      ]
    }
  }
}
```

The single-instance `instance_id` / `device_name` shortcut and the `attachments` list can be combined; the module flattens both into one set of attachments keyed by `"<volume>.<index>"`. Indexes (rather than instance IDs) keep the `for_each` keys known at plan time, so you can safely set `instance_id = aws_instance.x.id` for instances created in the same configuration. Appending attachments is safe; removing or reordering earlier list entries shifts indexes and will detach/reattach the later volumes.

### Restore from a snapshot

```hcl
volumes = {
  restored = {
    snapshot_id = "snap-0123456789abcdef0"
    type        = "gp3"
    # size is optional when restoring; omit to inherit the snapshot size
  }
}
```

## Volume Object Reference

Each entry in `volumes` accepts:

| Attribute | Type | Default | Notes |
|---|---|---|---|
| `availability_zone` | string | `var.availability_zone` | Required (here or module-level) |
| `size` | number | — | GiB; required unless `snapshot_id` set |
| `type` | string | `gp3` | `gp2`, `gp3`, `io1`, `io2`, `st1`, `sc1`, `standard` |
| `iops` | number | — | gp3/io1/io2 only |
| `throughput` | number | — | gp3 only (125–1000 MiB/s) |
| `encrypted` | bool | `var.encrypted` | Per-volume override |
| `kms_key_id` | string | module key | Per-volume override |
| `snapshot_id` | string | — | Restore from snapshot |
| `multi_attach_enabled` | bool | `false` | io1/io2 only |
| `outpost_arn` | string | — | Create on an Outpost |
| `final_snapshot` | bool | `false` | Snapshot before deletion |
| `instance_id` | string | — | Triggers attachment when set |
| `device_name` | string | — | Required when `instance_id` set |
| `stop_instance_before_detaching` | bool | `true` | Safer detach |
| `force_detach` | bool | `false` | Use with caution |
| `skip_destroy` | bool | `false` | Leave attached on destroy |
| `attachments` | list(object) | `[]` | Extra attachment targets for Multi-Attach |
| `managed_by_dlm` | bool | `true` | Include in snapshot policy |
| `tags` | map(string) | `{}` | Merged onto the volume |

## How Snapshot Targeting Works

When `create_lifecycle_policy = true`, every volume with `managed_by_dlm = true` is tagged with `EbsModuleDlmGroup = <name>`. The DLM policy targets that tag, so snapshots are scoped precisely to this module's volumes — no accidental coverage of unrelated volumes.

## Encrypting With a Custom CMK

When `create_kms_key = true`, the generated key policy grants the account root full control. For instances to **attach** volumes encrypted with that key — especially ECS capacity launched by an Auto Scaling group — pass the relevant principals via `kms_key_additional_principals`:

```hcl
create_kms_key = true
kms_key_additional_principals = [
  aws_iam_role.ecs_instance.arn,
  "arn:aws:iam::123456789012:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling",
]
```

Omit this only when the consuming principals already have key access via their own IAM policies. Supplying a full `kms_key_policy` overrides this generated policy entirely.

## A Note on the Idle Alarm

When `create_cloudwatch_alarms = true`, two alarm families are created:

- **BurstBalance** (gp2/st1/sc1 only) — a genuine health signal; a depleting burst bucket means the volume is undersized for its workload.
- **Idle** (`VolumeIdleTime`) — a coarse **FinOps heuristic** for spotting detached/unused volumes still incurring cost. It can false-positive on legitimately quiet volumes, so it is fully togglable via `enable_idle_alarm` and tunable via `idle_alarm_threshold_seconds` / `idle_alarm_evaluation_periods`. Disable it for low-traffic volumes.

## Requirements

| Name | Version |
|---|---|
| terraform | >= 1.5.0 |
| aws | ~> 5.0 |

## Inputs

See [variables.tf](variables.tf) for the full list with descriptions and validation rules.

## Outputs

| Name | Description |
|---|---|
| `volume_ids` | Map of logical names to volume IDs |
| `volume_arns` | Map of logical names to volume ARNs |
| `volume_availability_zones` | Map of logical names to AZs |
| `volume_sizes` | Map of logical names to sizes (GiB) |
| `attachments` | Map of `"<volume>.<index>"` to `{ volume_id, instance_id, device_name }` |
| `attachment_device_names` | Map of `"<volume>.<index>"` to attached device name |
| `attachment_instance_ids` | Map of `"<volume>.<index>"` to attached instance ID |
| `kms_key_id` / `kms_key_arn` / `kms_alias_arn` | Created KMS key details (null if not created) |
| `effective_kms_key_id` | Key actually used for encryption |
| `dlm_lifecycle_policy_id` / `dlm_lifecycle_policy_arn` | DLM policy details (null if not created) |
| `dlm_role_arn` | IAM role used by DLM |
| `burst_balance_alarm_arns` / `idle_alarm_arns` | CloudWatch alarm ARNs |
