# Native `terraform test` suite for the lb module (plan-only).
# Credential-free provider so no real AWS resources are required.
# Run with: terraform test

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock"
  secret_key                  = "mock"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# --- Application LB: SG + target group + forward listener --------------------
run "application_basic" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    security_group_ingress_rules = {
      http = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
    }
    target_groups = {
      app = { port = 8080, protocol = "HTTP", target_type = "ip" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
  }

  assert {
    condition     = aws_lb.this[0].load_balancer_type == "application"
    error_message = "Should be an application load balancer"
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "Security group should be created"
  }

  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.this) == 1
    error_message = "One ingress rule should be planned"
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 1 && length(aws_lb_listener.this) == 1
    error_message = "One target group and one listener should be planned"
  }
}

# --- Network LB: no SG, TCP listener -----------------------------------------
run "network_basic" {
  command = plan

  variables {
    name                  = "test-nlb"
    load_balancer_type    = "network"
    create_security_group = false
    subnets               = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      tcp = { port = 443, protocol = "TCP", target_type = "instance", vpc_id = "vpc-12345678" }
    }
    listeners = {
      tcp = {
        port           = 443
        default_action = { type = "forward", target_group_key = "tcp" }
      }
    }
  }

  assert {
    condition     = aws_lb.this[0].load_balancer_type == "network"
    error_message = "Should be a network load balancer"
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No security group should be created"
  }

  assert {
    condition     = aws_lb_listener.this["tcp"].protocol == "TCP"
    error_message = "Listener protocol should be TCP"
  }
}

# --- HTTPS listener + HTTP->HTTPS redirect -----------------------------------
run "https_with_redirect" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
    }
    listeners = {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        default_action  = { type = "forward", target_group_key = "app" }
      }
      http = {
        port = 80
        default_action = {
          type     = "redirect"
          redirect = { status_code = "HTTP_301", port = "443", protocol = "HTTPS" }
        }
      }
    }
  }

  assert {
    condition     = aws_lb_listener.this["https"].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06"
    error_message = "HTTPS listener should get the default SSL policy"
  }

  assert {
    condition     = aws_lb_listener.this["http"].default_action[0].type == "redirect"
    error_message = "HTTP listener should redirect"
  }
}

# --- Weighted forward (blue/green) -------------------------------------------
run "weighted_forward" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      blue  = { port = 8080, target_type = "ip" }
      green = { port = 8080, target_type = "ip" }
    }
    listeners = {
      http = {
        port = 80
        default_action = {
          type = "forward"
          target_groups = [
            { target_group_key = "blue", weight = 90 },
            { target_group_key = "green", weight = 10 },
          ]
          stickiness = { duration = 3600 }
        }
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "Two target groups should be planned"
  }
}

# --- Listener rules with conditions ------------------------------------------
run "listener_rules" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
      api = { port = 9090, target_type = "ip" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
    listener_rules = {
      api = {
        listener_key = "http"
        priority     = 100
        actions      = [{ type = "forward", target_group_key = "api" }]
        conditions = [
          { path_patterns = ["/api/*"] },
          { host_headers = ["api.example.com"] },
        ]
      }
      block = {
        listener_key = "http"
        priority     = 50
        actions      = [{ type = "fixed-response", fixed_response = { content_type = "text/plain", status_code = "403", message_body = "denied" } }]
        conditions   = [{ source_ips = ["10.0.0.0/8"] }]
      }
    }
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 2
    error_message = "Two listener rules should be planned"
  }
}

# --- Static target attachments (no ECS/k8s controller) -----------------------
run "static_target_attachments" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      app = {
        port        = 80
        target_type = "instance"
        targets = {
          a = { target_id = "i-aaaa1111" }
          b = { target_id = "i-bbbb2222" }
        }
      }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.this) == 2
    error_message = "Two target attachments should be planned"
  }
}

# --- Lambda target group has no port -----------------------------------------
run "lambda_target_group" {
  command = plan

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
    target_groups = {
      fn = { target_type = "lambda" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "fn" }
      }
    }
  }

  assert {
    condition     = aws_lb_target_group.this["fn"].port == null
    error_message = "Lambda target group should have no port"
  }
}

# ============================================================================
# VALIDATION FAILURES
# ============================================================================

run "invalid_name_fails" {
  command = plan
  variables {
    name    = "invalid name with spaces"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
  }
  expect_failures = [var.name]
}

