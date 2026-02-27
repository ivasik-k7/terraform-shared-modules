# ─────────────────────────────────────────────────────────────────────────────
# Node Group Module
#
# Features:
#   • Launch Template – IMDSv2, EBS encryption, custom bootstrap, detailed
#     monitoring, placement groups, pre/post bootstrap hooks
#   • Warm Pool      – near-zero scale-out latency (FinOps: stopped instances
#                      cost EBS only, not compute)
#   • Scheduled Scaling – automatic scale-to-zero for dev/staging (FinOps)
#   • Bring-your-own IAM role
#   • Fully backward-compatible: all new features default to original behaviour
# ─────────────────────────────────────────────────────────────────────────────

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ─────────────────────────────────────────────────────────────────────────────
# Locals
# ─────────────────────────────────────────────────────────────────────────────
locals {
  node_group_full_name = "${var.cluster_name}-${var.node_group_name}"
  role_name            = coalesce(var.iam_role_name, "${local.node_group_full_name}-node-role")

  common_tags = merge(
    {
      "terraform-module"                              = "node-group"
      "k8s.io/cluster-autoscaler/enabled"             = "true"
      "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    },
    var.tags,
  )

  # Effective node role ARN
  effective_node_role_arn = var.create_iam_role ? aws_iam_role.node[0].arn : var.iam_role_arn

  # Update config: only one of max_unavailable / max_unavailable_percentage can be set
  use_max_unavailable_count = var.update_config_max_unavailable != null

  # User-data for AL2 (ignored for Bottlerocket/Windows)
  user_data = base64encode(templatefile("${path.module}/templates/userdata.sh.tpl", {
    cluster_name             = var.cluster_name
    bootstrap_extra_args     = var.bootstrap_extra_args
    pre_bootstrap_user_data  = var.pre_bootstrap_user_data
    post_bootstrap_user_data = var.post_bootstrap_user_data
  }))
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM – Node Role  (skipped when create_iam_role = false)
# ─────────────────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "node_assume_role" {
  count = var.create_iam_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  count              = var.create_iam_role ? 1 : 0
  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.node_assume_role[0].json
  tags               = merge(local.common_tags, { Name = local.role_name })
}

# AWS-managed baseline policies
resource "aws_iam_role_policy_attachment" "AmazonEKSWorkerNodePolicy" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "AmazonEKS_CNI_Policy" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "AmazonEC2ContainerRegistryReadOnly" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "AmazonSSMManagedInstanceCore" {
  count      = var.create_iam_role ? 1 : 0
  role       = aws_iam_role.node[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Extra caller-supplied policies
resource "aws_iam_role_policy_attachment" "additional" {
  for_each = var.create_iam_role ? var.iam_role_additional_policies : {}

  role       = aws_iam_role.node[0].name
  policy_arn = each.value
}

# ─────────────────────────────────────────────────────────────────────────────
# Placement Group  (optional)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_placement_group" "this" {
  count    = var.create_node_group && var.create_launch_template && var.placement_group_strategy != null ? 1 : 0
  name     = "${local.node_group_full_name}-pg"
  strategy = var.placement_group_strategy
  tags     = merge(local.common_tags, { Name = "${local.node_group_full_name}-pg" })
}

# ─────────────────────────────────────────────────────────────────────────────
# Launch Template
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_launch_template" "this" {
  count = var.create_node_group && var.create_launch_template ? 1 : 0

  name_prefix = "${local.node_group_full_name}-lt-"
  description = "Launch template for EKS node group ${local.node_group_full_name}"

  # ── IMDSv2 (mandatory – prevents SSRF-based credential theft) ──────────────
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # enforces IMDSv2
    http_put_response_hop_limit = var.imdsv2_hop_limit
    instance_metadata_tags      = "enabled" # lets EC2 read its own tags
  }

  # ── Root volume ───────────────────────────────────────────────────────────
  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.disk_size
      volume_type           = var.disk_type
      iops                  = var.disk_iops
      throughput            = var.disk_throughput
      encrypted             = var.disk_encrypted
      kms_key_id            = var.disk_kms_key_id
      delete_on_termination = true
    }
  }

  # ── Monitoring ────────────────────────────────────────────────────────────
  monitoring {
    enabled = var.enable_detailed_monitoring
  }

  # ── Placement group ───────────────────────────────────────────────────────
  dynamic "placement" {
    for_each = var.placement_group_strategy != null ? [1] : []
    content {
      group_name = aws_placement_group.this[0].name
    }
  }

  # ── User data (AL2 bootstrap) ─────────────────────────────────────────────
  # Only inject when bootstrap args or hooks are needed; otherwise leave empty
  # so EKS default bootstrap runs unmodified.
  user_data = (
    var.bootstrap_extra_args != "" ||
    var.pre_bootstrap_user_data != "" ||
    var.post_bootstrap_user_data != ""
  ) ? local.user_data : null

  # ── Network – tag network interfaces for cost allocation ──────────────────
  network_interfaces {
    associate_public_ip_address = false
    delete_on_termination       = true
    security_groups             = var.node_security_group_ids
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = local.node_group_full_name })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${local.node_group_full_name}-root" })
  }

  tag_specifications {
    resource_type = "network-interface"
    tags          = merge(local.common_tags, { Name = local.node_group_full_name })
  }

  tags = merge(local.common_tags, var.launch_template_tags, { Name = "${local.node_group_full_name}-lt" })

  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# EKS Node Group
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_eks_node_group" "this" {
  count = var.create_node_group ? 1 : 0

  cluster_name = var.cluster_name
  # Support both name and name_prefix patterns
  node_group_name        = var.node_group_name_prefix == null ? local.node_group_full_name : null
  node_group_name_prefix = var.node_group_name_prefix != null ? "${var.cluster_name}-${var.node_group_name_prefix}" : null

  node_role_arn   = local.effective_node_role_arn
  subnet_ids      = var.subnet_ids
  version         = var.cluster_version
  release_version = var.release_version
  instance_types  = var.instance_types
  capacity_type   = var.capacity_type
  ami_type        = var.ami_type
  # disk_size is set on the Launch Template when LT is used – setting both
  # causes an API error, so only pass it in the no-LT path.
  disk_size = var.create_launch_template ? null : var.disk_size

  # ── Launch Template reference ─────────────────────────────────────────────
  dynamic "launch_template" {
    for_each = var.create_launch_template ? [1] : []
    content {
      id      = aws_launch_template.this[0].id
      version = aws_launch_template.this[0].latest_version
    }
  }

  # ── Remote access (only valid without a launch template) ──────────────────
  dynamic "remote_access" {
    for_each = !var.create_launch_template && var.remote_access_ec2_ssh_key != null ? [1] : []
    content {
      ec2_ssh_key               = var.remote_access_ec2_ssh_key
      source_security_group_ids = var.remote_access_source_security_group_ids
    }
  }

  scaling_config {
    desired_size = var.desired_size
    max_size     = var.max_size
    min_size     = var.min_size
  }

  update_config {
    max_unavailable            = local.use_max_unavailable_count ? var.update_config_max_unavailable : null
    max_unavailable_percentage = local.use_max_unavailable_count ? null : var.update_config_max_unavailable_percentage
  }

  force_update_version = var.force_update_version

  labels = var.labels

  dynamic "taint" {
    for_each = var.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  tags = merge(local.common_tags, { Name = local.node_group_full_name })

  lifecycle {
    # Cluster Autoscaler / Karpenter manage desired_size at runtime
    ignore_changes = [scaling_config[0].desired_size]
    # Zero-downtime replacement when using name_prefix
    create_before_destroy = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.AmazonEC2ContainerRegistryReadOnly,
    aws_iam_role_policy_attachment.AmazonSSMManagedInstanceCore,
  ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Warm Pool  – FinOps: pre-warms instances so scale-out is near-instant
# Cost model: Stopped → EBS only ($0.08/GB/month); Running → full EC2 price
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_autoscaling_group_tag" "warm_pool_enabled" {
  # Tag the ASG so dashboards can identify warm-pool-enabled groups
  count = var.create_node_group && var.enable_warm_pool ? 1 : 0

  autoscaling_group_name = aws_eks_node_group.this[0].resources[0].autoscaling_groups[0].name

  tag {
    key                 = "finops:warm-pool"
    value               = "true"
    propagate_at_launch = false
  }
}

resource "aws_autoscaling_warm_pool" "this" {
  count = var.create_node_group && var.enable_warm_pool ? 1 : 0

  autoscaling_group_name      = aws_eks_node_group.this[0].resources[0].autoscaling_groups[0].name
  pool_state                  = var.warm_pool_state
  min_size                    = var.warm_pool_min_size
  max_group_prepared_capacity = var.warm_pool_max_prepared_capacity

  instance_reuse_policy {
    reuse_on_scale_in = var.warm_pool_instance_reuse_policy
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# Scheduled Scaling  – FinOps: zero-cost nights/weekends in dev/staging
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_autoscaling_schedule" "this" {
  for_each = var.create_node_group ? var.scheduled_scaling_actions : {}

  scheduled_action_name  = each.key
  autoscaling_group_name = aws_eks_node_group.this[0].resources[0].autoscaling_groups[0].name

  recurrence       = each.value.recurrence
  time_zone        = each.value.time_zone
  start_time       = each.value.start_time
  end_time         = each.value.end_time
  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_size
}
