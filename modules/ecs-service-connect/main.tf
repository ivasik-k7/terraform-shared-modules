data "aws_region" "current" {
  count = var.create_log_group && var.inject_default_log_configuration ? 1 : 0
}

# Cross-variable guards the provider can't express.
resource "terraform_data" "validations" {
  lifecycle {
    precondition {
      condition     = var.create_namespace || var.existing_namespace_arn != null
      error_message = "create_namespace is false but existing_namespace_arn is not set. Provide an existing namespace ARN or set create_namespace = true."
    }
    precondition {
      condition     = !var.enable_tls || var.tls_ca_arn != null
      error_message = "enable_tls is true but tls_ca_arn is not set. Provide the AWS Private CA ARN used to issue certificates."
    }
    # Service Connect TLS requires a role for certificate issuance. Catch the
    # missing role at plan time instead of at the consuming ECS service's apply.
    precondition {
      condition     = !local.tls_needs_role || var.tls_role_arn != null
      error_message = "Service Connect TLS is enabled (mesh-wide or per-service) without a role. Set tls_role_arn to the IAM role ECS uses to issue certificates."
    }
  }
}

resource "aws_service_discovery_http_namespace" "this" {
  count = var.create_namespace && var.namespace_type == "http" ? 1 : 0

  name        = coalesce(var.namespace_name, var.name)
  description = var.namespace_description

  tags = merge(
    var.tags,
    {
      Name = coalesce(var.namespace_name, var.name)
    }
  )
}

resource "aws_service_discovery_private_dns_namespace" "this" {
  count = var.create_namespace && var.namespace_type == "dns_private" ? 1 : 0

  name        = coalesce(var.namespace_name, var.name)
  description = var.namespace_description
  vpc         = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = coalesce(var.namespace_name, var.name)
    }
  )
}

resource "aws_cloudwatch_log_group" "service_connect" {
  count = var.create_log_group ? 1 : 0

  name              = coalesce(var.log_group_name, "/ecs/service-connect/${var.name}")
  retention_in_days = var.log_retention_in_days
  kms_key_id        = var.log_kms_key_id

  tags = merge(
    var.tags,
    {
      Name = coalesce(var.log_group_name, "/ecs/service-connect/${var.name}")
    }
  )
}
