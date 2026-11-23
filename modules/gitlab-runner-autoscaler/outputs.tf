# ---------------------------------------------------------------------------
# Resources
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "ECS cluster the managers run on."
  value       = module.managers.cluster_name
}

output "manager_service_names" {
  description = "ECS service of each pool's manager, by pool."
  value       = local.create ? module.managers.service_names : {}
}

output "manager_task_role_arns" {
  description = "Task role of each pool's manager, by pool: the identity that scales the fleet, pulls job images and signs cache transfers."
  value       = local.create ? module.managers.task_role_arns : {}
}

output "manager_execution_role_arns" {
  description = "Execution role of each pool's manager, by pool: the identity that reads the token and the SSH key at task start. The token parameter or secret, and its key, must let it read."
  value       = local.create ? module.managers.execution_role_arns : {}
}

output "manager_log_group_names" {
  description = "CloudWatch log group of each pool's manager, by pool."
  value       = local.create ? module.managers.log_group_names : {}
}

output "autoscaling_group_names" {
  description = "Auto Scaling group of each pool, by pool."
  value       = { for k, m in module.fleet : k => m.autoscaling_group_name }
}

output "instance_role_arns" {
  description = "IAM role of each pool's job instances, by pool. It has Session Manager, an explicit deny on the runner's token and SSH key, and, on pools with aws_access, what the jobs get."
  value       = { for k, m in module.fleet : k => m.iam_role_arn }
}

output "job_role_trust_policies" {
  description = "For each pool with aws_access.assume_role_arns: the trust policy (JSON) the roles jobs assume must carry. It admits any instance role of that pool's fleet, by name prefix and pool tag, so it survives the role being replaced."
  value       = local.job_role_trust_policies
}

output "security_group_ids" {
  description = "The managers' and the job instances' security groups: { manager, instance }. Reference instance from a database's group to let jobs reach it."
  value       = local.create ? local.security_group_ids : null
}

output "cache_bucket" {
  description = "The cache bucket: { name, arn, created }. created is false for a bucket passed as cache.bucket_name. Null without a cache."
  value       = local.create && var.cache.enabled ? { name = local.cache_bucket, arn = local.cache_bucket_arn, created = local.cache_creates_bucket } : null
}

output "config_toml" {
  description = "Each pool's config.toml as the manager writes it, by pool, with the token as a placeholder. Review it in the plan."
  value       = local.config_toml
}

output "alarm_names" {
  description = "Alarms by pool: this module's (manager_errors, system_failures, at_ceiling, instances_without_manager, acquire_timeouts with the collector) and the manager service's from modules/ecs (cpu, memory, running_tasks)."
  value = { for k, p in local.active_pools : k => merge(
    lookup(module.managers.alarm_names, k, {}),
    !var.monitoring.alarms ? {} : {
      manager_errors            = aws_cloudwatch_metric_alarm.manager_errors[k].alarm_name
      system_failures           = aws_cloudwatch_metric_alarm.system_failures[k].alarm_name
      at_ceiling                = aws_cloudwatch_metric_alarm.at_ceiling[k].alarm_name
      instances_without_manager = aws_cloudwatch_metric_alarm.instances_without_manager[k].alarm_name
    },
    local.collect_metrics && var.monitoring.alarms ? { acquire_timeouts = aws_cloudwatch_metric_alarm.acquire_timeouts[k].alarm_name } : {},
  ) }
}

output "dashboard_name" {
  description = "The CloudWatch dashboard of every pool. Null when monitoring.dashboard is off or there are no pools."
  value       = one(aws_cloudwatch_dashboard.this[*].dashboard_name)
}

# ---------------------------------------------------------------------------
# Contracts
# ---------------------------------------------------------------------------

locals {
  uses_customer_keys = length(compact(concat([var.kms_key_arn, local.cache_kms_key_arn], var.secrets_kms_key_arns))) > 0
  endpoint_names = sort(distinct(concat(
    ["ec2", "autoscaling", "ecr.api", "ecr.dkr", "logs", "secretsmanager", "ssm", "ssmmessages", "ec2messages"],
    local.uses_customer_keys ? ["kms"] : [],
    length(local.aws_pools) > 0 ? ["sts"] : [],
  )))
}

