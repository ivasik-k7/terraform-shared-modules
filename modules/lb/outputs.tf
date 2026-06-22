# ============================================================================
# LOAD BALANCER
# ============================================================================

output "arn" {
  description = "ARN of the load balancer"
  value       = one(aws_lb.this[*].arn)
}

output "arn_suffix" {
  description = "ARN suffix for use with CloudWatch metrics"
  value       = one(aws_lb.this[*].arn_suffix)
}

output "id" {
  description = "ID (ARN) of the load balancer"
  value       = one(aws_lb.this[*].id)
}

output "name" {
  description = "Name of the load balancer"
  value       = one(aws_lb.this[*].name)
}

output "dns_name" {
  description = "DNS name of the load balancer"
  value       = one(aws_lb.this[*].dns_name)
}

output "zone_id" {
  description = "Route 53 hosted zone ID of the load balancer (for alias records)"
  value       = one(aws_lb.this[*].zone_id)
}

# ============================================================================
# SECURITY GROUP
# ============================================================================

output "security_group_id" {
  description = "ID of the security group created for the load balancer (null if not created)"
  value       = local.create_security_group ? aws_security_group.this[0].id : null
}

output "security_group_arn" {
  description = "ARN of the security group created for the load balancer (null if not created)"
  value       = local.create_security_group ? aws_security_group.this[0].arn : null
}

# ============================================================================
# TARGET GROUPS
# ============================================================================

output "target_group_arns" {
  description = "Map of target group key to ARN (attach ECS services, EKS TargetGroupBindings, etc.)"
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn }
}

output "target_group_arn_suffixes" {
  description = "Map of target group key to ARN suffix (for CloudWatch metrics)"
  value       = { for k, tg in aws_lb_target_group.this : k => tg.arn_suffix }
}

output "target_group_names" {
  description = "Map of target group key to name"
  value       = { for k, tg in aws_lb_target_group.this : k => tg.name }
}

output "target_groups" {
  description = "Full target group resource objects keyed by target group key"
  value       = aws_lb_target_group.this
}

# ============================================================================
# LISTENERS & RULES
# ============================================================================

output "listener_arns" {
  description = "Map of listener key to ARN"
  value       = { for k, l in aws_lb_listener.this : k => l.arn }
}

output "listeners" {
  description = "Full listener resource objects keyed by listener key"
  value       = aws_lb_listener.this
  sensitive   = true # may contain OIDC client_secret in authenticate actions
}

output "listener_certificate_arns" {
  description = "Map of additional (SNI) certificate attachment key to certificate ARN"
  value       = { for k, c in aws_lb_listener_certificate.this : k => c.certificate_arn }
}

output "listener_rule_arns" {
  description = "Map of listener rule key to ARN"
  value       = { for k, r in aws_lb_listener_rule.this : k => r.arn }
}

# ============================================================================
# WAF / ROUTE 53 / ALARMS
# ============================================================================

output "web_acl_association_id" {
  description = "ID of the WAFv2 web ACL association (null if not associated)"
  value       = length(aws_wafv2_web_acl_association.this) > 0 ? aws_wafv2_web_acl_association.this[0].id : null
}

output "route53_record_fqdns" {
  description = "Map of Route 53 record key to FQDN"
  value       = { for k, r in aws_route53_record.this : k => r.fqdn }
}

output "cloudwatch_alarm_names" {
  description = "Names of the CloudWatch alarms created"
  value = concat(
    [for k, a in aws_cloudwatch_metric_alarm.unhealthy_hosts : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.elb_5xx : a.alarm_name],
    [for a in aws_cloudwatch_metric_alarm.target_response_time : a.alarm_name],
  )
}
