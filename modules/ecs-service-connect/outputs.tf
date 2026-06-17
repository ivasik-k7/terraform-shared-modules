output "namespace_arn" {
  description = "ARN of the Cloud Map namespace (created or referenced)"
  value       = local.namespace_arn
}

output "namespace_id" {
  description = "ID of the created Cloud Map namespace (null when referencing an existing namespace)"
  value = var.create_namespace ? (
    var.namespace_type == "http"
    ? aws_service_discovery_http_namespace.this[0].id
    : aws_service_discovery_private_dns_namespace.this[0].id
  ) : null
}

output "namespace_name" {
  description = "Name of the created Cloud Map namespace (null when referencing an existing namespace)"
  value       = local.namespace_name
}

output "namespace_hosted_zone" {
  description = "Route 53 hosted zone ID backing a dns_private namespace (null otherwise)"
  value       = var.create_namespace && var.namespace_type == "dns_private" ? aws_service_discovery_private_dns_namespace.this[0].hosted_zone : null
}

output "log_group_name" {
  description = "Name of the Service Connect log group (null if not created)"
  value       = local.log_group_name
}

output "log_group_arn" {
  description = "ARN of the Service Connect log group (null if not created)"
  value       = var.create_log_group ? aws_cloudwatch_log_group.service_connect[0].arn : null
}

output "service_connect_configurations" {
  description = <<-EOT
    Map of ECS service name -> a complete service_connect_configuration object.
    Pass an entry directly into the ecs module's service_connect_configuration
    input, e.g.: service_connect_configuration = module.sc.service_connect_configurations["api"]
  EOT
  value       = local.service_connect_configurations
}

output "service_endpoints" {
  description = "Map of ECS service name -> list of \"<dns_name>:<port>\" client endpoints exposed in the namespace"
  value       = local.service_endpoints
}

output "tls_role_arn" {
  description = "The externally-managed Service Connect TLS role ARN passed through to TLS-enabled services (echoes the tls_role_arn input)"
  value       = local.tls_role_arn
}