output "network_contract" {
  description = "What the subnets must reach for the managers and job instances to work: interface endpoints (private DNS on), the S3 gateway endpoint, and the hosts on 443. Known at plan."
  value = !local.create ? null : {
    interface_endpoints    = local.endpoint_names
    endpoint_service_names = [for e in local.endpoint_names : "com.amazonaws.${local.region}.${e}"]
    gateway_endpoints      = ["com.amazonaws.${local.region}.s3"]
    https_hosts = sort(distinct(concat(
      [regex("^https://([^/:]+)", var.gitlab_url)[0]],
      [for i in local.image_references : split("/", i)[0]],
      local.ecr_registries,
      var.docker_registry_mirror != "" ? [regex("^https://([^/:]+)", var.docker_registry_mirror)[0]] : [],
      var.monitoring.metrics_collector_image != "" ? [split("/", var.monitoring.metrics_collector_image)[0]] : [],
    )))
    ports = {
      manager_to_instance = 22
      outbound            = 443
    }
    notes = concat(
      [
        "ec2 and autoscaling are what the fleeting plugin calls; without them the manager starts and every job waits for an instance that never comes.",
        "The S3 gateway endpoint carries image layers and, with a cache, the cache archives; cache URLs use the regional S3 endpoint, not dual-stack.",
        "ssmmessages and ec2messages serve Session Manager on the job instances; they are not on the job path.",
        "EC2 Instance Connect is not used: the managers connect with a static key.",
      ],
      length(local.aws_pools) > 0 ? ["sts serves jobs on pools with aws_access that assume roles, and every AWS service those jobs call needs its own endpoint."] : [],
    )
  }
}

output "kms_key_policy_requirements" {
  description = "What each customer managed key's policy has to allow, in contract version 2: key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. The fleets', managers' and cache bucket's requirements with their sids prefixed, plus the cache signers and the metrics log group. The symbolic role deployer is whoever runs Terraform."
  value = !local.create ? null : distinct(concat(
    flatten([for k, m in module.fleet : [for r in coalesce(m.kms_key_policy_requirements, []) : merge(r, { sid = "Fleet${r.sid}" })]]),
    [for r in coalesce(module.managers.kms_key_policy_requirements, []) : merge(r, { sid = "Managers${r.sid}" })],
    # modules/s3's symbolic bucket_readers and bucket_writers are the managers here, named below.
    [for r in coalesce(module.cache.kms_key_policy_requirements, []) : merge(r, { sid = "Cache${r.sid}" }) if !contains(["BucketWriters", "BucketReaders"], r.sid)],
    local.cache_kms_key_arn == "" || length(local.cache_policy) == 0 ? [] : [{
      key        = local.cache_kms_key_arn
      sid        = "CacheSigners"
      principals = { services = [], arns = sort([for k, p in local.active_pools : p.task_role_arn if p.uses_cache]), roles = [] }
      actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
      purpose    = "The managers sign cache uploads and downloads; S3 encrypts and decrypts under the signer's identity, so without this every cache transfer fails with AccessDenied."
    }],
    !local.collect_metrics || var.kms_key_arn == "" ? [] : [{
      key        = var.kms_key_arn
      sid        = "MetricsLogGroup"
      principals = { services = ["logs.${local.region}.amazonaws.com"], arns = [], roles = [] }
      actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
      conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${local.metrics_log_group}"] }]
      purpose    = "CloudWatch Logs encrypts the collector's log group with this key; creating it fails without."
    }],
  ))
}

