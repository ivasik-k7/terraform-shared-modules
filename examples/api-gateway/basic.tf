terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

locals {
  name_prefix = "archon-hub-dev"

  base_tags = {
    Project     = "archon-hub"
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}

resource "aws_cognito_user_pool" "pool" {
  name = "${local.name_prefix}-user-pool"

  password_policy {
    minimum_length = 8
  }

  tags = local.base_tags
}

resource "aws_cognito_user_pool_client" "client" {
  name         = "${local.name_prefix}-client"
  user_pool_id = aws_cognito_user_pool.pool.id

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH"
  ]
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda"
  output_path = "${path.module}/bin/lambda_function.zip"
}

resource "aws_iam_role" "lambda_exec" {
  name = "${local.name_prefix}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = local.base_tags
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "users" {
  filename      = data.archive_file.lambda_zip.output_path
  function_name = "${local.name_prefix}-get-users"
  role          = aws_iam_role.lambda_exec.arn
  handler       = "index.handler"
  runtime       = "nodejs18.x"

  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  tags = local.base_tags
}

resource "aws_lambda_permission" "apigw_lambda" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${module.rest_api.rest_api_execution_arn}/*/*"
}

resource "aws_lambda_permission" "http_api_lambda" {
  statement_id  = "AllowHTTPAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.users.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.http_api.http_api_execution_arn}/*/*"
}


module "rest_api" {
  source = "../../modules/api-gateway"

  create_rest_api      = true
  rest_api_name        = "simple-api"
  rest_api_description = "Simple REST API with Lambda"

  rest_api_authorizers = {
    cognito_auth = {
      name            = "cognito-authorizer"
      type            = "COGNITO_USER_POOLS"
      provider_arns   = [aws_cognito_user_pool.pool.arn]
      identity_source = "method.request.header.Authorization"
    }
  }

  rest_api_resources = {
    users = {
      path_part = "users"
    }
  }

  rest_api_methods = {
    get_users = {
      resource_key  = "users"
      http_method   = "GET"
      authorization = "COGNITO_USER_POOLS"
      authorizer_id = null
    }
  }

  rest_api_integrations = {
    get_users = {
      method_key              = "get_users"
      type                    = "AWS_PROXY"
      integration_http_method = "POST"
      uri                     = aws_lambda_function.users.invoke_arn
    }
  }
  create_rest_api_deployment = true
  rest_api_stages = {
    prod = {
      stage_name = "prod"
    }
  }

  tags = {
    Environment = "production"
  }
}


module "http_api" {
  source = "../../modules/api-gateway"

  create_http_api      = true
  http_api_name        = "${local.name_prefix}-secure-api"
  http_api_description = "Serverless API with JWT and CORS"

  http_api_cors_configuration = {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Content-Type", "Authorization"]
    max_age       = 300
  }

  http_api_authorizers = {
    cognito_jwt = {
      name             = "cognito-jwt-auth"
      authorizer_type  = "JWT"
      identity_sources = ["$request.header.Authorization"]
      jwt_configuration = {
        audience = [aws_cognito_user_pool_client.client.id]
        issuer   = "https://${aws_cognito_user_pool.pool.endpoint}"
      }
    }
  }
  http_api_integrations = {
    lambda_backend = {
      integration_type       = "AWS_PROXY"
      integration_uri        = aws_lambda_function.users.invoke_arn
      payload_format_version = "2.0"
    }
  }

  http_api_routes = {
    "GET /profile" = {
      route_key          = "GET /profile"
      integration_key    = "lambda_backend"
      authorizer_key     = "cognito_jwt"
      authorization_type = "JWT"
    }

    "GET /health" = {
      route_key          = "GET /health"
      integration_key    = "lambda_backend"
      authorization_type = "NONE"
    }

    "$default" = {
      route_key       = "$default"
      integration_key = "lambda_backend"
    }
  }

  http_api_stages = {
    prod = {
      name        = "$default"
      auto_deploy = true

      default_route_settings = {
        detailed_metrics_enabled = true
        throttling_burst_limit   = 100
        throttling_rate_limit    = 50
      }
    }
  }

  tags = local.base_tags
}