run "invalid_lb_type_fails" {
  command = plan
  variables {
    name               = "test"
    load_balancer_type = "classic"
    vpc_id             = "vpc-12345678"
    subnets            = ["subnet-aaaa1111"]
  }
  expect_failures = [var.load_balancer_type]
}

run "invalid_ip_address_type_fails" {
  command = plan
  variables {
    name            = "test"
    vpc_id          = "vpc-12345678"
    subnets         = ["subnet-aaaa1111"]
    ip_address_type = "ipv6"
  }
  expect_failures = [var.ip_address_type]
}

run "sg_without_vpc_fails" {
  command = plan
  variables {
    name                  = "test"
    create_security_group = true
    subnets               = ["subnet-aaaa1111"]
  }
  expect_failures = [var.vpc_id]
}

run "non_lambda_without_port_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { target_type = "ip" }
    }
  }
  expect_failures = [var.target_groups]
}

run "forward_without_target_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward" }
      }
    }
  }
  expect_failures = [var.listeners]
}

run "listener_references_unknown_tg_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "does-not-exist" }
      }
    }
  }
  expect_failures = [var.listeners]
}

run "rule_references_unknown_listener_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
    listener_rules = {
      r = {
        listener_key = "nope"
        priority     = 10
        actions      = [{ type = "forward", target_group_key = "app" }]
        conditions   = [{ path_patterns = ["/x"] }]
      }
    }
  }
  expect_failures = [var.listener_rules]
}

run "rule_priority_out_of_range_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
    listener_rules = {
      r = {
        listener_key = "http"
        priority     = 99999
        actions      = [{ type = "forward", target_group_key = "app" }]
        conditions   = [{ path_patterns = ["/x"] }]
      }
    }
  }
  expect_failures = [var.listener_rules]
}

run "no_subnets_fails" {
  command = plan
  variables {
    name   = "test"
    vpc_id = "vpc-12345678"
  }
  expect_failures = [aws_lb.this]
}

run "application_without_sg_fails" {
  command = plan
  variables {
    name                  = "test"
    vpc_id                = "vpc-12345678"
    subnets               = ["subnet-aaaa1111"]
    create_security_group = false
  }
  expect_failures = [aws_lb.this]
}

# ============================================================================
# PHASE 2-4 FEATURE COVERAGE
# ============================================================================

# --- Target groups default to a CBD-safe name_prefix -------------------------
run "name_prefix_default" {
  command = plan
  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
  }
  assert {
    condition     = aws_lb_target_group.this["app"].name_prefix == "app"
    error_message = "Target group should derive a name_prefix from its key"
  }
}

# --- Lambda target gets an invoke permission ---------------------------------
run "lambda_permission_created" {
  command = plan
  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      fn = {
        target_type = "lambda"
        targets = {
          main = { target_id = "arn:aws:lambda:us-east-1:123456789012:function:my-fn" }
        }
      }
    }
    listeners = {
      http = {
        port           = 80
        default_action = { type = "forward", target_group_key = "fn" }
      }
    }
  }
  assert {
    condition     = length(aws_lambda_permission.this) == 1
    error_message = "A lambda invoke permission should be created for lambda targets"
  }
}

# --- Cognito auth adds a preceding default action ----------------------------
run "cognito_auth" {
  command = plan
  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
    }
    listeners = {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        default_action = {
          type             = "forward"
          target_group_key = "app"
          authenticate_cognito = {
            user_pool_arn       = "arn:aws:cognito-idp:us-east-1:123456789012:userpool/us-east-1_abc"
            user_pool_client_id = "client123"
            user_pool_domain    = "auth.example.com"
          }
        }
      }
    }
  }
  assert {
    condition     = length(aws_lb_listener.this["https"].default_action) == 2
    error_message = "Auth + forward should produce two default actions"
  }
}

# --- Mutual TLS on a listener ------------------------------------------------
run "mutual_tls" {
  command = plan
  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
    }
    listeners = {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        mutual_authentication = {
          mode            = "verify"
          trust_store_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:truststore/ts/abc"
        }
        default_action = { type = "forward", target_group_key = "app" }
      }
    }
  }
  assert {
    condition     = aws_lb_listener.this["https"].mutual_authentication[0].mode == "verify"
    error_message = "Mutual authentication mode should be forwarded"
  }
}

