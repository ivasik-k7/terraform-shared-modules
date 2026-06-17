locals {
  # Resolve the namespace ARN/name from whichever source is active.
  namespace_arn = var.create_namespace ? (
    var.namespace_type == "http"
    ? aws_service_discovery_http_namespace.this[0].arn
    : aws_service_discovery_private_dns_namespace.this[0].arn
  ) : var.existing_namespace_arn

  namespace_name = var.create_namespace ? coalesce(var.namespace_name, var.name) : null

  log_group_name = var.create_log_group ? coalesce(var.log_group_name, "/ecs/service-connect/${var.name}") : null

  # Optional awslogs config injected into services that do not bring their own.
  default_log_configuration = var.create_log_group && var.inject_default_log_configuration ? {
    log_driver = "awslogs"
    options = {
      "awslogs-group"         = local.log_group_name
      "awslogs-region"        = data.aws_region.current[0].name
      "awslogs-stream-prefix" = "service-connect"
    }
    secret_option = []
  } : null

  # The TLS role is managed outside this module (cert issuance / IAM).
  tls_role_arn = var.tls_role_arn

  # TLS needs a role when it is enabled mesh-wide, or any per-service tls block
  # omits its own role_arn. Used to validate tls_role_arn is supplied.
  tls_needs_role = var.enable_tls || anytrue(flatten([
    for s in values(var.services) : [
      for svc in s.services : svc.tls != null && svc.tls.role_arn == null
    ]
  ]))

  # Mesh-wide TLS default, applied to exposed services that omit their own tls.
  default_tls = var.enable_tls ? {
    aws_pca_authority_arn = var.tls_ca_arn
    kms_key               = var.tls_kms_key
    role_arn              = local.tls_role_arn
  } : null

  # Build a complete, normalised service_connect_configuration per ECS service.
  # The shape matches the ecs module's service_connect_configuration input type
  # exactly, so the output can be passed straight through.
  service_connect_configurations = {
    for k, s in var.services : k => {
      enabled   = s.enabled
      namespace = local.namespace_arn
      service = [
        for svc in s.services : {
          port_name             = svc.port_name
          discovery_name        = coalesce(svc.discovery_name, svc.port_name)
          ingress_port_override = svc.ingress_port_override
          client_alias = [
            for ca in svc.client_aliases : {
              port     = ca.port
              dns_name = ca.dns_name
            }
          ]
          timeout = svc.timeout != null ? svc.timeout : var.default_timeout
          # Per-service tls wins; otherwise inherit the mesh-wide default. A
          # per-service role_arn falls back to the module's TLS role.
          tls = svc.tls != null ? {
            aws_pca_authority_arn = svc.tls.aws_pca_authority_arn
            kms_key               = svc.tls.kms_key
            role_arn              = try(coalesce(svc.tls.role_arn, local.tls_role_arn), null)
          } : local.default_tls
        }
      ]
      log_configuration = s.log_configuration != null ? s.log_configuration : local.default_log_configuration
    }
  }

  # Human-facing summary of how clients reach each exposed service.
  service_endpoints = {
    for k, s in var.services : k => flatten([
      for svc in s.services : [
        for ca in svc.client_aliases : "${coalesce(ca.dns_name, coalesce(svc.discovery_name, svc.port_name))}:${ca.port}"
      ]
    ])
  }
}
