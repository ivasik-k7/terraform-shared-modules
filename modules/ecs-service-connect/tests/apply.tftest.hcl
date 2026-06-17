# Mocked-provider apply test for the ecs-service-connect module.
# Run with: terraform test

mock_provider "aws" {}

run "apply_http_namespace_with_logs" {
  command = apply

  variables {
    name             = "mesh"
    namespace_type   = "http"
    create_log_group = true
    services = {
      api = { services = [{ port_name = "api-http", client_aliases = [{ port = 8080 }] }] }
    }
  }

  assert {
    condition     = length(aws_service_discovery_http_namespace.this) == 1
    error_message = "An HTTP namespace should be created"
  }

  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.this) == 0
    error_message = "No private DNS namespace should be created for http type"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.service_connect) == 1
    error_message = "A Service Connect log group should be created"
  }

  assert {
    condition     = output.service_connect_configurations["api"].log_configuration.options["awslogs-stream-prefix"] == "service-connect"
    error_message = "Default awslogs configuration should be injected"
  }
}

run "apply_dns_private_namespace" {
  command = apply

  variables {
    name           = "mesh"
    namespace_type = "dns_private"
    vpc_id         = "vpc-12345678"
    services       = {}
  }

  assert {
    condition     = length(aws_service_discovery_private_dns_namespace.this) == 1
    error_message = "A private DNS namespace should be created"
  }

  assert {
    condition     = length(aws_service_discovery_http_namespace.this) == 0
    error_message = "No HTTP namespace should be created for dns_private type"
  }
}

run "apply_mesh_wide_tls" {
  command = apply

  variables {
    name         = "mesh"
    enable_tls   = true
    tls_ca_arn   = "arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/abc"
    tls_role_arn = "arn:aws:iam::123456789012:role/sc-tls"
    services = {
      api = {
        services = [{
          port_name      = "http"
          client_aliases = [{ port = 8080 }]
        }]
      }
    }
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].tls.role_arn == "arn:aws:iam::123456789012:role/sc-tls"
    error_message = "Mesh-wide TLS role should be injected from tls_role_arn"
  }
}