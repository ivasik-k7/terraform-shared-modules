resource "aws_api_gateway_rest_api" "textract_api" {
  name        = local.api_name
  description = var.api_description
  tags        = local.common_tags

  #   endpoint_configuration {
  #     types            = [local.endpoint_config.type]
  #     vpc_endpoint_ids = local.endpoint_config.vpc_endpoint_ids
  #   }

  policy = var.allowed_ips != [] ? jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action    = "execute-api:Invoke"
        Resource  = "execute-api:/*/*/*"
        Condition = {
          IpAddress = {
            "aws:SourceIp" = var.allowed_ips
          }
        }
      }
    ]
  }) : null
}

resource "aws_api_gateway_resource" "api_resources" {
  for_each = { for route in keys(local.enabled_routes) :
    trimprefix(split(" ", route)[1], "/") => trimprefix(split(" ", route)[1], "/")
    if split(" ", route)[1] != "/"
  }

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  parent_id   = aws_api_gateway_rest_api.textract_api.root_resource_id
  path_part   = each.value
}

resource "aws_api_gateway_method" "api_methods" {
  for_each = local.enabled_routes

  rest_api_id      = aws_api_gateway_rest_api.textract_api.id
  resource_id      = split(" ", each.key)[1] == "/" ? aws_api_gateway_rest_api.textract_api.root_resource_id : aws_api_gateway_resource.api_resources[trimprefix(split(" ", each.key)[1], "/")].id
  http_method      = split(" ", each.key)[0]
  authorization    = "NONE"
  api_key_required = var.enable_api_key

  request_parameters = {
    for param_key, param_value in try(each.value.request_parameters, {}) :
    replace(param_key, "integration.request", "method.request") => true
  }
}

resource "aws_api_gateway_integration" "textract_integration" {
  for_each = local.enabled_routes

  rest_api_id             = aws_api_gateway_rest_api.textract_api.id
  resource_id             = aws_api_gateway_method.api_methods[each.key].resource_id
  http_method             = aws_api_gateway_method.api_methods[each.key].http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = each.value.integration_uri
  credentials             = var.textract_role_arn

  request_parameters = try(each.value.request_parameters, {})

  request_templates    = each.value.request_templates
  passthrough_behavior = try(each.value.passthrough_behavior, "NEVER")

  depends_on = [aws_api_gateway_method.api_methods]
}

# Method Responses
resource "aws_api_gateway_method_response" "response_200" {
  for_each = local.enabled_routes

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  resource_id = aws_api_gateway_method.api_methods[each.key].resource_id
  http_method = aws_api_gateway_method.api_methods[each.key].http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = true
  }
}

resource "aws_api_gateway_integration_response" "integration_response" {
  for_each = local.enabled_routes

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  resource_id = aws_api_gateway_method.api_methods[each.key].resource_id
  http_method = aws_api_gateway_method.api_methods[each.key].http_method
  status_code = aws_api_gateway_method_response.response_200[each.key].status_code

  selection_pattern = try(each.value.selection_pattern, null)

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin" = "'*'"
  }

  #   response_templates = try(each.value.response_templates, {})

  depends_on = [aws_api_gateway_integration.textract_integration]
}

resource "aws_api_gateway_method" "options_method" {
  for_each = toset([for route in keys(local.enabled_routes) : split(" ", route)[1]])

  rest_api_id   = aws_api_gateway_rest_api.textract_api.id
  resource_id   = each.value == "/" ? aws_api_gateway_rest_api.textract_api.root_resource_id : aws_api_gateway_resource.api_resources[trimprefix(each.value, "/")].id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "options_integration" {
  for_each = aws_api_gateway_method.options_method

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  type        = "MOCK"

  request_templates = {
    "application/json" = jsonencode({
      statusCode = 200
    })
  }
}

resource "aws_api_gateway_method_response" "options_200" {
  for_each = aws_api_gateway_method.options_method

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Access-Control-Allow-Origin"  = true
  }
}

resource "aws_api_gateway_integration_response" "options_integration_response" {
  for_each = aws_api_gateway_method.options_method

  rest_api_id = aws_api_gateway_rest_api.textract_api.id
  resource_id = each.value.resource_id
  http_method = each.value.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Headers" = "'${join(",", var.cors_configuration.allow_headers)}'"
    "method.response.header.Access-Control-Allow-Methods" = "'${join(",", var.cors_configuration.allow_methods)}'"
    "method.response.header.Access-Control-Allow-Origin"  = "'${join(",", var.cors_configuration.allow_origins)}'"
  }

  depends_on = [aws_api_gateway_integration.options_integration]
}
