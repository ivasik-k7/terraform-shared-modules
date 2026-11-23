locals {
  manager_environment = { for k, p in local.active_pools : k => merge(
    {
      CONFIG_TOML_B64   = base64encode(local.config_toml[k])
      DOCKER_CONFIG_B64 = base64encode(local.docker_config)
      SSH_KEY_PATH      = local.ssh_key_path
      TOKEN_REVISION    = tostring(p.token_revision)
    },
    var.ca_certificate_pem == "" ? {} : { CA_CERTIFICATE_B64 = base64encode(var.ca_certificate_pem) },
  ) }

  manager_containers = { for k, p in local.active_pools : k => merge(
    {
      manager = {
        image       = var.manager_image
        environment = local.manager_environment[k]
        secrets = {
          RUNNER_TOKEN     = p.token_arn
          FLEETING_SSH_KEY = var.ssh_private_key_secret_arn
        }
        # Fargate's ceiling; the runner's shutdown_timeout stays below it.
        # https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_ContainerDefinition.html
        stop_timeout = 120
      }
    },
    !local.collect_metrics ? {} : {
      metrics = {
        image       = var.monitoring.metrics_collector_image
        essential   = false
        environment = { AOT_CONFIG_CONTENT = local.collector_config[k] }
      }
    },
  ) }
}

# GitLab requires a dedicated Auto Scaling group per docker-autoscaler
# configuration, so each pool has one manager and a deployment stops it first.
# https://docs.gitlab.com/runner/executors/docker_autoscaler/
module "managers" {
  source = "../ecs"
  create = local.create

  name                = var.name
  tags                = local.tags
  required_tag_keys   = var.required_tag_keys
  acknowledged_checks = local.ecs_acknowledged

  subnet_ids         = var.subnet_ids
  security_group_ids = local.create ? [local.security_group_ids.manager] : []

  log_retention_days       = var.log_retention_days
  log_kms_key_arn          = var.kms_key_arn
  secrets_kms_key_arns     = local.secrets_kms_key_arns
  permissions_boundary_arn = var.permissions_boundary_arn
  sns_topic_arn            = var.sns_topic_arn
  create_event_rules       = var.sns_topic_arn != ""

  services = { for k, p in local.active_pools : k => {
    cpu           = p.manager_cpu
    memory        = p.manager_memory
    containers    = local.manager_containers[k]
    desired_count = p.enabled ? 1 : 0
    deployment = {
      minimum_healthy_percent       = 0
      maximum_percent               = 100
      availability_zone_rebalancing = false
    }
    task_role = {
      policies = merge(
        { fleeting = local.fleeting_policy[k] },
        local.pull_policy == "" ? {} : { ecr-pull = local.pull_policy },
        p.uses_cache ? { cache = local.cache_policy[k] } : {},
        local.collect_metrics ? { metrics = local.metrics_policy } : {},
      )
    }
    tags = p.tags
  } }
}
