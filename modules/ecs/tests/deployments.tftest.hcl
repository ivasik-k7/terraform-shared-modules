# Native deployment strategies, lifecycle hooks, sigint_rollback and the
# Service Connect pieces that go with them. Runs that compare a role ARN apply
# against the mock, because the role's ARN is only known after apply.
#
# What a mock cannot show: ECS accepting the strategy with these target groups
# and listener rules, or a hook being invoked.

mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_region" {
    defaults = { region = "eu-west-2" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "111122223333" }
  }
  # Applied runs need ARNs the provider's own validation accepts.
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = { arn = "arn:aws:ecs:eu-west-2:111122223333:cluster/orders" }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:eu-west-2:111122223333:task-definition/orders-api:1" }
  }
  mock_resource "aws_cloudwatch_log_group" {
    defaults = { arn = "arn:aws:logs:eu-west-2:111122223333:log-group:/ecs/orders/api" }
  }
}

variables {
  name               = "orders"
  subnet_ids         = ["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]
  security_group_ids = ["sg-0a1b2c3d4e5f60001"]
  sns_topic_arn      = "arn:aws:sns:eu-west-2:111122223333:alerts"
  log_kms_key_arn    = "arn:aws:kms:eu-west-2:111122223333:key/11111111-2222-3333-4444-555555555555"
  tags               = { CostCenter = "cc-1", Environment = "test" }

  services = {
    api = {
      image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
      port          = 8080
      desired_count = 2
    }
  }
}

run "every_service_states_rolling_unless_told_otherwise" {
  command = plan

  assert {
    condition     = aws_ecs_service.this["api"].deployment_configuration[0].strategy == "ROLLING"
    error_message = "a service sends strategy = ROLLING, so leaving BLUE_GREEN is an update and not a strategy the API keeps."
  }

  assert {
    condition     = length(aws_iam_role.infrastructure) == 0 && output.infrastructure_role_arn == null
    error_message = "a rolling service without load balancers, hooks or volumes needs no infrastructure role."
  }

  assert {
    condition     = output.governance.deployment_strategies == { api = "ROLLING" } && length(output.governance.traffic_shifted) == 0
    error_message = "governance reports each service's strategy."
  }

  assert {
    condition     = !contains(keys(output.verify_commands.stop_deployment), "api")
    error_message = "the rollback command is offered only where ECS runs a traffic-shifting deployment."
  }
}

run "blue_green_moves_traffic_between_two_target_groups_with_the_infrastructure_role" {
  command = apply

  variables {
    services = {
      api = {
        image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
        port          = 8080
        desired_count = 2
        deployment    = { strategy = "BLUE_GREEN", bake_time_minutes = 15 }
        load_balancers = [{
          target_group_arn             = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-blue/0123456789abcdef"
          alternate_target_group_arn   = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-green/0123456789abcdef"
          production_listener_rule_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/web/0123456789abcdef/0123456789abcdef/0123456789abcdef"
          test_listener_rule_arn       = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/web/0123456789abcdef/0123456789abcdef/fedcba9876543210"
        }]
      }
    }
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this["api"].deployment_configuration[0].strategy == "BLUE_GREEN",
      aws_ecs_service.this["api"].deployment_configuration[0].bake_time_in_minutes == "15",
    ])
    error_message = "BLUE_GREEN is sent with its bake time."
  }

  assert {
    condition = one(aws_ecs_service.this["api"].load_balancer).advanced_configuration[0] == {
      alternate_target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-green/0123456789abcdef"
      production_listener_rule   = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/web/0123456789abcdef/0123456789abcdef/0123456789abcdef"
      test_listener_rule         = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/web/0123456789abcdef/0123456789abcdef/fedcba9876543210"
      role_arn                   = aws_iam_role.infrastructure[0].arn
    }
    error_message = "the load balancer carries the alternate target group, both listener rules and the module's infrastructure role."
  }

  assert {
    condition     = keys(aws_iam_role_policy_attachment.infrastructure) == ["load_balancers"] && aws_iam_role_policy_attachment.infrastructure["load_balancers"].policy_arn == "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForLoadBalancers"
    error_message = "the infrastructure role gets the load balancer policy (no service-role/ path) and nothing it does not use."
  }

  assert {
    condition     = jsondecode(output.deployer_requirements.iam_policy).Statement[1].Sid == "PassInfrastructureRole"
    error_message = "the deployer is told to pass the infrastructure role to ECS."
  }

  assert {
    condition     = jsonencode(output.governance.traffic_shifted) == jsonencode(["api"]) && contains(keys(output.verify_commands.stop_deployment), "api")
    error_message = "governance and verify_commands follow the traffic-shifting service."
  }
}

