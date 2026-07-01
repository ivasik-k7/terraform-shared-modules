# full apply against mocked aws - builds the whole graph offline.

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" }
  }
  mock_resource "aws_ecs_cluster" {
    defaults = {
      id   = "arn:aws:ecs:us-east-1:123456789012:cluster/test"
      arn  = "arn:aws:ecs:us-east-1:123456789012:cluster/test"
      name = "test"
    }
  }
  mock_resource "aws_ecs_task_definition" {
    defaults = { arn = "arn:aws:ecs:us-east-1:123456789012:task-definition/test-web:1" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/mock", name = "mock" }
  }
  mock_resource "aws_service_discovery_service" {
    defaults = { arn = "arn:aws:servicediscovery:us-east-1:123456789012:service/srv-abc" }
  }
  mock_resource "aws_security_group" {
    defaults = { id = "sg-0123456789abcdef0", arn = "arn:aws:ec2:us-east-1:123456789012:security-group/sg-0123456789abcdef0" }
  }
}

# --- Comprehensive: mixed launch, LB, secrets, SG, discovery, autoscaling ----
run "full_stack_apply" {
  command = apply

  variables {
    cluster_name              = "test"
    vpc_id                    = "vpc-12345678"
    default_subnets           = ["subnet-aaaa1111", "subnet-bbbb2222"]
    service_connect_namespace = "arn:aws:servicediscovery:us-east-1:123456789012:namespace/ns-abc"
    enable_container_insights = true

    ec2_capacity_providers = {
      ec2-od = { auto_scaling_group_arn = "arn:aws:autoscaling:us-east-1:123456789012:autoScalingGroup:uuid:autoScalingGroupName/my-asg" }
    }

    services = {
      api = {
        cpu                      = 512
        memory                   = 1024
        requires_compatibilities = ["FARGATE", "EC2"]
        capacity_provider_strategy = [
          { capacity_provider = "FARGATE", weight = 1, base = 1 },
          { capacity_provider = "ec2-od", weight = 3, base = 0 },
        ]
        containers = {
          api = {
            image         = "myapp:1"
            port_mappings = [{ container_port = 8080, name = "http" }]
            secrets       = { DB_PASSWORD = "arn:aws:secretsmanager:us-east-1:123456789012:secret:db-abc" }
            environment   = { LOG_LEVEL = "info" }
          }
        }
        create_security_group = true
        load_balancers        = [{ target_group_arn = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/api/abc", container_name = "api", container_port = 8080 }]
        service_connect       = { services = [{ port_name = "http", client_alias = { dns_name = "api", port = 8080 } }] }
        service_discovery     = { namespace_id = "ns-abc123" }
        task_role_policies    = { s3 = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess" }
        autoscaling           = { min_capacity = 2, max_capacity = 20, cpu_target = 60, memory_target = 70, scheduled = { nightly = { schedule = "cron(0 19 * * ? *)", min_capacity = 0, max_capacity = 0 } } }
      }
    }
  }

  assert {
    condition     = length(aws_ecs_cluster.this) == 1 && length(aws_ecs_service.autoscaled) == 1 && length(aws_ecs_service.static) == 0
    error_message = "Cluster + one autoscaled service expected"
  }

  assert {
    condition     = length(aws_ecs_capacity_provider.ec2) == 1
    error_message = "EC2 capacity provider expected"
  }

  assert {
    condition     = length(aws_iam_role.execution) == 1 && length(aws_iam_role.task) == 1 && length(aws_iam_role_policy.execution_secrets) == 1
    error_message = "Execution role + task role + secrets policy expected"
  }

  assert {
    condition     = length(aws_security_group.service) == 1 && length(aws_service_discovery_service.this) == 1
    error_message = "Service SG + discovery expected"
  }

  assert {
    condition     = length(aws_appautoscaling_target.this) == 1 && length(aws_appautoscaling_policy.cpu) == 1 && length(aws_appautoscaling_policy.memory) == 1 && length(aws_appautoscaling_scheduled_action.this) == 1
    error_message = "Autoscaling target + cpu/mem policies + scheduled action expected"
  }
}

# --- Minimal Fargate, BYO execution role, no extras -------------------------
run "minimal_apply" {
  command = apply

  variables {
    cluster_name            = "test-min"
    default_subnets         = ["subnet-aaaa1111"]
    task_execution_role_arn = "arn:aws:iam::123456789012:role/existing-exec"
    services = {
      web = { image = "nginx:alpine", port = 80 }
    }
  }

  assert {
    condition     = length(aws_iam_role.execution) == 0
    error_message = "No execution role created when one is provided"
  }

  assert {
    condition     = length(aws_ecs_service.static) == 1 && length(aws_appautoscaling_target.this) == 0
    error_message = "Static service, no autoscaling"
  }
}
