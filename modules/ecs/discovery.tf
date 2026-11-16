resource "aws_service_discovery_service" "this" {
  for_each = local.discovery_created

  name        = each.value.service_discovery.name != "" ? each.value.service_discovery.name : each.key
  description = "ECS workload ${each.key} on cluster ${var.name}"

  # Deregisters the instances ECS registered, so a replacement (name, namespace,
  # record type and routing policy all force one) or a destroy is not refused.
  force_destroy = true

  dns_config {
    namespace_id   = each.value.service_discovery.namespace_id
    routing_policy = each.value.service_discovery.routing_policy

    dns_records {
      type = each.value.service_discovery.dns_record_type
      ttl  = each.value.service_discovery.ttl
    }
  }

  health_check_custom_config {}

  tags = local.workload_tags[each.key]

  lifecycle {
    # AWS sets failure_threshold to 1 and returns it, and the provider replaces
    # the service when it differs from configuration; setting it instead is a
    # deprecation warning on aws 6.x (internal/service/servicediscovery/service.go).
    ignore_changes = [health_check_custom_config]
  }
}
