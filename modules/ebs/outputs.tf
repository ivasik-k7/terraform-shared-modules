output "volume_ids" {
  description = "Map of logical volume names to EBS volume IDs"
  value       = { for k, v in aws_ebs_volume.this : k => v.id }
}

output "volume_arns" {
  description = "Map of logical volume names to EBS volume ARNs"
  value       = { for k, v in aws_ebs_volume.this : k => v.arn }
}

output "volume_availability_zones" {
  description = "Map of logical volume names to their Availability Zones"
  value       = { for k, v in aws_ebs_volume.this : k => v.availability_zone }
}

output "volume_sizes" {
  description = "Map of logical volume names to their size in GiB"
  value       = { for k, v in aws_ebs_volume.this : k => v.size }
}

output "attachments" {
  description = <<-EOT
    Map of attachments keyed by "<volume>.<index>". Each value contains the
    volume_id, instance_id, and device_name. Supports multiple attachments per
    volume (io1/io2 Multi-Attach).
  EOT
  value = {
    for k, v in aws_volume_attachment.this : k => {
      volume_id   = v.volume_id
      instance_id = v.instance_id
      device_name = v.device_name
    }
  }
}

output "attachment_device_names" {
  description = "Map of \"<volume>.<index>\" to the device name the volume is attached as"
  value       = { for k, v in aws_volume_attachment.this : k => v.device_name }
}

output "attachment_instance_ids" {
  description = "Map of \"<volume>.<index>\" to the instance ID the volume is attached to"
  value       = { for k, v in aws_volume_attachment.this : k => v.instance_id }
}

output "kms_key_id" {
  description = "ID of the created KMS key (null if not created)"
  value       = var.create_kms_key ? aws_kms_key.ebs[0].key_id : null
}

output "kms_key_arn" {
  description = "ARN of the created KMS key (null if not created)"
  value       = var.create_kms_key ? aws_kms_key.ebs[0].arn : null
}

output "kms_alias_arn" {
  description = "ARN of the created KMS alias (null if not created)"
  value       = var.create_kms_key ? aws_kms_alias.ebs[0].arn : null
}

output "effective_kms_key_id" {
  description = "The module-level KMS key applied to volumes that do not set a per-volume kms_key_id (created key, supplied key, or null for the AWS-managed default). Per-volume overrides are not reflected here"
  value       = local.resolved_kms_key_id
}

output "dlm_lifecycle_policy_id" {
  description = "ID of the DLM lifecycle policy (null if not created)"
  value       = var.create_lifecycle_policy ? aws_dlm_lifecycle_policy.this[0].id : null
}

output "dlm_lifecycle_policy_arn" {
  description = "ARN of the DLM lifecycle policy (null if not created)"
  value       = var.create_lifecycle_policy ? aws_dlm_lifecycle_policy.this[0].arn : null
}

output "dlm_role_arn" {
  description = "ARN of the IAM role used by DLM (created or supplied; null if no lifecycle policy)"
  value       = local.dlm_role_arn
}

output "burst_balance_alarm_arns" {
  description = "Map of logical volume names to BurstBalance CloudWatch alarm ARNs"
  value       = { for k, v in aws_cloudwatch_metric_alarm.burst_balance : k => v.arn }
}

output "idle_alarm_arns" {
  description = "Map of logical volume names to idle CloudWatch alarm ARNs"
  value       = { for k, v in aws_cloudwatch_metric_alarm.idle : k => v.arn }
}
