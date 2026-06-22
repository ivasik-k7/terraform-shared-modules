# Full-stack apply test using a mocked AWS provider, so the whole graph (LB, SG
# + rules, target groups, attachments, listeners, SNI certs, listener rules) is
# created offline with no real AWS account. Run with: terraform test

mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/mock/abc123"
      arn_suffix = "app/mock/abc123"
      dns_name   = "mock-123.us-east-1.elb.amazonaws.com"
      zone_id    = "Z35SXDOTRQ7X7K"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/mock/abc123"
      arn_suffix = "targetgroup/mock/abc123"
    }
  }

  mock_resource "aws_lb_listener" {
    defaults = {
      arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:listener/app/mock/abc123/def456"
    }
  }
}

# --- Comprehensive ALB -------------------------------------------------------
run "full_stack_apply" {
  command = apply

  variables {
    name    = "test-alb"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]

    security_group_ingress_rules = {
      http  = { from_port = 80, to_port = 80, cidr_ipv4 = "0.0.0.0/0" }
      https = { from_port = 443, to_port = 443, cidr_ipv4 = "0.0.0.0/0" }
    }

    target_groups = {
      blue = {
        port        = 8080
        target_type = "ip"
        health_check = {
          path     = "/healthz"
          matcher  = "200"
          interval = 15
        }
        stickiness = { type = "lb_cookie", cookie_duration = 3600 }
      }
      green = {
        port        = 8080
        target_type = "ip"
      }
    }

    listeners = {
      https = {
        port                        = 443
        protocol                    = "HTTPS"
        certificate_arn             = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        additional_certificate_arns = ["arn:aws:acm:us-east-1:123456789012:certificate/efgh"]
        default_action = {
          type = "forward"
          target_groups = [
            { target_group_key = "blue", weight = 100 },
            { target_group_key = "green", weight = 0 },
          ]
        }
      }
      http = {
        port = 80
        default_action = {
          type     = "redirect"
          redirect = { status_code = "HTTP_301", port = "443", protocol = "HTTPS" }
        }
      }
    }

    listener_rules = {
      api = {
        listener_key = "https"
        priority     = 100
        actions      = [{ type = "forward", target_group_key = "green" }]
        conditions = [
          { path_patterns = ["/api/*"] },
          { http_header = { name = "X-Env", values = ["canary"] } },
        ]
      }
    }

    tags = { Environment = "test" }
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 2
    error_message = "Expected two target groups"
  }

  assert {
    condition     = length(aws_lb_listener.this) == 2
    error_message = "Expected two listeners"
  }

  assert {
    condition     = length(aws_lb_listener_certificate.this) == 1
    error_message = "Expected one additional (SNI) certificate"
  }

  assert {
    condition     = length(aws_lb_listener_rule.this) == 1
    error_message = "Expected one listener rule"
  }

  assert {
    condition     = length(aws_security_group.this) == 1 && length(aws_vpc_security_group_ingress_rule.this) == 2 && length(aws_vpc_security_group_egress_rule.this) == 1
    error_message = "Expected the SG with two ingress rules and the default egress rule"
  }
}

# --- Network LB with static instance attachments -----------------------------
run "network_with_attachments_apply" {
  command = apply

  variables {
    name                  = "test-nlb"
    load_balancer_type    = "network"
    create_security_group = false
    subnets               = ["subnet-aaaa1111", "subnet-bbbb2222"]

    target_groups = {
      tcp = {
        port        = 443
        protocol    = "TCP"
        target_type = "instance"
        vpc_id      = "vpc-12345678"
        targets = {
          a = { target_id = "i-aaaa1111" }
          b = { target_id = "i-bbbb2222" }
        }
      }
    }

    listeners = {
      tcp = {
        port           = 443
        default_action = { type = "forward", target_group_key = "tcp" }
      }
    }
  }

  assert {
    condition     = length(aws_lb_target_group_attachment.this) == 2
    error_message = "Expected two target attachments"
  }

  assert {
    condition     = length(aws_security_group.this) == 0
    error_message = "No security group for this NLB"
  }
}

# --- Minimal apply: only LB + SG, no listeners/target groups -----------------
run "minimal_apply" {
  command = apply

  variables {
    name    = "test-min"
    vpc_id  = "vpc-12345678"
    subnets = ["subnet-aaaa1111", "subnet-bbbb2222"]
  }

  assert {
    condition     = length(aws_lb_target_group.this) == 0 && length(aws_lb_listener.this) == 0
    error_message = "No target groups or listeners by default"
  }

  assert {
    condition     = length(aws_security_group.this) == 1
    error_message = "Security group created by default"
  }
}

# --- Lambda target, edge auth, WAF, Route53, and alarms all apply ------------
run "advanced_features_apply" {
  command = apply

  variables {
    name        = "test-adv"
    vpc_id      = "vpc-12345678"
    subnets     = ["subnet-aaaa1111", "subnet-bbbb2222"]
    web_acl_arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/test/abc"

    route53_records = {
      apex = { zone_id = "Z123456", name = "app.example.com" }
    }

    target_groups = {
      app = { port = 8080, target_type = "ip" }
      fn = {
        target_type = "lambda"
        targets = {
          main = { target_id = "arn:aws:lambda:us-east-1:123456789012:function:my-fn" }
        }
      }
    }

    listeners = {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abcd"
        default_action = {
          type             = "forward"
          target_group_key = "app"
          authenticate_oidc = {
            authorization_endpoint = "https://idp.example.com/authorize"
            client_id              = "client123"
            client_secret          = "secret"
            issuer                 = "https://idp.example.com"
            token_endpoint         = "https://idp.example.com/token"
            user_info_endpoint     = "https://idp.example.com/userinfo"
          }
        }
      }
    }

    create_cloudwatch_alarms = true
  }

  assert {
    condition     = length(aws_lambda_permission.this) == 1
    error_message = "Lambda invoke permission should be created"
  }

  assert {
    condition     = length(aws_wafv2_web_acl_association.this) == 1
    error_message = "WAF association should be created"
  }

  assert {
    condition     = length(aws_route53_record.this) == 1
    error_message = "Route53 record should be created"
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.unhealthy_hosts) == 2
    error_message = "One unhealthy-host alarm per target group"
  }

  assert {
    condition     = length(aws_lb_listener.this["https"].default_action) == 2
    error_message = "OIDC auth + forward should produce two default actions"
  }
}
