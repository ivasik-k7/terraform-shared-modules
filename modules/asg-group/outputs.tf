# ============================================================================
# AUTO SCALING GROUP
# ============================================================================

output "autoscaling_group_arn" {
  description = "ASG ARN. Pass to ecs-orchestrator's ec2_capacity_providers[*].auto_scaling_group_arn, or reference from any consumer."
  value       = one(aws_autoscaling_group.this[*].arn)
}

output "autoscaling_group_name" {
  description = "ASG name."
  value       = one(aws_autoscaling_group.this[*].name)
}

output "autoscaling_group_id" {
  description = "ASG id."
  value       = one(aws_autoscaling_group.this[*].id)
}

# ============================================================================
# LAUNCH TEMPLATE
# ============================================================================

output "launch_template_id" {
  description = "Launch template id."
  value       = one(aws_launch_template.this[*].id)
}

output "launch_template_latest_version" {
  description = "Latest launch template version."
  value       = one(aws_launch_template.this[*].latest_version)
}

# ============================================================================
# IAM
# ============================================================================

output "iam_role_arn" {
  description = "ARN of the created instance role (null when not created)."
  value       = local.create_iam ? aws_iam_role.this[0].arn : null
}

output "iam_role_name" {
  description = "Name of the created instance role (null when not created)."
  value       = local.create_iam ? aws_iam_role.this[0].name : null
}

output "instance_profile_name" {
  description = "Instance profile attached to the instances (created or provided)."
  value       = local.instance_profile_name
}

output "instance_profile_arn" {
  description = "ARN of the created instance profile (null when not created)."
  value       = local.create_iam ? aws_iam_instance_profile.this[0].arn : null
}

# ============================================================================
# SECURITY GROUP
# ============================================================================

output "security_group_id" {
  description = "ID of the security group created for the instances (null when not created)."
  value       = local.create_security_group ? aws_security_group.this[0].id : null
}

output "security_group_ids" {
  description = "All security group IDs attached to the instances (created + provided)."
  value       = local.security_group_ids
}

# ============================================================================
# SCALING & MONITORING
# ============================================================================

output "target_tracking_policy_arns" {
  description = "Map of policy key to target-tracking scaling policy ARN."
  value       = { for k, p in aws_autoscaling_policy.target_tracking : k => p.arn }
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms created (empty when disabled)."
  value = compact([
    one(aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name),
    one(aws_cloudwatch_metric_alarm.in_service_low[*].alarm_name),
  ])
}
