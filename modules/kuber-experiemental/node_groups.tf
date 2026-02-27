# ─────────────────────────────────────────────────────────────────────────────
# node_groups.tf – EKS managed node groups
#
# Each entry in var.node_groups becomes one module call.
# New enriched fields (Launch Template, FinOps, warm pool, scheduled scaling)
# are threaded through here; all carry safe defaults so existing callers don't
# need to change anything.
# ─────────────────────────────────────────────────────────────────────────────

module "node_group" {
  source   = "./modules/node_group"
  for_each = var.node_groups

  # ── Identity ────────────────────────────────────────────────────────────────
  cluster_name    = aws_eks_cluster.this.name
  cluster_version = var.cluster_version
  node_group_name = each.key

  # ── Networking ───────────────────────────────────────────────────────────────
  subnet_ids              = length(each.value.subnet_ids) > 0 ? each.value.subnet_ids : var.subnet_ids
  node_security_group_ids = [aws_security_group.node.id]

  # ── Compute ──────────────────────────────────────────────────────────────────
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = each.value.ami_type
  release_version = each.value.release_version

  # ── Scaling ──────────────────────────────────────────────────────────────────
  min_size     = each.value.min_size
  max_size     = each.value.max_size
  desired_size = each.value.desired_size

  # ── Storage / Launch Template ─────────────────────────────────────────────
  create_launch_template = each.value.create_launch_template
  disk_size              = each.value.disk_size
  disk_type              = each.value.disk_type
  disk_iops              = each.value.disk_iops
  disk_throughput        = each.value.disk_throughput
  disk_encrypted         = each.value.disk_encrypted
  disk_kms_key_id        = each.value.disk_kms_key_id
  imdsv2_hop_limit       = each.value.imdsv2_hop_limit

  # ── Bootstrap ────────────────────────────────────────────────────────────────
  bootstrap_extra_args     = each.value.bootstrap_extra_args
  pre_bootstrap_user_data  = each.value.pre_bootstrap_user_data
  post_bootstrap_user_data = each.value.post_bootstrap_user_data

  # ── Monitoring ───────────────────────────────────────────────────────────────
  enable_detailed_monitoring = each.value.enable_detailed_monitoring

  # ── Kubernetes metadata ───────────────────────────────────────────────────────
  labels = each.value.labels
  taints = each.value.taints

  # ── FinOps – Warm Pool ────────────────────────────────────────────────────────
  enable_warm_pool                = each.value.enable_warm_pool
  warm_pool_state                 = each.value.warm_pool_state
  warm_pool_min_size              = each.value.warm_pool_min_size
  warm_pool_max_prepared_capacity = each.value.warm_pool_max_prepared_capacity
  warm_pool_instance_reuse_policy = each.value.warm_pool_instance_reuse_policy

  # ── FinOps – Scheduled scaling ────────────────────────────────────────────────
  scheduled_scaling_actions = each.value.scheduled_scaling_actions

  tags = merge(local.common_tags, each.value.tags)

  depends_on = [aws_eks_cluster.this]
}
