# asg / launch template

output "autoscaling_group_name" {
  description = "Name of the bastion Auto Scaling Group"
  value       = one(aws_autoscaling_group.this[*].name)
}

output "autoscaling_group_arn" {
  description = "ARN of the bastion Auto Scaling Group"
  value       = one(aws_autoscaling_group.this[*].arn)
}

output "autoscaling_group_id" {
  description = "ID of the bastion Auto Scaling Group"
  value       = one(aws_autoscaling_group.this[*].id)
}

output "launch_template_id" {
  description = "ID of the bastion launch template"
  value       = one(aws_launch_template.this[*].id)
}

output "launch_template_arn" {
  description = "ARN of the bastion launch template"
  value       = one(aws_launch_template.this[*].arn)
}

output "launch_template_latest_version" {
  description = "Latest version of the bastion launch template"
  value       = one(aws_launch_template.this[*].latest_version)
}

# security group

output "security_group_id" {
  description = "ID of the created security group (null if not created)"
  value       = local.create_security_group ? aws_security_group.this[0].id : null
}

output "security_group_arn" {
  description = "ARN of the created security group (null if not created)"
  value       = local.create_security_group ? aws_security_group.this[0].arn : null
}

# iam

output "iam_role_arn" {
  description = "ARN of the created IAM role (null when an external instance profile is used)"
  value       = local.create_iam_role ? aws_iam_role.this[0].arn : null
}

output "iam_role_name" {
  description = "Name of the created IAM role (null when an external instance profile is used)"
  value       = local.create_iam_role ? aws_iam_role.this[0].name : null
}

output "iam_instance_profile_name" {
  description = "Instance profile attached to the bastion (created or provided)"
  value       = local.instance_profile_name
}

output "iam_instance_profile_arn" {
  description = "ARN of the created instance profile (null when an external profile is used)"
  value       = local.create_iam_role ? aws_iam_instance_profile.this[0].arn : null
}

# schedules

output "scheduled_action_names" {
  description = "Names of the scheduled scaling actions (including auto-shutdown)"
  value       = [for k, s in aws_autoscaling_schedule.this : s.scheduled_action_name]
}

output "auto_shutdown_enabled" {
  description = "Whether the auto-shutdown convenience schedule is active"
  value       = var.auto_shutdown != null && try(var.auto_shutdown.enabled, false)
}

# alarms

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms created (empty when disabled)"
  value       = [for a in aws_cloudwatch_metric_alarm.status_check_failed : a.alarm_name]
}
