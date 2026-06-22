output "efs_id" {
  description = "The ID of the EFS file system"
  value       = aws_efs_file_system.this.id
}

output "efs_arn" {
  description = "The ARN of the EFS file system"
  value       = aws_efs_file_system.this.arn
}

output "efs_dns_name" {
  description = "The DNS name for the EFS file system"
  value       = aws_efs_file_system.this.dns_name
}

# Convenience aliases (common naming used by callers/examples).
output "file_system_id" {
  description = "The ID of the EFS file system (alias of efs_id)"
  value       = aws_efs_file_system.this.id
}

output "file_system_arn" {
  description = "The ARN of the EFS file system (alias of efs_arn)"
  value       = aws_efs_file_system.this.arn
}

output "file_system_dns_name" {
  description = "The DNS name for the EFS file system (alias of efs_dns_name)"
  value       = aws_efs_file_system.this.dns_name
}

output "efs_size_in_bytes" {
  description = "The latest known metered size (in bytes) of data stored in the file system"
  value       = aws_efs_file_system.this.size_in_bytes
}

output "efs_number_of_mount_targets" {
  description = "The current number of mount targets that the file system has"
  value       = aws_efs_file_system.this.number_of_mount_targets
}

output "mount_target_ids" {
  description = "Map of subnet IDs to mount target IDs"
  value       = { for k, v in aws_efs_mount_target.this : k => v.id }
}

output "mount_target_network_interface_ids" {
  description = "Map of subnet IDs to mount target network interface IDs"
  value       = { for k, v in aws_efs_mount_target.this : k => v.network_interface_id }
}

output "mount_target_dns_names" {
  description = "Map of subnet IDs to mount target DNS names"
  value       = { for k, v in aws_efs_mount_target.this : k => v.mount_target_dns_name }
}

output "mount_target_ip_addresses" {
  description = "Map of subnet IDs to mount target IP addresses"
  value       = { for k, v in aws_efs_mount_target.this : k => v.ip_address }
}

output "access_point_ids" {
  description = "Map of access point names to their IDs"
  value       = { for k, v in aws_efs_access_point.this : k => v.id }
}

output "access_point_arns" {
  description = "Map of access point names to their ARNs"
  value       = { for k, v in aws_efs_access_point.this : k => v.arn }
}

output "access_point_file_system_arns" {
  description = "Map of access point names to their file system ARNs"
  value       = { for k, v in aws_efs_access_point.this : k => v.file_system_arn }
}

output "security_group_id" {
  description = "The ID of the security group (if created)"
  value       = var.create_security_group ? aws_security_group.efs[0].id : null
}

output "security_group_arn" {
  description = "The ARN of the security group (if created)"
  value       = var.create_security_group ? aws_security_group.efs[0].arn : null
}

output "replication_configuration_destination_file_system_id" {
  description = "The file system ID of the replica"
  value       = var.replication_configuration != null ? aws_efs_replication_configuration.this[0].destination[0].file_system_id : null
}

output "replication_configuration_destination_region" {
  description = "The region of the replica file system"
  value       = var.replication_configuration != null ? aws_efs_replication_configuration.this[0].destination[0].region : null
}

# ============================================================================
# POLICY & MONITORING OUTPUTS
# ============================================================================

output "file_system_policy" {
  description = "The effective file system policy JSON applied (null when none)"
  value       = local.file_system_policy
}

output "backup_policy_enabled" {
  description = "Whether an EFS backup policy is managed by this module"
  value       = var.enable_backup_policy
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms created for the file system"
  value = compact([
    length(aws_cloudwatch_metric_alarm.burst_credit_balance) > 0 ? aws_cloudwatch_metric_alarm.burst_credit_balance[0].alarm_name : "",
    length(aws_cloudwatch_metric_alarm.percent_io_limit) > 0 ? aws_cloudwatch_metric_alarm.percent_io_limit[0].alarm_name : "",
  ])
}
