# API Gateway Module

Production-grade Terraform module for deploying Amazon API Gateway (REST API and HTTP API) with features for building serverless APIs.

## Features

- **REST API (v1)** - Full-featured REST API with extensive customization
- **HTTP API (v2)** - Modern, low-latency HTTP API with simplified configuration
- **WebSocket API** - Real-time bidirectional communication support
- **Custom Authorizers** - Lambda, Cognito, and IAM authorization
- **Usage Plans & API Keys** - Rate limiting and quota management
- **Custom Domains** - Custom domain names with SSL/TLS certificates
- **VPC Integration** - Private API endpoints with VPC links
- **Request/Response Transformation** - Mapping templates and validation
- **CORS Support** - Built-in CORS configuration for HTTP APIs
- **Deployment Management** - Stage-based deployments with canary releases
- **Monitoring & Logging** - CloudWatch integration and X-Ray tracing

## Quick Start

### Basic HTTP API

```hcl
module "api_gateway" {
  source = "./modules/api-gateway"

  create_http_api = true
  http_api_name   = "my-http-api"

  http_api_cors_configuration = {
    allow_origins = ["https://example.com"]
    allow_methods = ["GET", "POST", "PUT", "DELETE"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  http_api_integrations = {
    lambda = {
      integration_type = "AWS_PROXY"
      integration_uri  = aws_lambda_function.api.invoke_arn
    }
  }

  http_api_routes = {
    get_items = {
      route_key       = "GET /items"
      integration_key = "lambda"
    }
  }

  http_api_stages = {
    default = {
      name        = "$default"
      auto_deploy = true
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### REST API with Cognito Authorizer

```hcl
module "api_gateway_rest" {
  source = "./modules/api-gateway"

  create_rest_api = true
  rest_api_name   = "my-rest-api"

  rest_api_authorizers = {
    cognito_auth = {
      name          = "cognito-authorizer"
      type          = "COGNITO_USER_POOLS"
      provider_arns = [aws_cognito_user_pool.main.arn]
    }
  }

  rest_api_resources = {
    items = {
      path_part = "items"
    }
  }

  rest_api_methods = {
    get_items = {
      resource_key  = "items"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
    }
  }

  rest_api_integrations = {
    get_items = {
      method_key              = "get_items"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.api.invoke_arn
    }
  }