output "deployer_requirements" {
  description = "IAM the identity running Terraform needs beyond what modules/asg-group, modules/ecs and modules/s3 list: security groups, the key pair, metric filters, alarms and the dashboard."
  value = !local.create ? null : {
    children = {
      fleet    = { for k, m in module.fleet : k => m.deployer_requirements }
      managers = module.managers.deployer_requirements
      cache    = local.cache_creates_bucket ? "modules/s3: see its README, \"Deployer permissions\"" : null
    }
    actions = [
      "ec2:CreateSecurityGroup", "ec2:DeleteSecurityGroup", "ec2:AuthorizeSecurityGroupEgress", "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress", "ec2:RevokeSecurityGroupIngress", "ec2:DescribeSecurityGroups", "ec2:DescribeSecurityGroupRules",
      "ec2:ImportKeyPair", "ec2:DeleteKeyPair", "ec2:DescribeKeyPairs", "ec2:DescribeManagedPrefixLists", "ec2:CreateTags",
      "logs:PutMetricFilter", "logs:DeleteMetricFilter", "logs:DescribeMetricFilters",
      "logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:AssociateKmsKey", "logs:TagResource",
      "cloudwatch:PutMetricAlarm", "cloudwatch:DeleteAlarms", "cloudwatch:DescribeAlarms", "cloudwatch:TagResource", "cloudwatch:ListTagsForResource",
      "cloudwatch:PutDashboard", "cloudwatch:GetDashboard", "cloudwatch:DeleteDashboards",
    ]
  }
}

output "governance" {
  description = "Facts a change review needs, as data: acknowledged checks (this module's and those passed to the child modules), and per pool privilege, sharing, ceiling, Spot, AWS access, cache and token source."
  value = !local.create ? null : {
    acknowledged_checks = sort(var.acknowledged_checks)
    built_in_acknowledgements = {
      asg_group = sort(local.built_in_acknowledgements.fleet)
      ecs       = sort(local.built_in_acknowledgements.ecs)
      s3        = sort(local.built_in_acknowledgements.cache)
    }
    pools = { for k, p in local.active_pools : k => {
      privileged            = p.privileged
      capacity_per_instance = p.capacity_per_instance
      max_use_count         = p.max_use_count
      max_instances         = p.max_instances
      spot                  = p.spot
      instance_types        = p.instance_types
      enabled               = p.enabled
      token_arn             = p.token_arn
      shared_cache          = p.uses_cache
      jobs_use_aws          = p.jobs_use_aws
      job_role_arns         = p.jobs_use_aws ? sort(p.aws_access.assume_role_arns) : []
      imds_hop_limit        = p.jobs_use_aws ? 2 : 1
    } }
    cache = !var.cache.enabled ? null : {
      bucket              = local.cache_bucket
      created             = local.cache_creates_bucket
      expiration_days     = var.cache.expiration_days
      compression         = "${var.cache.compression_format} ${var.cache.compression_level}"
      endpoint_restricted = length(var.cache.vpc_endpoint_ids) > 0
    }
    monitoring = {
      alarms         = var.monitoring.alarms
      notifications  = var.sns_topic_arn != ""
      dashboard      = var.monitoring.dashboard
      runner_metrics = local.collect_metrics
    }
    runner_version = var.runner_version
    manager_image  = var.manager_image
    helper_image   = var.helper_image
  }
}

output "verify_commands" {
  description = "Commands to run from CloudShell after an apply: check a pool's token, restart its manager, follow its log, watch its fleet."
  value = !local.create ? null : { for k, p in local.active_pools : k => {
    token_is_set     = startswith(split(":", p.token_arn)[2], "ssm") ? "aws ssm get-parameter --region ${split(":", p.token_arn)[3]} --name ${trimprefix(split(":", p.token_arn)[5], "parameter")} --with-decryption --query Parameter.Value --output text | cut -c1-5" : "aws secretsmanager get-secret-value --region ${split(":", p.token_arn)[3]} --secret-id ${p.token_arn} --query SecretString --output text | cut -c1-5"
    restart_manager  = "aws ecs update-service --region ${local.region} --cluster ${module.managers.cluster_name} --service ${module.managers.service_names[k]} --force-new-deployment"
    manager_logs     = "aws logs tail --region ${local.region} ${module.managers.log_group_names[k]} --follow"
    fleet_instances  = "aws autoscaling describe-auto-scaling-groups --region ${local.region} --auto-scaling-group-names ${module.fleet[k].autoscaling_group_name} --query 'AutoScalingGroups[0].Instances'"
    scaling_activity = "aws autoscaling describe-scaling-activities --region ${local.region} --auto-scaling-group-name ${module.fleet[k].autoscaling_group_name} --max-items 10"
  } }
}
