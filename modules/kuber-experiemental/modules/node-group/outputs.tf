# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# ─────────────────────────────────────────────────────────────────────────────

# ── Node Group ────────────────────────────────────────────────────────────────

output "node_group_arn" {
  description = "ARN of the EKS node group."
  value       = var.create_node_group ? aws_eks_node_group.this[0].arn : null
}

output "node_group_id" {
  description = "EKS node group ID (cluster_name:node_group_name)."
  value       = var.create_node_group ? aws_eks_node_group.this[0].id : null
}

output "node_group_name" {
  description = "Full name of the EKS node group as registered with the cluster."
  value       = var.create_node_group ? aws_eks_node_group.this[0].node_group_name : null
}

output "status" {
  description = "Current status of the node group (ACTIVE, CREATING, etc.)."
  value       = var.create_node_group ? aws_eks_node_group.this[0].status : null
}

# ── IAM ───────────────────────────────────────────────────────────────────────

output "node_group_role_arn" {
  description = "ARN of the IAM role attached to the node group."
  value       = local.effective_node_role_arn
}

output "node_group_role_name" {
  description = "Name of the IAM role attached to the node group."
  value       = var.create_iam_role ? aws_iam_role.node[0].name : null
}

# ── Launch Template ───────────────────────────────────────────────────────────

output "launch_template_id" {
  description = "ID of the Launch Template. Null when create_launch_template = false."
  value       = var.create_node_group && var.create_launch_template ? aws_launch_template.this[0].id : null
}

output "launch_template_name" {
  description = "Name of the Launch Template."
  value       = var.create_node_group && var.create_launch_template ? aws_launch_template.this[0].name : null
}

output "launch_template_latest_version" {
  description = "Latest version number of the Launch Template."
  value       = var.create_node_group && var.create_launch_template ? aws_launch_template.this[0].latest_version : null
}

# ── Auto Scaling Group ────────────────────────────────────────────────────────

output "autoscaling_group_names" {
  description = <<-EOT
    List of Auto Scaling Group names backing this node group.
    Useful for attaching CloudWatch alarms, scheduled actions, and warm pools
    directly to the ASG outside this module.
  EOT
  value = var.create_node_group ? [
    for asg in aws_eks_node_group.this[0].resources[0].autoscaling_groups : asg.name
  ] : []
}

# ── Placement Group ───────────────────────────────────────────────────────────

output "placement_group_id" {
  description = "ID of the placement group. Null when not created."
  value       = var.create_node_group && var.create_launch_template && var.placement_group_strategy != null ? aws_placement_group.this[0].id : null
}

# ── FinOps metadata ───────────────────────────────────────────────────────────

output "finops_summary" {
  description = <<-EOT
    Human-readable FinOps configuration summary for this node group.
    Useful for cost-review dashboards or plan output scanning.
  EOT
  value = {
    capacity_type              = var.capacity_type
    instance_types             = var.instance_types
    min_size                   = var.min_size
    max_size                   = var.max_size
    warm_pool_enabled          = var.enable_warm_pool
    warm_pool_state            = var.enable_warm_pool ? var.warm_pool_state : null
    scheduled_scaling_actions  = keys(var.scheduled_scaling_actions)
    detailed_monitoring        = var.enable_detailed_monitoring
    disk_type                  = var.disk_type
    disk_encrypted             = var.disk_encrypted
    imdsv2_hop_limit           = var.create_launch_template ? var.imdsv2_hop_limit : "n/a (no launch template)"
  }
}
