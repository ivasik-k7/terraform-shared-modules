# cloud map service discovery (namespace is referenced, not created here).

resource "aws_service_discovery_service" "this" {
  for_each = local.services_with_discovery

  name = coalesce(each.value.service_discovery.name, each.key)

  dns_config {
    namespace_id   = each.value.service_discovery.namespace_id
    routing_policy = each.value.service_discovery.routing_policy

    dns_records {
      type = each.value.service_discovery.dns_record_type
      ttl  = each.value.service_discovery.dns_ttl
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }

  tags = merge(local.common_tags, each.value.tags, { "Name" = "${var.cluster_name}-${each.key}" })
}