  rest_api_stages = {
    prod = {
      stage_name           = "prod"
      xray_tracing_enabled = true
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### HTTP API with JWT Authorizer

```hcl
module "api_gateway_jwt" {
  source = "./modules/api-gateway"

  create_http_api = true
  http_api_name   = "jwt-protected-api"

  http_api_authorizers = {
    jwt = {
      authorizer_type = "JWT"
      name            = "jwt-authorizer"
      jwt_configuration = {
        audience = ["api.example.com"]
        issuer   = "https://cognito-idp.us-east-1.amazonaws.com/us-east-1_XXXXX"
      }
    }
  }

  http_api_routes = {
    protected = {
      route_key          = "GET /protected"
      authorization_type = "JWT"
      authorizer_key     = "jwt"
      integration_key    = "lambda"
    }
  }

  http_api_integrations = {
    lambda = {
      integration_type = "AWS_PROXY"
      integration_uri  = aws_lambda_function.api.invoke_arn
    }
  }

  http_api_stages = {
    prod = {
      name        = "prod"
      auto_deploy = true
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### REST API with Usage Plans and API Keys

```hcl
module "api_gateway_usage" {
  source = "./modules/api-gateway"

  create_rest_api = true
  rest_api_name   = "metered-api"

  rest_api_resources = {
    data = {
      path_part = "data"
    }
  }

  rest_api_methods = {
    get_data = {
      resource_key     = "data"
      http_method      = "GET"
      authorization    = "NONE"
      api_key_required = true
    }
  }

  rest_api_integrations = {
    get_data = {
      method_key              = "get_data"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.api.invoke_arn
    }
  }

  rest_api_stages = {
    prod = {
      stage_name = "prod"
    }
  }

  rest_api_usage_plans = {
    basic = {
      name = "basic-plan"
      api_stages = [
        {
          stage = "prod"
        }
      ]
      quota_settings = {
        limit  = 10000
        period = "MONTH"
      }
      throttle_settings = {
        burst_limit = 100
        rate_limit  = 50
      }
    }
  }

  rest_api_keys = {
    client_1 = {
      name    = "client-1-key"
      enabled = true
    }
  }

  rest_api_usage_plan_keys = {
    client_1_basic = {
      api_key_key    = "client_1"
      usage_plan_key = "basic"
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### REST API with Custom Domain

```hcl
module "api_gateway_domain" {
  source = "./modules/api-gateway"

  create_rest_api = true
  rest_api_name   = "custom-domain-api"

  rest_api_resources = {
    api = {
      path_part = "api"
    }
  }

  rest_api_methods = {
    get_api = {
      resource_key  = "api"
      http_method   = "GET"
      authorization = "NONE"
    }
  }

  rest_api_integrations = {
    get_api = {
      method_key              = "get_api"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.api.invoke_arn
    }
  }

  rest_api_stages = {
    prod = {
      stage_name = "prod"
    }
  }

  rest_api_domain_names = {
    main = {
      domain_name              = "api.example.com"
      regional_certificate_arn = aws_acm_certificate.api.arn
      endpoint_configuration = {
        types = ["REGIONAL"]
      }
    }
  }

  rest_api_base_path_mappings = {
    main = {
      domain_key = "main"
      stage_key  = "prod"
      base_path  = "v1"
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### HTTP API with VPC Link

```hcl
module "api_gateway_vpc" {
  source = "./modules/api-gateway"

  create_http_api = true
  http_api_name   = "vpc-integrated-api"

  http_api_vpc_links = {
    main = {
      name               = "main-vpc-link"
      security_group_ids = [aws_security_group.api.id]
      subnet_ids         = aws_subnet.private[*].id
    }
  }

  http_api_integrations = {
    alb = {
      integration_type   = "HTTP_PROXY"
      integration_uri    = "http://internal-alb.example.com"
      integration_method = "ANY"
      connection_type    = "VPC_LINK"
      connection_id      = "main"
    }
  }

  http_api_routes = {
    proxy = {
      route_key       = "ANY /{proxy+}"
      integration_key = "alb"
    }
  }

  http_api_stages = {
    prod = {
      name        = "prod"
      auto_deploy = true
    }
  }

  tags = {
    Environment = "production"
  }
}
```

### REST API with Request Validation

```hcl
module "api_gateway_validation" {
  source = "./modules/api-gateway"

  create_rest_api = true
  rest_api_name   = "validated-api"

  rest_api_request_validators = {
    body_validator = {
      name                        = "body-validator"
      validate_request_body       = true
      validate_request_parameters = true
    }
  }

  rest_api_models = {
    user = {
      name         = "User"
      content_type = "application/json"
      schema = jsonencode({
        type = "object"
        properties = {
          name = {
            type = "string"
          }
          email = {
            type = "string"
          }
        }
        required = ["name", "email"]
      })
    }
  }

  rest_api_resources = {
    users = {
      path_part = "users"
    }
  }

  rest_api_methods = {
    post_user = {
      resource_key         = "users"
      http_method          = "POST"
      authorization        = "NONE"
      request_validator_id = "body_validator"
      request_models = {
        "application/json" = "User"
      }
    }
  }

  rest_api_integrations = {
    post_user = {
      method_key              = "post_user"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.api.invoke_arn
    }
  }

  tags = {
    Environment = "production"
  }
}
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| aws       | ~> 5.0   |

## Providers

| Name | Version |
| ---- | ------- |
| aws  | ~> 5.0  |

## Resources

### REST API Resources

| Name                                                                                                                                    | Type     |
| --------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [aws_api_gateway_rest_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_rest_api)       | resource |
| [aws_api_gateway_resource.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_resource)       | resource |
| [aws_api_gateway_method.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_method)           | resource |
| [aws_api_gateway_integration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_integration) | resource |
| [aws_api_gateway_authorizer.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_authorizer)   | resource |
| [aws_api_gateway_deployment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_deployment)   | resource |
| [aws_api_gateway_stage.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_stage)             | resource |
| [aws_api_gateway_usage_plan.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_usage_plan)   | resource |
| [aws_api_gateway_api_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_api_key)         | resource |
| [aws_api_gateway_domain_name.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/api_gateway_domain_name) | resource |

### HTTP API Resources

| Name                                                                                                                                      | Type     |
| ----------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [aws_apigatewayv2_api.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_api)                 | resource |
| [aws_apigatewayv2_authorizer.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_authorizer)   | resource |
| [aws_apigatewayv2_integration.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_integration) | resource |
| [aws_apigatewayv2_route.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_route)             | resource |
| [aws_apigatewayv2_stage.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_stage)             | resource |
| [aws_apigatewayv2_domain_name.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/apigatewayv2_domain_name) | resource |

## Inputs

### REST API Configuration

| Name                         | Description                                         | Type     | Default | Required |
| ---------------------------- | --------------------------------------------------- | -------- | ------- | :------: |
| create_rest_api              | Whether to create a REST API                        | `bool`   | `false` |    no    |
| rest_api_name                | Name of the REST API                                | `string` | `""`    |   yes    |
| rest_api_description         | Description of the REST API                         | `string` | `null`  |    no    |
| endpoint_configuration       | Endpoint configuration for the REST API             | `object` | `null`  |    no    |
| disable_execute_api_endpoint | Whether to disable the default execute-api endpoint | `bool`   | `false` |    no    |

### HTTP API Configuration

| Name                        | Description                         | Type     | Default  | Required |
| --------------------------- | ----------------------------------- | -------- | -------- | :------: |
| create_http_api             | Whether to create an HTTP API       | `bool`   | `false`  |    no    |
| http_api_name               | Name of the HTTP API                | `string` | `""`     |   yes    |
| http_api_protocol_type      | Protocol type (HTTP or WEBSOCKET)   | `string` | `"HTTP"` |    no    |
| http_api_cors_configuration | CORS configuration for the HTTP API | `object` | `null`   |    no    |

### Authorization

| Name                 | Description                 | Type          | Default | Required |
| -------------------- | --------------------------- | ------------- | ------- | :------: |
| rest_api_authorizers | Map of REST API authorizers | `map(object)` | `{}`    |    no    |
| http_api_authorizers | Map of HTTP API authorizers | `map(object)` | `{}`    |    no    |

### Usage Plans & API Keys

| Name                 | Description                 | Type          | Default | Required |
| -------------------- | --------------------------- | ------------- | ------- | :------: |
| rest_api_usage_plans | Map of REST API usage plans | `map(object)` | `{}`    |    no    |
| rest_api_keys        | Map of REST API keys        | `map(object)` | `{}`    |    no    |

## Outputs

### REST API Outputs

| Name                       | Description                            |
| -------------------------- | -------------------------------------- |
| rest_api_id                | ID of the REST API                     |
| rest_api_arn               | ARN of the REST API                    |
| rest_api_execution_arn     | Execution ARN of the REST API          |
| rest_api_stage_invoke_urls | Map of REST API stage invoke URLs      |
| rest_api_key_values        | Map of REST API key values (sensitive) |

### HTTP API Outputs

| Name                       | Description                       |
| -------------------------- | --------------------------------- |
| http_api_id                | ID of the HTTP API                |
| http_api_arn               | ARN of the HTTP API               |
| http_api_endpoint          | Endpoint of the HTTP API          |
| http_api_stage_invoke_urls | Map of HTTP API stage invoke URLs |

## Free Tier Limits

AWS API Gateway Free Tier includes:

- **1 million REST API calls** per month for 12 months
- **1 million HTTP API calls** per month for 12 months
- **1 million messages** for WebSocket APIs for 12 months
- **750,000 connection minutes** for WebSocket APIs for 12 months

After free tier:

- REST API: $3.50 per million requests
- HTTP API: $1.00 per million requests (71% cheaper)
- WebSocket: $1.00 per million messages

## Best Practices

### Performance

- **Use HTTP API** - 71% cheaper and lower latency than REST API
- **Enable Caching** - Reduce backend calls (REST API only)
- **Optimize Payload** - Use compression for large responses
- **Connection Reuse** - Keep-alive connections for better performance

### Security

- **Use Authorizers** - Cognito, Lambda, or IAM for authentication
- **API Keys** - For usage tracking and rate limiting
- **Resource Policies** - Restrict access by IP or VPC
- **TLS 1.2+** - Enforce minimum TLS version
- **CORS Configuration** - Restrict allowed origins
- **Request Validation** - Validate requests before backend processing

### Cost Optimization

- **Choose HTTP API** - Use HTTP API for cost savings when possible
- **Enable Caching** - Reduce backend invocations (REST API)
- **Usage Plans** - Implement rate limiting to prevent abuse
- **Monitor Usage** - Track API calls and optimize high-traffic endpoints
- **Regional Endpoints** - Use regional endpoints to reduce latency and cost

### Monitoring

- **CloudWatch Metrics** - Monitor latency, errors, and request counts
- **Access Logging** - Enable detailed request/response logging
- **X-Ray Tracing** - Distributed tracing for debugging
- **CloudWatch Alarms** - Alert on error rates and latency thresholds

### Deployment

- **Stage Variables** - Use for environment-specific configuration
- **Canary Deployments** - Gradual rollout of changes
- **Deployment Triggers** - Automate redeployment on changes
- **Multiple Stages** - Separate dev, staging, and production

## REST API vs HTTP API

| Feature                | REST API      | HTTP API      |
| ---------------------- | ------------- | ------------- |
| **Cost**               | $3.50/million | $1.00/million |
| **Latency**            | Higher        | Lower         |
| **Caching**            | ✅ Yes        | ❌ No         |
| **Usage Plans**        | ✅ Yes        | ❌ No         |
| **Request Validation** | ✅ Yes        | ❌ No         |
| **API Keys**           | ✅ Yes        | ❌ No         |
| **JWT Authorizers**    | ❌ No         | ✅ Yes        |
| **CORS**               | Manual        | Built-in      |
| **WebSocket**          | ❌ No         | ✅ Yes        |

**Recommendation**: Use HTTP API for new projects unless you need REST API-specific features.

## IAM Permissions

### Required Permissions for Terraform

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["apigateway:*"],
      "Resource": "*"
    }
  ]
}
```

### Lambda Invoke Permission

```hcl
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.rest_api_execution_arn}/*/*"
}
```

## Troubleshooting

### Common Issues

**403 Forbidden Error**

- Check authorizer configuration
- Verify IAM permissions
- Review resource policy

**502 Bad Gateway**

- Check Lambda function errors
- Verify integration configuration
- Review timeout settings

**Custom Domain Not Working**

- Verify certificate in correct region (us-east-1 for CloudFront)
- Check DNS configuration
- Ensure base path mapping is correct

**CORS Errors**

- Enable CORS in API Gateway
- Add proper headers in Lambda response
- Check allowed origins configuration

**Rate Limiting**

- Review usage plan quotas
- Check throttle settings
- Monitor CloudWatch metrics

## Examples

See the [examples](../../examples/api-gateway/) directory for complete working examples.

## Contributing

Contributions are welcome! Please ensure:

- Code follows Terraform best practices
- All variables have descriptions and validations
- Examples are tested and working
- Documentation is updated

## License

This module is provided as-is for infrastructure management.
