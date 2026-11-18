# ECS Managed Instances capacity providers: registration, the two roles they
# need, the services that run on them, and their refusals and warnings.
#
# What a mock cannot show: ECS launching an instance with these roles, or EBS
# encryption by default being on in a real account.

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
  mock_data "aws_ebs_encryption_by_default" {
    defaults = { enabled = true }
  }
  mock_data "aws_iam_instance_profile" {
    defaults = { role_arn = "arn:aws:iam::111122223333:role/platform/agent", role_name = "agent" }
  }
  mock_resource "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::111122223333:role/mock" }
  }
  mock_resource "aws_iam_instance_profile" {
    defaults = { arn = "arn:aws:iam::111122223333:instance-profile/orders-ecs-managed-instances" }
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

  managed_instances_capacity_providers = {
    general = {}
  }

  services = {
    api = {
      image         = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
      port          = 8080
      desired_count = 2
      launch        = "MANAGED_INSTANCES"
      capacity      = "general"
    }
  }
}

run "a_provider_belongs_to_this_cluster_and_is_on_its_list" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["general"].name == "orders-general",
      aws_ecs_capacity_provider.managed_instances["general"].cluster == "orders",
      contains(aws_ecs_cluster_capacity_providers.this[0].capacity_providers, "orders-general"),
      output.capacity_provider_names == { general = "orders-general" },
    ])
    error_message = "the provider is created in the cluster, registered on its provider list, and reported by key."
  }

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].propagate_tags == "CAPACITY_PROVIDER",
      aws_ecs_capacity_provider.managed_instances["general"].tags["CostCenter"] == "cc-1",
    ])
    error_message = "the instances carry the module's tags, so their cost is attributable."
  }

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].capacity_option_type == "ON_DEMAND",
      aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].monitoring == "BASIC",
      toset(aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].network_configuration[0].subnets) == toset(["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"]),
      length(aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].storage_configuration) == 0,
      length(aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].instance_requirements) == 0,
      length(aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].infrastructure_optimization) == 0,
    ])
    error_message = "an empty entry is on-demand, basic monitoring, the module's subnets, and ECS's own storage size, instance choice and consolidation."
  }
}

run "the_module_instance_role_is_named_for_the_managed_policy" {
  command = apply

  assert {
    condition = alltrue([
      aws_iam_role.instance[0].name == "ecsInstanceRole-orders",
      jsondecode(aws_iam_role.instance[0].assume_role_policy).Statement[0].Principal == { Service = "ec2.amazonaws.com" },
      aws_iam_role_policy_attachment.instance[0].policy_arn == "arn:aws:iam::aws:policy/AmazonECSInstanceRolePolicyForManagedInstances",
      aws_iam_instance_profile.instance[0].role == "ecsInstanceRole-orders",
    ])
    error_message = "the instance role starts with ecsInstanceRole, the only names the managed infrastructure policy may pass, and carries the managed instance policy."
  }

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].infrastructure_role_arn == aws_iam_role.infrastructure[0].arn,
      aws_ecs_capacity_provider.managed_instances["general"].managed_instances_provider[0].instance_launch_template[0].ec2_instance_profile_arn == aws_iam_instance_profile.instance[0].arn,
      keys(aws_iam_role_policy_attachment.infrastructure) == ["managed_instances"],
      aws_iam_role_policy_attachment.infrastructure["managed_instances"].policy_arn == "arn:aws:iam::aws:policy/AmazonECSInfrastructureRolePolicyForManagedInstances",
      length(aws_iam_role_policy.infrastructure_module) == 0,
    ])
    error_message = "the provider launches with the module's infrastructure role (managed instances policy only) and instance profile."
  }

  assert {
    condition = alltrue([
      output.managed_instances_instance_profile_arn == aws_iam_instance_profile.instance[0].arn,
      one([for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s.Resource if s.Sid == "PassManagedInstanceRoles"]) == ["arn:aws:iam::111122223333:role/ecsInstanceRole-orders"],
    ])
    error_message = "the deployer is told to pass the instance role, and the profile is an output."
  }
}

