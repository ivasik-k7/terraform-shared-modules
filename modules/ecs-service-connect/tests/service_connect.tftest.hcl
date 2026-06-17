# Native `terraform test` suite for the ecs-service-connect module.
# Run with: terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Configuration generation (plan-only, input-derived values) ---------------
run "generates_service_connect_config" {
  command = plan

  variables {
    name           = "mesh"
    namespace_name = "prod.internal"
    namespace_type = "http"
    services = {
      api = {
        services = [{
          port_name      = "api-http"
          discovery_name = "api"
          client_aliases = [{ port = 8080, dns_name = "api" }]
        }]
      }
      web = { services = [] }
    }
  }

  assert {
    condition     = length(output.service_connect_configurations["api"].service) == 1
    error_message = "api should expose exactly one service"
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].discovery_name == "api"
    error_message = "discovery_name should be set"
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].client_alias[0].port == 8080
    error_message = "client_alias port should be 8080"
  }

  assert {
    condition     = output.service_endpoints["api"][0] == "api:8080"
    error_message = "service endpoint should be api:8080"
  }

  assert {
    condition     = length(output.service_connect_configurations["web"].service) == 0
    error_message = "web is client-only and should expose nothing"
  }
}

# --- discovery_name defaults to port_name when omitted ------------------------
run "discovery_name_defaults_to_port_name" {
  command = plan

  variables {
    name = "mesh"
    services = {
      api = {
        services = [{ port_name = "grpc" }]
      }
    }
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].discovery_name == "grpc"
    error_message = "discovery_name should default to port_name"
  }
}

# --- Validation: invalid namespace_type ---------------------------------------
run "invalid_namespace_type_fails" {
  command = plan

  variables {
    name           = "mesh"
    namespace_type = "dns_public"
  }

  expect_failures = [var.namespace_type]
}

# --- Precondition: create_namespace=false without an existing ARN -------------
run "missing_existing_namespace_fails" {
  command = plan

  variables {
    name                   = "mesh"
    create_namespace       = false
    existing_namespace_arn = null
  }

  expect_failures = [terraform_data.validations]
}

# --- Precondition: enable_tls without a CA ARN --------------------------------
run "enable_tls_requires_ca_fails" {
  command = plan

  variables {
    name       = "mesh"
    enable_tls = true
    tls_ca_arn = null
  }

  expect_failures = [terraform_data.validations]
}

# --- Precondition: TLS enabled without a role ---------------------------------
run "tls_without_role_fails" {
  command = plan

  variables {
    name         = "mesh"
    enable_tls   = true
    tls_ca_arn   = "arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/abc"
    tls_role_arn = null
  }

  expect_failures = [terraform_data.validations]
}

# --- Self-consistency: duplicate client endpoints are rejected ----------------
run "duplicate_endpoint_fails" {
  command = plan

  variables {
    name = "mesh"
    services = {
      api = { services = [{ port_name = "http", client_aliases = [{ port = 8080, dns_name = "shared" }] }] }
      web = { services = [{ port_name = "web", client_aliases = [{ port = 8080, dns_name = "shared" }] }] }
    }
  }

  expect_failures = [var.services]
}

# --- Self-consistency: duplicate discovery names are rejected -----------------
run "duplicate_discovery_name_fails" {
  command = plan

  variables {
    name = "mesh"
    services = {
      a = { services = [{ port_name = "p1", discovery_name = "dup" }] }
      b = { services = [{ port_name = "p2", discovery_name = "dup" }] }
    }
  }

  expect_failures = [var.services]
}

# --- Heterogeneous services unify into one output map type --------------------
# Mixes per-service tls + per-service log_config (with secret_option), a plain
# service, and a client-only service to stress object/tuple type unification.
run "heterogeneous_services_unify" {
  command = plan

  variables {
    name             = "mesh"
    create_log_group = true
    tls_role_arn     = "arn:aws:iam::123456789012:role/sc-tls"
    services = {
      api = {
        services = [{
          port_name      = "http"
          client_aliases = [{ port = 8080, dns_name = "api" }]
          tls = {
            aws_pca_authority_arn = "arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/abc"
            role_arn              = "arn:aws:iam::123456789012:role/per-svc"
          }
        }]
        log_configuration = {
          log_driver    = "awslogs"
          options       = { "awslogs-group" = "/custom" }
          secret_option = [{ name = "X", value_from = "arn:aws:ssm:us-east-1:123456789012:parameter/x" }]
        }
      }
      plain  = { services = [{ port_name = "grpc", client_aliases = [{ port = 9000 }] }] }
      worker = { services = [] }
    }
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].tls.role_arn == "arn:aws:iam::123456789012:role/per-svc"
    error_message = "per-service tls role should win"
  }
  assert {
    condition     = output.service_connect_configurations["plain"].service[0].tls == null
    error_message = "plain service should have null tls"
  }
  assert {
    condition     = output.service_connect_configurations["plain"].log_configuration.options["awslogs-stream-prefix"] == "service-connect"
    error_message = "plain service should inherit the default log config"
  }
  assert {
    condition     = length(output.service_endpoints["worker"]) == 0
    error_message = "client-only service exposes no endpoints"
  }
}

# --- Mesh-wide TLS + default timeout are injected into generated config -------
run "mesh_wide_tls_and_timeout_injected" {
  command = plan

  variables {
    name         = "mesh"
    enable_tls   = true
    tls_ca_arn   = "arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/abc"
    tls_role_arn = "arn:aws:iam::123456789012:role/sc-tls"
    default_timeout = {
      per_request_timeout_seconds = 30
    }
    services = {
      api = { services = [{ port_name = "http", client_aliases = [{ port = 8080 }] }] }
    }
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].tls.aws_pca_authority_arn == "arn:aws:acm-pca:us-east-1:123456789012:certificate-authority/abc"
    error_message = "Mesh-wide TLS CA should be injected"
  }

  assert {
    condition     = output.service_connect_configurations["api"].service[0].timeout.per_request_timeout_seconds == 30
    error_message = "Default timeout should be injected"
  }
}