run "canary_and_linear_send_only_their_own_configuration" {
  command = plan

  variables {
    services = {
      api = {
        image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
        port          = 8080
        desired_count = 2
        deployment    = { strategy = "CANARY", canary_percent = 10, canary_bake_minutes = 20 }
      }
      web = {
        image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/web:1.0.0"
        port          = 8080
        desired_count = 2
        deployment    = { strategy = "LINEAR", linear_step_percent = 25, linear_step_bake_minutes = 3, bake_time_minutes = 0 }
      }
    }
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this["api"].deployment_configuration[0].canary_configuration[0].canary_percent == 10,
      aws_ecs_service.this["api"].deployment_configuration[0].canary_configuration[0].canary_bake_time_in_minutes == "20",
      length(aws_ecs_service.this["api"].deployment_configuration[0].linear_configuration) == 0,
      aws_ecs_service.this["api"].deployment_configuration[0].bake_time_in_minutes == "10",
    ])
    error_message = "CANARY sends its share and bake, the default 10-minute deployment bake time, and no linear block."
  }

  assert {
    condition = alltrue([
      aws_ecs_service.this["web"].deployment_configuration[0].linear_configuration[0].step_percent == 25,
      aws_ecs_service.this["web"].deployment_configuration[0].linear_configuration[0].step_bake_time_in_minutes == "3",
      length(aws_ecs_service.this["web"].deployment_configuration[0].canary_configuration) == 0,
      aws_ecs_service.this["web"].deployment_configuration[0].bake_time_in_minutes == "0",
    ])
    error_message = "LINEAR sends its step and step bake, a bake time of 0 as 0, and no canary block."
  }

  assert {
    condition     = length(aws_iam_role.infrastructure) == 0
    error_message = "a headless canary or linear service has no load balancer for ECS to act on, so no infrastructure role."
  }
}

run "lifecycle_hooks_invoke_their_functions_through_the_infrastructure_role" {
  command = apply

  variables {
    services = {
      api = {
        image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
        port          = 8080
        desired_count = 2
        deployment = {
          strategy = "BLUE_GREEN"
          lifecycle_hooks = {
            smoke = {
              function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:smoke-test"
              stages       = ["POST_TEST_TRAFFIC_SHIFT", "POST_PRODUCTION_TRAFFIC_SHIFT"]
              details      = jsonencode({ path = "/health" })
            }
            approve = {
              function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:approve:live"
              stages       = ["PRE_SCALE_UP"]
            }
          }
        }
      }
    }
  }

  assert {
    condition = toset([for h in aws_ecs_service.this["api"].deployment_configuration[0].lifecycle_hook : h.hook_target_arn]) == toset([
      "arn:aws:lambda:eu-west-2:111122223333:function:smoke-test",
      "arn:aws:lambda:eu-west-2:111122223333:function:approve:live",
    ])
    error_message = "each hook targets its function, alias included."
  }

  assert {
    condition     = alltrue([for h in aws_ecs_service.this["api"].deployment_configuration[0].lifecycle_hook : h.role_arn == aws_iam_role.infrastructure[0].arn])
    error_message = "ECS invokes every hook with the module's infrastructure role."
  }

  assert {
    condition     = jsondecode(one([for h in aws_ecs_service.this["api"].deployment_configuration[0].lifecycle_hook : h.hook_details if h.hook_target_arn == "arn:aws:lambda:eu-west-2:111122223333:function:smoke-test"])) == { path = "/health" }
    error_message = "hook details reach the hook."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.infrastructure_module[0].policy).Statement == [{
      Sid      = "InvokeDeploymentHooks"
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = ["arn:aws:lambda:eu-west-2:111122223333:function:approve:live", "arn:aws:lambda:eu-west-2:111122223333:function:smoke-test"]
    }]
    error_message = "the infrastructure role may invoke exactly the hook functions."
  }

  assert {
    condition     = jsonencode(output.governance.lifecycle_hooks) == jsonencode({ api = { approve = ["PRE_SCALE_UP"], smoke = ["POST_TEST_TRAFFIC_SHIFT", "POST_PRODUCTION_TRAFFIC_SHIFT"] } })
    error_message = "governance lists each hook and its stages."
  }
}

run "sigint_rollback_reaches_the_service" {
  command = plan

  variables {
    services = {
      api = {
        image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
        port          = 8080
        desired_count = 2
        deployment    = { wait_for_steady_state = true, sigint_rollback = true }
      }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].sigint_rollback && aws_ecs_service.this["api"].wait_for_steady_state
    error_message = "a cancelled run rolls the deployment back while Terraform waits for it."
  }

  assert {
    condition     = jsonencode(output.governance.sigint_rollback) == jsonencode(["api"])
    error_message = "governance lists services that roll back on a cancelled run."
  }
}

run "service_connect_access_logs_and_test_headers_render" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-0123456789abcdef"
    services = {
      api = {
        desired_count = 2
        deployment    = { strategy = "BLUE_GREEN" }
        containers = {
          app = {
            image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
            port_mappings = [{ container_port = 8080, name = "http", app_protocol = "http" }]
          }
        }
        service_connect = {
          access_logs = { include_query_parameters = true }
          expose      = { http = { test_traffic_header = { name = "x-canary", value = "1" } } }
        }
      }
    }
  }

  assert {
    condition     = aws_ecs_service.this["api"].service_connect_configuration[0].access_log_configuration[0] == { format = "JSON", include_query_parameters = "ENABLED" }
    error_message = "access logs default to JSON and send query parameters only when asked."
  }

  assert {
    condition = jsonencode(one(one(aws_ecs_service.this["api"].service_connect_configuration[0].service).client_alias[0].test_traffic_rules).header) == jsonencode([{
      name  = "x-canary"
      value = [{ exact = "1" }]
    }])
    error_message = "the test header routes matching requests to the new revision."
  }

  assert {
    condition     = jsonencode(output.governance.service_connect_access_logs) == jsonencode(["api"])
    error_message = "governance lists services that write Service Connect access logs."
  }
}

# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

run "an_unknown_strategy_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "RECREATE" } } }
  }

  expect_failures = [var.services]
}

run "a_traffic_shifting_strategy_on_a_task_workload_is_rejected" {
  command = plan

  variables {
    services = { job = { image = "r/a:1", workload = "task", deployment = { strategy = "CANARY" } } }
  }

  expect_failures = [var.services]
}

run "bake_times_and_shares_outside_the_api_range_are_rejected" {
  command = plan

  variables {
    services = {
      a = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "BLUE_GREEN", bake_time_minutes = 1441 } }
      b = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "CANARY", canary_percent = 0 } }
      c = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "LINEAR", linear_step_percent = 2 } }
    }
  }

  expect_failures = [var.services]
}

# Without wait_for_steady_state the provider never watches for SIGINT, so the
# flag would read as a guarantee and do nothing.
run "sigint_rollback_without_waiting_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { sigint_rollback = true } } }
  }

  expect_failures = [var.services]
}

run "a_hook_that_is_not_a_lambda_function_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = {
      strategy = "BLUE_GREEN", lifecycle_hooks = { x = { function_arn = "arn:aws:states:eu-west-2:111122223333:stateMachine:x", stages = ["PRE_SCALE_UP"] } }
    } } }
  }

  expect_failures = [var.services]
}

run "a_hook_with_an_unknown_stage_or_no_stage_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = {
      strategy = "BLUE_GREEN"
      lifecycle_hooks = {
        x = { function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:x", stages = ["AFTER_EVERYTHING"] }
        y = { function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:y", stages = [] }
      }
    } } }
  }

  expect_failures = [var.services]
}

run "hook_details_that_are_not_json_are_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = {
      strategy = "BLUE_GREEN", lifecycle_hooks = { x = { function_arn = "arn:aws:lambda:eu-west-2:111122223333:function:x", stages = ["PRE_SCALE_UP"], details = "path=/health" } }
    } } }
  }

  expect_failures = [var.services]
}

# Without an alternate target group and a production rule, ECS has nowhere to
# start the new revision and no rule to move.
run "a_load_balancer_on_blue_green_without_its_alternate_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "BLUE_GREEN" }, load_balancers = [{
      target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-blue/0123456789abcdef"
    }] } }
  }

  expect_failures = [var.services]
}

run "an_alternate_that_is_the_primary_target_group_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, deployment = { strategy = "LINEAR" }, load_balancers = [{
      target_group_arn             = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-blue/0123456789abcdef"
      alternate_target_group_arn   = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-blue/0123456789abcdef"
      production_listener_rule_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:listener-rule/app/web/0123456789abcdef/0123456789abcdef/0123456789abcdef"
    }] } }
  }

  expect_failures = [var.services]
}

run "traffic_shifting_fields_on_a_rolling_service_are_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, load_balancers = [{
      target_group_arn           = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-blue/0123456789abcdef"
      alternate_target_group_arn = "arn:aws:elasticloadbalancing:eu-west-2:111122223333:targetgroup/api-green/0123456789abcdef"
    }] } }
  }

  expect_failures = [var.services]
}

# Access logs are written through the proxy's log configuration.
run "access_logs_without_the_proxy_log_are_rejected" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-0123456789abcdef"
    services                      = { api = { image = "r/a:1", port = 8080, desired_count = 2, service_connect = { log_proxy = false, access_logs = {} } } }
  }

  expect_failures = [var.services]
}

run "a_test_header_on_a_rolling_service_is_rejected" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-0123456789abcdef"
    services = { api = { desired_count = 2, containers = {
      app                = { image = "r/a:1", port_mappings = [{ container_port = 8080, name = "http", app_protocol = "http" }] }
      }, service_connect = { expose = { http = { test_traffic_header = { name = "x-canary", value = "1" } } } }
    } }
  }

  expect_failures = [var.services]
}

# Header rules need an application protocol; a plain TCP port has no headers.
run "a_test_header_on_a_port_without_app_protocol_is_rejected" {
  command = plan

  variables {
    service_connect_namespace_arn = "arn:aws:servicediscovery:eu-west-2:111122223333:namespace/ns-0123456789abcdef"
    services = { api = { desired_count = 2, deployment = { strategy = "BLUE_GREEN" }, containers = {
      app                = { image = "r/a:1", port_mappings = [{ container_port = 8080, name = "http" }] }
      }, service_connect = { expose = { http = { test_traffic_header = { name = "x-canary", value = "1" } } } }
    } }
  }

  expect_failures = [var.services]
}