# The managed policy only passes roles named ecsInstanceRole*; a supplied
# profile with another role name would fail every instance launch.
run "a_supplied_profile_role_is_passable_by_arn" {
  command = apply

  variables {
    managed_instances_capacity_providers = {
      general = { instance_profile_arn = "arn:aws:iam::111122223333:instance-profile/platform/agent" }
    }
  }

  assert {
    condition     = length(aws_iam_role.instance) == 0 && length(aws_iam_instance_profile.instance) == 0 && output.managed_instances_instance_profile_arn == null
    error_message = "a supplied profile means the module creates no instance role or profile."
  }

  assert {
    condition     = data.aws_iam_instance_profile.managed_instances["general"].name == "agent"
    error_message = "the profile is looked up by its name, the last part of its ARN after any path."
  }

  assert {
    condition = jsondecode(aws_iam_role_policy.infrastructure_module[0].policy).Statement == [{
      Sid       = "PassSuppliedInstanceRoles"
      Effect    = "Allow"
      Action    = ["iam:PassRole"]
      Resource  = ["arn:aws:iam::111122223333:role/platform/agent"]
      Condition = { StringLike = { "iam:PassedToService" = "ec2.*" } }
    }]
    error_message = "the infrastructure role may pass the supplied profile's role to EC2, whatever its name."
  }

  assert {
    condition     = one([for s in jsondecode(output.deployer_requirements.iam_policy).Statement : s.Resource if s.Sid == "ReadSuppliedInstanceProfiles"]) == ["arn:aws:iam::111122223333:instance-profile/platform/agent"]
    error_message = "the plan reads the supplied profile, and the deployer is told so."
  }
}

run "a_service_on_managed_instances_runs_on_its_provider" {
  command = plan

  assert {
    condition = alltrue([
      aws_ecs_task_definition.this["api"].requires_compatibilities == toset(["MANAGED_INSTANCES"]),
      [for p in aws_ecs_service.this["api"].capacity_provider_strategy : p.capacity_provider] == ["orders-general"],
    ])
    error_message = "the task definition is MANAGED_INSTANCES and the service's strategy names the registered provider."
  }

  assert {
    condition     = contains(output.network_contract.required_interface_endpoints, "com.amazonaws.eu-west-2.ecs-agent") && jsonencode(output.network_contract.managed_instances.general.subnet_ids) == jsonencode(["subnet-0a1b2c3d4e5f60001", "subnet-0a1b2c3d4e5f60002"])
    error_message = "the instances run the ECS agent, so the contract names the ecs endpoints and where the instances live."
  }

  assert {
    condition     = output.governance.managed_instances == { general = "ON_DEMAND" } && output.governance.managed_instance_volumes == "EBS encryption by default"
    error_message = "governance reports the providers and how their volumes are encrypted."
  }
}

run "instance_requirements_storage_and_consolidation_render_when_asked" {
  command = plan

  variables {
    managed_instances_capacity_providers = {
      gpu = {
        subnet_ids             = ["subnet-0a1b2c3d4e5f60009"]
        capacity_option_type   = "SPOT"
        monitoring             = "DETAILED"
        storage_size_gib       = 200
        scale_in_after_seconds = -1
        instance_requirements = {
          vcpu_min              = 4
          vcpu_max              = 16
          memory_mib_min        = 16384
          cpu_manufacturers     = ["intel", "amd"]
          accelerator_types     = ["gpu"]
          accelerator_count_min = 1
        }
      }
    }
    services = {
      api = {
        image                      = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0"
        port                       = 8080
        desired_count              = 2
        launch                     = "MANAGED_INSTANCES"
        capacity_provider_strategy = [{ capacity_provider = "gpu" }]
      }
    }
    acknowledged_checks = ["spot_services_keep_an_on_demand_floor"]
  }

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].instance_requirements[0].vcpu_count[0].max == 16,
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].instance_requirements[0].memory_mib[0].max == null,
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].instance_requirements[0].accelerator_count[0].min == 1,
      toset(aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].instance_requirements[0].accelerator_types) == toset(["gpu"]),
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].instance_requirements[0].burstable_performance == "excluded",
    ])
    error_message = "instance requirements render ranges with open maxima, accelerators, and the same burstable default as modules/asg-group."
  }

  assert {
    condition = alltrue([
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].storage_configuration[0].storage_size_gib == 200,
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].infrastructure_optimization[0].scale_in_after == -1,
      aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].capacity_option_type == "SPOT",
      toset(aws_ecs_capacity_provider.managed_instances["gpu"].managed_instances_provider[0].instance_launch_template[0].network_configuration[0].subnets) == toset(["subnet-0a1b2c3d4e5f60009"]),
    ])
    error_message = "storage size, consolidation, Spot and the provider's own subnets are sent."
  }

  assert {
    condition     = jsonencode(output.governance.services_on_spot) == jsonencode(["api"])
    error_message = "a service on a SPOT Managed Instances provider counts as on Spot."
  }
}