# --- WAF association, Route53 records, and alarms ----------------------------
run "waf_route53_alarms" {
  command = plan
  variables {
    name        = "test-alb"
    vpc_id      = "vpc-12345678"
    subnets     = ["subnet-aaaa1111"]
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/abc"
    route53_records = {
      apex = { zone_id = "Z123", name = "app.example.com" }
    }
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    create_cloudwatch_alarms = true
  }
  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association should be planned"
  }
  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "Route53 record should be planned"
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 1 && length(aws_cloudwatch_metric_alarm.elb_5xx) == 1 && length(aws_cloudwatch_metric_alarm.target_response_time) == 1
    error_message = "Expected unhealthy-host + 5xx + response-time alarms"
  }
}

# --- create = false builds nothing -------------------------------------------
run "create_false" {
  command = plan
  variables {
    create  = false
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    listeners = {
      http = { port = 80, default_action = { type = "forward", target_group_key = "app" } }
    }
  }
  assert {
    condition     = length(aws_lb.this) == 0 && length(aws_lb_target_group.this) == 0 && length(aws_lb_listener.this) == 0
    error_message = "create=false should build nothing"
  }
}

# --- Gateway type is no longer supported -------------------------------------
run "gateway_type_fails" {
  command = plan
  variables {
    name               = "test"
    load_balancer_type = "gateway"
    vpc_id             = "vpc-12345678"
    subnets            = ["subnet-aaaa1111"]
  }
  expect_failures = [var.load_balancer_type]
}

# --- ALB cannot use a TCP listener -------------------------------------------
run "alb_tcp_listener_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, target_type = "ip" }
    }
    listeners = {
      bad = { port = 80, protocol = "TCP", default_action = { type = "forward", target_group_key = "app" } }
    }
  }
  expect_failures = [var.listeners]
}

# --- NLB cannot use an HTTP target group -------------------------------------
run "nlb_http_target_group_fails" {
  command = plan
  variables {
    name                  = "test"
    load_balancer_type    = "network"
    create_security_group = false
    subnets               = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 80, protocol = "HTTP", target_type = "instance", vpc_id = "vpc-12345678" }
    }
  }
  expect_failures = [var.target_groups]
}

# --- Listener rule with auth + forward gets ordered actions ------------------
run "rule_auth_then_forward" {
  command = plan
  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
    }
    listeners = {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        default_action  = { type = "forward", target_group_key = "app" }
      }
    }
    listener_rules = {
      secure = {
        listener_key = "https"
        priority     = 100
        actions = [
          {
            type = "authenticate-oidc"
            authenticate_oidc = {
              authorization_endpoint = "https://idp.example.com/authorize"
              client_id              = "c"
              client_secret          = "s"
              issuer                 = "https://idp.example.com"
              token_endpoint         = "https://idp.example.com/token"
              user_info_endpoint     = "https://idp.example.com/userinfo"
            }
          },
          { type = "forward", target_group_key = "app" },
        ]
        conditions = [{ path_patterns = ["/secure/*"] }]
      }
    }
  }
  assert {
    condition     = aws_lb_listener_rule.this["secure"].action[0].order == 1 && aws_lb_listener_rule.this["secure"].action[1].order == 2
    error_message = "Rule actions should be ordered 1,2 so auth precedes forward"
  }
}

# --- NLB alarms use the NetworkELB namespace ---------------------------------
run "nlb_alarm_namespace" {
  command = plan
  variables {
    name                     = "test-nlb"
    load_balancer_type       = "network"
    create_security_group    = false
    subnets                  = ["subnet-aaaa1111"]
    create_cloudwatch_alarms = true
    target_groups = {
      tcp = { port = 443, protocol = "TCP", target_type = "instance", vpc_id = "vpc-12345678" }
    }
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.unhealthy_hosts["tcp"].namespace == "AWS/NetworkELB"
    error_message = "NLB unhealthy-host alarm must use the AWS/NetworkELB namespace"
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.elb_5xx) == 0
    error_message = "5XX alarm should not exist for an NLB"
  }
}

# --- HTTPS listener without a certificate is rejected ------------------------
run "https_without_cert_fails" {
  command = plan
  variables {
    name    = "test"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111"]
    target_groups = {
      app = { port = 8080, target_type = "ip" }
    }
    listeners = {
      https = { port = 443, protocol = "HTTPS", default_action = { type = "forward", target_group_key = "app" } }
    }
  }
  expect_failures = [var.listeners]
}
