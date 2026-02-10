output "security_group_id" {
  description = "ID of the bastion security group."
  value       = aws_security_group.bastion.id
}

output "security_group_arn" {
  description = "ARN of the bastion security group."
  value       = aws_security_group.bastion.arn
}

output "launch_template_id" {
  description = "ID of the bastion launch template."
  value       = aws_launch_template.bastion.id
}

output "launch_template_latest_version" {
  description = "Latest version number of the bastion launch template."
  value       = aws_launch_template.bastion.latest_version
}

output "autoscaling_group_name" {
  description = "Name of the bastion Auto Scaling Group."
  value       = aws_autoscaling_group.bastion.name
}

output "autoscaling_group_arn" {
  description = "ARN of the bastion Auto Scaling Group."
  value       = aws_autoscaling_group.bastion.arn
}

output "iam_role_arn" {
  description = "ARN of the IAM role attached to the bastion (null when an external profile is used)."
  value       = local.create_iam_resources ? aws_iam_role.bastion[0].arn : null
}

output "iam_role_name" {
  description = "Name of the IAM role attached to the bastion (null when an external profile is used)."
  value       = local.create_iam_resources ? aws_iam_role.bastion[0].name : null
}

output "iam_instance_profile_arn" {
  description = "ARN of the instance profile in use (module-created or externally provided)."
  value       = local.instance_profile_arn
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch Log Group (null when cloudwatch_logs_enabled = false)."
  value       = var.cloudwatch_logs_enabled ? aws_cloudwatch_log_group.bastion[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch Log Group (null when cloudwatch_logs_enabled = false)."
  value       = var.cloudwatch_logs_enabled ? aws_cloudwatch_log_group.bastion[0].arn : null
}

output "eip_public_ip" {
  description = "Public IP of the Elastic IP (null when eip_enabled = false)."
  value       = var.eip_enabled && var.asg_desired_capacity == 1 ? aws_eip.bastion[0].public_ip : null
}

output "eip_allocation_id" {
  description = "Allocation ID of the Elastic IP (null when eip_enabled = false)."
  value       = var.eip_enabled && var.asg_desired_capacity == 1 ? aws_eip.bastion[0].id : null
}

output "ami_id" {
  description = "ID of the AMI used by the bastion launch template."
  value       = local.ami_id
}

output "ssm_connect_command" {
  description = "AWS CLI command to start a Session Manager session with the bastion (requires ssm_enabled = true)."
  value       = var.ssm_enabled ? "aws ssm start-session --target <INSTANCE_ID> --region ${data.aws_region.current.name}" : null
}