run "default_capacity_can_be_a_managed_instances_provider" {
  command = plan

  variables {
    default_capacity = "general"
  }

  assert {
    condition     = jsonencode(aws_ecs_cluster_capacity_providers.this[0].default_capacity_provider_strategy) == jsonencode([{ base = 0, capacity_provider = "orders-general", weight = 1 }])
    error_message = "the cluster default resolves a Managed Instances key to its registered name."
  }
}

# ---------------------------------------------------------------------------
# Warnings
# ---------------------------------------------------------------------------

run "spot_managed_instances_without_an_on_demand_share_warn" {
  command = plan

  variables {
    managed_instances_capacity_providers = { spot = { capacity_option_type = "SPOT" } }
    services = {
      api = { image = "111122223333.dkr.ecr.eu-west-2.amazonaws.com/api:1.0.0", port = 8080, desired_count = 2, launch = "MANAGED_INSTANCES", capacity = "spot" }
    }
  }

  expect_failures = [check.spot_services_keep_an_on_demand_floor]
}

# The capacity provider has no encryption setting; the account default decides.
run "unencrypted_default_ebs_warns" {
  command = plan

  override_data {
    target = data.aws_ebs_encryption_by_default.current[0]
    values = { enabled = false }
  }

  expect_failures = [check.managed_instance_volumes_are_encrypted]
}

# ---------------------------------------------------------------------------
# Refusals
# ---------------------------------------------------------------------------

run "a_managed_instances_service_without_capacity_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, launch = "MANAGED_INSTANCES" } }
  }

  expect_failures = [var.services]
}

run "a_managed_instances_service_on_an_ec2_provider_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { asg = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services               = { api = { image = "r/a:1", port = 8080, desired_count = 2, launch = "MANAGED_INSTANCES", capacity = "asg" } }
  }

  expect_failures = [var.services]
}

run "bridge_networking_on_managed_instances_is_rejected" {
  command = plan

  variables {
    services = { api = { image = "r/a:1", port = 8080, desired_count = 2, launch = "MANAGED_INSTANCES", capacity = "general", network_mode = "bridge" } }
  }

  expect_failures = [var.services]
}

run "provider_settings_outside_the_api_range_are_rejected" {
  command = plan

  variables {
    managed_instances_capacity_providers = {
      general = { capacity_option_type = "RESERVED", storage_size_gib = 20, scale_in_after_seconds = 4000 }
    }
  }

  expect_failures = [var.managed_instances_capacity_providers]
}

run "a_managed_instances_key_that_is_an_ec2_key_is_rejected" {
  command = plan

  variables {
    ec2_capacity_providers = { general = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
  }

  expect_failures = [var.managed_instances_capacity_providers]
}

run "instance_requirements_with_an_inverted_range_are_rejected" {
  command = plan

  variables {
    managed_instances_capacity_providers = { general = { instance_requirements = { vcpu_min = 8, vcpu_max = 4 } } }
  }

  expect_failures = [var.managed_instances_capacity_providers]
}

# ECS refuses capacity provider names starting with aws, ecs or fargate.
run "a_cluster_name_ecs_would_refuse_as_a_provider_prefix_is_rejected" {
  command = plan

  variables {
    name = "ecs-orders"
  }

  expect_failures = [var.managed_instances_capacity_providers]
}

run "an_ec2_provider_under_a_refused_prefix_is_rejected_too" {
  command = plan

  variables {
    name                                 = "fargate-orders"
    managed_instances_capacity_providers = {}
    ec2_capacity_providers               = { asg = { auto_scaling_group_arn = "arn:aws:autoscaling:eu-west-2:111122223333:autoScalingGroup:x:autoScalingGroupName/g" } }
    services                             = { api = { image = "r/a:1", port = 8080, desired_count = 2 } }
  }

  expect_failures = [var.ec2_capacity_providers]
}

run "a_provider_with_no_subnets_anywhere_is_rejected" {
  command = plan

  variables {
    subnet_ids = []
    services   = {}
  }

  expect_failures = [aws_ecs_capacity_provider.managed_instances["general"]]
}
