output "web_acl_arn" {
  description = "Web ACL ARN. For CloudFront, set this as web_acl_id on the aws_cloudfront_distribution."
  value       = one(aws_wafv2_web_acl.this[*].arn)
}

output "web_acl_id" {
  description = "Web ACL id."
  value       = one(aws_wafv2_web_acl.this[*].id)
}

output "web_acl_name" {
  description = "Web ACL name."
  value       = one(aws_wafv2_web_acl.this[*].name)
}

output "web_acl_capacity" {
  description = "Consumed WCU (Web ACL Capacity Units) - watch against the 1500 default ceiling as you add rules."
  value       = one(aws_wafv2_web_acl.this[*].capacity)
}

output "ip_set_allow_arns" {
  description = "Map of allowlist name => IP set ARN (reuse across ACLs or reference elsewhere)."
  value       = { for k, s in aws_wafv2_ip_set.allow : k => s.arn }
}

output "ip_set_block_arns" {
  description = "Map of blocklist name => IP set ARN."
  value       = { for k, s in aws_wafv2_ip_set.block : k => s.arn }
}

output "rule_priorities" {
  description = "The auto-assigned priority of every composed rule (id => priority), for auditing evaluation order."
  value       = local.priority
}

output "logging_enabled" {
  description = "True when WAF logging is configured."
  value       = local.create && var.enable_logging
}
