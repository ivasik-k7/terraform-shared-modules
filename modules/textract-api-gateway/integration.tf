resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.textract_api.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.api_resources,
      aws_api_gateway_method.api_methods,
      aws_api_gateway_integration.textract_integration,
      aws_api_gateway_integration_response.integration_response
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_api_gateway_integration.textract_integration,
    aws_api_gateway_integration_response.integration_response
  ]
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.textract_api.id
  stage_name    = var.environment

  variables = {
    environment     = var.environment
    project_name    = var.project_name
    input_bucket    = local.input_bucket_name
    output_bucket   = local.output_bucket_name
    textract_region = data.aws_region.current.name
  }

  dynamic "access_log_settings" {
    for_each = var.logging_configuration.enabled ? [1] : []
    content {
      destination_arn = aws_cloudwatch_log_group.api_logs[0].arn
      format          = var.logging_configuration.log_format
    }
  }
}

resource "aws_api_gateway_method_settings" "settings" {
  for_each = local.enabled_routes

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name

  method_path = "${trimprefix(split(" ", each.key)[1], "/")}/${split(" ", each.key)[0]}"

  settings {
    metrics_enabled        = var.logging_configuration.enabled
    logging_level          = var.logging_configuration.execution_logging_level
    data_trace_enabled     = var.logging_configuration.log_full_response_data
    throttling_burst_limit = var.throttling_configuration.burst_limit
    throttling_rate_limit  = var.throttling_configuration.rate_limit
  }
}

resource "aws_cloudwatch_log_group" "api_logs" {
  count = var.logging_configuration.enabled ? 1 : 0

  name              = "API-Gateway-Execution-Logs_${aws_api_gateway_rest_api.textract_api.id}/${var.environment}"
  retention_in_days = var.logging_configuration.log_group_retention
  kms_key_id        = try(aws_kms_key.logs_key[0].arn, null)

  tags = local.common_tags
}

resource "aws_api_gateway_domain_name" "custom_domain" {
  count = local.has_custom_domain ? 1 : 0

  domain_name              = var.custom_domain.domain_name
  regional_certificate_arn = var.custom_domain.certificate_arn
  security_policy          = var.custom_domain.security_policy

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = local.common_tags
}

resource "aws_api_gateway_base_path_mapping" "mapping" {
  count = local.has_custom_domain ? 1 : 0

  domain_name = aws_api_gateway_domain_name.custom_domain[0].domain_name
  api_id      = aws_api_gateway_rest_api.textract_api.id
  stage_name  = aws_api_gateway_stage.stage.stage_name
}

resource "aws_route53_record" "api_record" {
  count = local.has_custom_domain && var.custom_domain.create_dns_record ? 1 : 0

  zone_id = var.custom_domain.hosted_zone_id
  name    = var.custom_domain.domain_name
  type    = "A"

  alias {
    name                   = aws_api_gateway_domain_name.custom_domain[0].regional_domain_name
    zone_id                = aws_api_gateway_domain_name.custom_domain[0].regional_zone_id
    evaluate_target_health = true
  }
}
