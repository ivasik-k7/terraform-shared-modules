# Node Group Module – Usage Guide

## Minimal (backward-compatible)

```hcl
module "ng_default" {
  source = "./modules/node_group"

  cluster_name    = "my-cluster"
  cluster_version = "1.30"
  node_group_name = "default"
  subnet_ids      = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
}
```

---

## Production: ON_DEMAND with Launch Template, IMDSv2, encrypted EBS

```hcl
module "ng_prod" {
  source = "./modules/node_group"

  cluster_name    = "prod-cluster"
  cluster_version = "1.30"
  node_group_name = "general"
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["m6i.xlarge", "m6a.xlarge", "m5.xlarge"]
  capacity_type  = "ON_DEMAND"
  min_size       = 3
  max_size       = 20
  desired_size   = 5

  # Storage
  disk_size   = 100
  disk_type   = "gp3"
  disk_iops   = 4000
  disk_throughput = 250
  disk_encrypted  = true
  disk_kms_key_id = "arn:aws:kms:eu-west-1:123456789012:key/mrk-abc123"

  # Security: IMDSv2 enforced, containers cannot reach IMDS directly
  imdsv2_hop_limit = 1  # set to 2 if pods need EC2 metadata without IRSA

  # Monitoring: enable 1-min metrics in production
  enable_detailed_monitoring = true

  # Pin AMI to prevent surprise changes during scale-out
  release_version = "1.30.0-20240522"
}
```

---

## FinOps: SPOT nodes with instance diversity

```hcl
module "ng_spot" {
  source = "./modules/node_group"

  cluster_name    = "prod-cluster"
  cluster_version = "1.30"
  node_group_name = "spot-workers"
  subnet_ids      = module.vpc.private_subnets

  # Diversify across 4 instance families to maximise spot availability
  instance_types = [
    "m6i.2xlarge", "m6a.2xlarge",
    "m5.2xlarge",  "m5a.2xlarge",
  ]
  capacity_type = "SPOT"
  min_size      = 0
  max_size      = 30
  desired_size  = 5

  labels = { "workload-type" = "spot", "topology.kubernetes.io/zone" = "auto" }
  taints = [{
    key    = "workload-type"
    value  = "spot"
    effect = "NO_SCHEDULE"
  }]

  finops_cost_center = "platform-eng"
  finops_team        = "infra"
}
```

---

## FinOps: Warm Pool (eliminate scale-out latency spikes)

```hcl
module "ng_warm" {
  source = "./modules/node_group"

  cluster_name    = "prod-cluster"
  cluster_version = "1.30"
  node_group_name = "warm-general"
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["m6i.large"]
  min_size       = 2
  max_size       = 20
  desired_size   = 4

  # Warm pool: keep 2 pre-initialised instances in Stopped state
  # Cost: EBS only ($0.08/GB/month per instance) vs full EC2 price when Running
  enable_warm_pool                = true
  warm_pool_state                 = "Stopped"   # cheapest; use "Running" for <1s join
  warm_pool_min_size              = 2
  warm_pool_max_prepared_capacity = 6           # max warm+running = 6
  warm_pool_instance_reuse_policy = true        # return to pool on scale-in
}
```

---

## FinOps: Scheduled scale-to-zero (dev/staging)

```hcl
module "ng_dev" {
  source = "./modules/node_group"

  cluster_name    = "dev-cluster"
  cluster_version = "1.30"
  node_group_name = "dev-workers"
  subnet_ids      = module.vpc.private_subnets

  instance_types = ["t3.medium"]
  min_size       = 0
  max_size       = 5
  desired_size   = 2

  # Scale to zero at 20:00 UTC, back up at 07:00 UTC weekdays only
  # Saves ~60 % on EC2 cost for a dev cluster running 9h/day × 5 days/week
  scheduled_scaling_actions = {
    scale-down-evening = {
      recurrence   = "0 20 * * MON-FRI"
      min_size     = 0
      max_size     = 0
      desired_size = 0
    }
    scale-up-morning = {
      recurrence   = "0 7 * * MON-FRI"
      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
    scale-down-weekend = {
      recurrence   = "0 20 * * FRI"
      min_size     = 0
      max_size     = 0
      desired_size = 0
    }
    scale-up-monday = {
      recurrence   = "0 7 * * MON"
      min_size     = 1
      max_size     = 5
      desired_size = 2
    }
  }

  finops_environment = "dev"
  finops_team        = "platform-eng"
}
```

---

## Custom bootstrap + post-bootstrap hook

```hcl
module "ng_custom_bootstrap" {
  source = "./modules/node_group"

  cluster_name    = "my-cluster"
  cluster_version = "1.30"
  node_group_name = "custom"
  subnet_ids      = module.vpc.private_subnets

  bootstrap_extra_args = "--kubelet-extra-args '--max-pods=110 --node-labels=role=worker'"

  pre_bootstrap_user_data = <<-EOF
    #!/bin/bash
    # Mount extra NVMe instance storage
    mkfs.xfs /dev/nvme1n1
    mkdir -p /mnt/fast-storage
    mount /dev/nvme1n1 /mnt/fast-storage
  EOF

  post_bootstrap_user_data = <<-EOF
    #!/bin/bash
    # Register node with internal monitoring agent
    /usr/local/bin/register-node.sh --cluster my-cluster
  EOF
}
```

---

## Placement group (HPC / low-latency)

```hcl
module "ng_hpc" {
  source = "./modules/node_group"

  cluster_name    = "hpc-cluster"
  cluster_version = "1.30"
  node_group_name = "hpc-workers"
  subnet_ids      = [module.vpc.private_subnets[0]] # cluster PG must be single AZ

  instance_types           = ["c6in.8xlarge"]
  placement_group_strategy = "cluster"  # lowest latency between instances
}
```

---

## Bring-your-own IAM role

```hcl
module "ng_byo_role" {
  source = "./modules/node_group"

  cluster_name    = "my-cluster"
  cluster_version = "1.30"
  node_group_name = "shared-role"
  subnet_ids      = module.vpc.private_subnets

  create_iam_role = false
  iam_role_arn    = aws_iam_role.shared_node_role.arn
}
```

---

## Outputs reference

| Output                           | Description                                        |
| -------------------------------- | -------------------------------------------------- |
| `node_group_arn`                 | Full node group ARN                                |
| `node_group_id`                  | `cluster:nodegroup` ID                             |
| `node_group_name`                | Registered name of the node group                  |
| `status`                         | ACTIVE / CREATING / UPDATING / DELETING            |
| `node_group_role_arn`            | IAM role ARN (for aws-auth ConfigMap)              |
| `node_group_role_name`           | IAM role name                                      |
| `launch_template_id`             | Launch Template ID                                 |
| `launch_template_latest_version` | Latest LT version number                           |
| `autoscaling_group_names`        | ASG names (for alarms, dashboards)                 |
| `placement_group_id`             | Placement group ID when strategy is set            |
| `finops_summary`                 | Structured FinOps config snapshot for cost reviews |
