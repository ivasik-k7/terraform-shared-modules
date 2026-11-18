# ---------------------------------------------------------------------------
# Resources: what callers wire to their other resources.
# ---------------------------------------------------------------------------

output "cluster_name" {
  description = "Cluster name."
  value       = one(aws_ecs_cluster.this[*].name)
}

output "cluster_arn" {
  description = "Cluster ARN."
  value       = one(aws_ecs_cluster.this[*].arn)
}

output "capacity_provider_names" {
  description = "Registered name of each ec2_capacity_providers and managed_instances_capacity_providers entry, by key."
  value       = merge({ for k, p in aws_ecs_capacity_provider.ec2 : k => p.name }, { for k, p in aws_ecs_capacity_provider.managed_instances : k => p.name })
}

output "service_arns" {
  description = "ECS service ARN by workload key, for service and daemon workloads."
  value       = { for k, s in merge(aws_ecs_service.this, aws_ecs_service.autoscaled, aws_ecs_service.static_ignored, aws_ecs_service.autoscaled_ignored) : k => s.id }
}

output "service_names" {
  description = "ECS service name by workload key (the key itself), for service and daemon workloads."
  value       = { for k, s in merge(aws_ecs_service.this, aws_ecs_service.autoscaled, aws_ecs_service.static_ignored, aws_ecs_service.autoscaled_ignored) : k => s.name }
}

output "task_definition_arns" {
  description = "Current task definition revision ARN by workload key."
  value       = { for k, t in aws_ecs_task_definition.this : k => t.arn }
}

output "task_definition_families" {
  description = "Task definition family by workload key: <name>-<key>."
  value       = { for k, t in aws_ecs_task_definition.this : k => t.family }
}

output "task_role_arns" {
  description = "Task role ARN by workload key, created or supplied. Grant the application's access to these."
  value       = local.create ? local.task_role_arn : {}
}

output "task_role_names" {
  description = "Name of each task role the module created, by workload key. Attach further policies to these from the calling root."
  value       = { for k, r in aws_iam_role.task : k => r.name }
}

output "execution_role_arns" {
  description = "Task execution role ARN by workload key, created or supplied."
  value       = local.create ? local.execution_role_arn : {}
}

output "log_group_names" {
  description = "Log group each workload writes to, by key: /ecs/<name>/<key>, or its log_group.name (created or existing)."
  value       = local.create ? local.log_group_name : {}
}

output "log_group_arns" {
  description = "ARN of each log group the module created, by workload key, without the :* suffix."
  value       = { for k, g in aws_cloudwatch_log_group.this : k => g.arn }
}

output "alarm_names" {
  description = "CloudWatch alarm names by workload key, for deployment alarms or dashboards: cpu, memory and (with Container Insights) running_tasks."
  value = { for k, s in local.alarmed : k => merge(
    { cpu = aws_cloudwatch_metric_alarm.cpu[k].alarm_name, memory = aws_cloudwatch_metric_alarm.memory[k].alarm_name },
    contains(keys(aws_cloudwatch_metric_alarm.running_tasks), k) ? { running_tasks = aws_cloudwatch_metric_alarm.running_tasks[k].alarm_name } : {},
  ) }
}

output "schedule_arns" {
  description = "EventBridge Scheduler schedule ARN by scheduled workload key."
  value       = { for k, s in aws_scheduler_schedule.this : k => s.arn }
}

output "infrastructure_role_arn" {
  description = "The role ECS acts on infrastructure with: managed EBS volumes, load balancer rules during BLUE_GREEN, LINEAR and CANARY deployments, deployment lifecycle hooks, Managed Instances. Null when nothing uses it."
  value       = local.create && local.infrastructure_used ? local.infrastructure_arn : null
}

output "managed_instances_instance_profile_arn" {
  description = "The instance profile the module created for Managed Instances (role ecsInstanceRole-<name>). Null when every provider names its own."
  value       = one(aws_iam_instance_profile.instance[*].arn)
}

# ---------------------------------------------------------------------------
# Contracts: facts another team acts on, as data rather than prose.
# ---------------------------------------------------------------------------

output "governance" {
  description = "The posture of this cluster as data: assert on it in tests, diff it in a change review."
  value = !local.create ? null : {
    workloads                   = { for k, s in local.services : k => s.workload }
    capacity                    = local.strategy
    services_on_spot            = sort([for k, w in local.spot_weight : k if w > 0])
    services_without_rollback   = local.services_without_rollback
    single_task_services        = local.single_task_services
    spot_without_on_demand      = local.spot_without_floor
    az_rebalancing              = local.services_with_az_rebalancing
    deployment_strategies       = local.deployment_strategies
    traffic_shifted             = sort(keys(local.traffic_shifted))
    lifecycle_hooks             = { for k, s in local.hooked : k => { for n, h in s.deployment.lifecycle_hooks : n => h.stages } }
    sigint_rollback             = sort([for k, s in local.replica : k if s.deployment.sigint_rollback])
    service_connect_access_logs = local.access_logged
    managed_instances           = { for k, p in local.managed_instances : k => p.capacity_option_type }
    managed_instance_volumes    = length(local.managed_instances) == 0 ? "no managed instances" : (local.managed_instance_volumes_encrypted ? "EBS encryption by default" : "unencrypted")
    autoscaled                  = sort(keys(local.autoscaled))
    scheduled                   = { for k, s in local.scheduled : k => "${s.schedule.expression} ${s.schedule.timezone}" }
    unpinned_images             = local.unpinned_images
    externally_deployed         = local.externally_deployed
    service_discovery           = { for k, s in local.long_running : k => "${s.service_discovery.namespace_id != "" ? "created" : "existing"} ${s.service_discovery.dns_record_type}" if s.service_discovery != null }
    log_groups_not_managed      = sort([for k, s in local.services : k if !s.log_group.create])
    log_retention_by_workload   = local.log_retention
    mutable_tag_images          = local.mutable_tag_images
    external_registries         = local.external_registries
    host_access                 = local.host_access
    administrator_roles         = local.administrator_roles
    secret_looking_environment  = local.secret_looking_environment
    exec_logging                = length(local.exec_services) == 0 ? "no exec" : var.execute_command.logging
    writable_root_filesystems   = local.writable_root_containers
    shell_access                = local.services_with_shell_access
    public_ip                   = local.services_with_public_ip
    untagged_tasks              = local.untagged_task_services
    schedules_without_dlq       = local.schedules_without_dlq
    container_insights          = var.container_insights
    log_retention_days          = var.log_retention_days
    log_keys_by_workload        = { for k, key in local.log_key : k => key != "" ? key : "CloudWatch Logs' own encryption" }
    ephemeral_customer_key      = var.fargate_ephemeral_storage_kms_key_arn != ""
    notifications               = var.sns_topic_arn != ""
    alarms                      = sort(keys(local.alarmed))
    event_rules                 = sort(keys(local.event_rules))
    required_tag_keys           = sort(var.required_tag_keys)
    acknowledged_checks         = sort(var.acknowledged_checks)
  }
}

output "network_contract" {
  description = <<-EOT
    What the tasks need from YOUR network, as data. The module creates no network
    resources. In a subnet with no route to the internet, a missing endpoint shows
    as tasks stuck in PROVISIONING or stopped with CannotPullContainerError or
    ResourceInitializationError, not as an error at apply.
  EOT
  value = !local.create ? null : {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
    per_workload = { for k, s in local.services : k => {
      subnet_ids         = local.subnets[k]
      security_group_ids = local.security_groups[k]
      public_ip          = s.assign_public_ip
    } if s.network_mode == "awsvpc" }
    managed_instances = { for k, p in local.managed_instances : k => {
      subnet_ids         = length(p.subnet_ids) > 0 ? p.subnet_ids : var.subnet_ids
      security_group_ids = length(p.security_group_ids) > 0 ? p.security_group_ids : var.security_group_ids
    } }

    required_interface_endpoints = sort(distinct(concat(
      ["com.amazonaws.${local.region}.logs"],
      length(local.ecr_images) > 0 ? ["com.amazonaws.${local.region}.ecr.api", "com.amazonaws.${local.region}.ecr.dkr"] : [],
      anytrue([for k, refs in local.secret_refs : anytrue([for v in refs : strcontains(v, ":secretsmanager:")])]) ? ["com.amazonaws.${local.region}.secretsmanager"] : [],
      anytrue([for k, refs in local.secret_refs : anytrue([for v in refs : strcontains(v, ":ssm:")])]) ? ["com.amazonaws.${local.region}.ssm"] : [],
      length(local.exec_services) > 0 && var.execute_command.kms_key_arn != "" ? ["com.amazonaws.${local.region}.kms"] : [],
      length(local.exec_services) > 0 ? ["com.amazonaws.${local.region}.ssmmessages"] : [],
      local.container_instances ? ["com.amazonaws.${local.region}.ecs", "com.amazonaws.${local.region}.ecs-agent", "com.amazonaws.${local.region}.ecs-telemetry"] : [],
      length([for k, s in local.long_running : k if s.service_connect != null]) > 0 ? ["com.amazonaws.${local.region}.ecs-agent"] : [],
    )))
    gateway_endpoints = length(local.ecr_images) + length(flatten(values(local.environment_file_arns))) > 0 || var.execute_command.s3_bucket_name != "" ? ["com.amazonaws.${local.region}.s3"] : []

    required_egress = concat(
      ["443 to the interface endpoints above, and to the S3 gateway prefix list"],
      length(local.efs_volumes) > 0 ? ["2049 to the EFS mount targets of: ${join(", ", sort(distinct(local.efs_volumes)))}"] : [],
      length(local.external_registries) > 0 ? ["443 to the image registries outside ECR: ${join(", ", local.external_registries)} (needs a NAT or proxy path; there is no endpoint for them)"] : [],
    )

    notes = compact([
      "Interface endpoints need private DNS enabled, or tasks resolve the public names and hang until they time out.",
      "The endpoints' own security groups must allow 443 inbound from the task security groups.",
      "ECR stores image layers in S3: without the s3 gateway endpoint (or another S3 path), the pull fails after authentication succeeds.",
      "Fargate tasks need no ecs endpoints, except ecs-agent, which Service Connect's proxy is managed through; EC2 container instances and Managed Instances run the ECS agent and need ecs, ecs-agent and ecs-telemetry (https://docs.aws.amazon.com/AmazonECS/latest/developerguide/vpc-endpoints.html).",
      "Load balancer health checks arrive from the load balancer's subnets: the task security groups must allow the container port from the load balancer's security group.",
      length(local.imds_reachable_workloads) == 0 ? "" : "EC2 workloads in bridge or host network mode (${join(", ", local.imds_reachable_workloads)}) can reach the instance metadata service and the container instance role's credentials unless the instances block it (ECS_AWSVPC_BLOCK_IMDS, or the iptables rule in https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html).",
    ])
  }
}

output "kms_key_policy_requirements" {
  description = "What each customer managed key's policy has to allow, in contract version 2: key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. Known at plan, so the key owner can act before the apply. The symbolic role deployer is whoever runs Terraform; exec_operators is whoever runs aws ecs execute-command."
  value = !local.create ? null : concat(
    flatten([for i, key in local.log_keys : concat(
      length([for k, s in local.created_log_groups : k if local.log_key[k] == key]) == 0 ? [] : [
        {
          key        = key
          sid        = "ServiceLogGroups${i}"
          principals = { services = ["logs.${local.region}.amazonaws.com"], arns = [], roles = [] }
          actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
          conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = sort(distinct([for k, s in local.created_log_groups : local.log_group_arn[k] if local.log_key[k] == key])) }]
          purpose    = "CloudWatch Logs encrypts the log groups the module creates with this key. Without it, creating a log group fails part way through the apply."
        },
        {
          key        = key
          sid        = "LogGroupCreator${i}"
          principals = { services = [], arns = [], roles = ["deployer"] }
          actions    = ["kms:Describe*"]
          conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["logs.${local.region}.amazonaws.com"] }]
          purpose    = "CloudWatch Logs requires the principal calling CreateLogGroup with a key to be able to describe it; otherwise the create fails with AccessDeniedException."
        },
      ],
      [
        {
          key = key
          sid = "LogWriters${i}"
          principals = {
            services = []
            arns     = sort(distinct([for k, s in local.services : local.execution_role_arn[k] if local.log_key[k] == key]))
            roles    = anytrue([for k, s in local.services : s.launch == "EC2" if local.log_key[k] == key]) ? ["container_instances"] : []
          }
          actions    = local.log_writer_actions
          conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["logs.${local.region}.amazonaws.com"] }]
          purpose    = "The awslogs driver writes with the execution role on Fargate, and with the container instance role on EC2; writers to a log group under a customer key need it through CloudWatch Logs."
        },
        {
          key        = key
          sid        = "LogReaders${i}"
          principals = { services = [], arns = [], roles = ["log_readers"] }
          actions    = ["kms:Decrypt", "kms:Describe*"]
          conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["logs.${local.region}.amazonaws.com"] }]
          purpose    = "Whoever reads the logs (aws logs tail, Logs Insights) decrypts them through CloudWatch Logs."
        },
      ],
    )]),
    [for i, key in var.secrets_kms_key_arns : {
      key        = key
      sid        = "SecretsKey${i}"
      principals = { services = [], arns = sort(distinct([for k, refs in local.secret_refs : local.execution_role_arn[k] if length(refs) > 0])), roles = [] }
      actions    = ["kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["secretsmanager.${local.region}.amazonaws.com", "ssm.${local.region}.amazonaws.com"] }]
      purpose    = "Execution roles decrypt the secrets and SecureString parameters injected into containers. Without it, tasks stop with ResourceInitializationError before the application starts."
    }],
    length(local.exec_services) == 0 || var.execute_command.kms_key_arn == "" ? [] : [
      {
        key        = var.execute_command.kms_key_arn
        sid        = "EcsExecTasks"
        principals = { services = [], arns = sort([for k, s in local.exec_services : local.task_role_arn[k]]), roles = [] }
        actions    = ["kms:Decrypt"]
        conditions = []
        purpose    = "The SSM agent in the container decrypts ECS Exec session data with the task role."
      },
      {
        key        = var.execute_command.kms_key_arn
        sid        = "EcsExecOperators"
        principals = { services = [], arns = [], roles = ["exec_operators"] }
        actions    = ["kms:GenerateDataKey"]
        conditions = []
        purpose    = "Whoever starts an ECS Exec session encrypts it with this key. Without it, execute-command fails for that person."
      },
    ],
    length(local.exec_services) == 0 || var.execute_command.logging != "OVERRIDE" || var.execute_command.log_group_name == "" || var.execute_command.log_kms_key_arn == "" ? [] : [{
      key        = var.execute_command.log_kms_key_arn
      sid        = "EcsExecLogWriters"
      principals = { services = [], arns = sort([for k, s in local.exec_services : local.task_role_arn[k]]), roles = [] }
      actions    = local.log_writer_actions
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["logs.${local.region}.amazonaws.com"] }]
      purpose    = "The SSM agent in the container writes ECS Exec transcripts to the exec log group with the task role."
    }],
    length(local.exec_services) == 0 || var.execute_command.logging != "OVERRIDE" || var.execute_command.s3_bucket_name == "" || var.execute_command.s3_kms_key_arn == "" ? [] : [{
      key        = var.execute_command.s3_kms_key_arn
      sid        = "EcsExecBucketWriters"
      principals = { services = [], arns = sort([for k, s in local.exec_services : local.task_role_arn[k]]), roles = [] }
      actions    = ["kms:GenerateDataKey"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
      purpose    = "The SSM agent uploads ECS Exec transcripts to the SSE-KMS bucket with the task role."
    }],
    [for i, key in var.environment_files_kms_key_arns : {
      key        = key
      sid        = "EnvironmentFiles${i}"
      principals = { services = [], arns = sort(distinct([for k, files in local.environment_file_arns : local.execution_role_arn[k] if length(files) > 0])), roles = [] }
      actions    = ["kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["s3.${local.region}.amazonaws.com"] }]
      purpose    = "Execution roles read containers' environment files from the SSE-KMS bucket. Without it, those tasks stop before the application starts."
    }],
    [for i, key in local.dead_letter_keys : {
      key        = key
      sid        = "ScheduleDeadLetters${i}"
      principals = { services = [], arns = [local.scheduler_role_arn], roles = [] }
      actions    = ["kms:GenerateDataKey", "kms:Decrypt"]
      conditions = [{ test = "StringEquals", variable = "kms:ViaService", values = ["sqs.${local.region}.amazonaws.com"] }]
      purpose    = "EventBridge Scheduler sends failed invocations to the SSE-KMS dead-letter queue. Without it, they are lost."
    }],
    var.fargate_ephemeral_storage_kms_key_arn == "" ? [] : [
      {
        key        = var.fargate_ephemeral_storage_kms_key_arn
        sid        = "FargateEphemeralDataKeys"
        principals = { services = ["fargate.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:GenerateDataKeyWithoutPlaintext"]
        conditions = [
          { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterName", values = [var.name] },
        ]
        purpose = "Fargate generates the data key for each task's ephemeral storage in this cluster."
      },
      {
        key        = var.fargate_ephemeral_storage_kms_key_arn
        sid        = "FargateEphemeralGrants"
        principals = { services = ["fargate.amazonaws.com"], arns = [], roles = [] }
        actions    = ["kms:CreateGrant"]
        conditions = [
          { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:EncryptionContext:aws:ecs:clusterName", values = [var.name] },
          { test = "ForAllValues:StringEquals", variable = "kms:GrantOperations", values = ["Decrypt"] },
        ]
        purpose = "Fargate decrypts the ephemeral storage key through a grant. Without both Fargate entries, tasks in this cluster fail to start."
      },
      {
        key        = var.fargate_ephemeral_storage_kms_key_arn
        sid        = "FargateEphemeralDescribe"
        principals = { services = [], arns = [], roles = ["deployer"] }
        actions    = ["kms:DescribeKey"]
        conditions = []
        purpose    = "CreateCluster and UpdateCluster validate the key as the caller. Without it, the cluster create or update fails."
      },
    ],
    flatten([for i, key in local.ebs_keys : [
      {
        key        = key
        sid        = "ManagedEbsDescribe${i}"
        principals = { services = [], arns = [local.infrastructure_arn], roles = [] }
        actions    = ["kms:DescribeKey"]
        conditions = []
        purpose    = "ECS checks the key before creating a task's EBS volume."
      },
      {
        key        = key
        sid        = "ManagedEbsDataKeys${i}"
        principals = { services = [], arns = [local.infrastructure_arn], roles = [] }
        actions    = ["kms:GenerateDataKey*", "kms:ReEncryptTo", "kms:ReEncryptFrom"]
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["ec2.${local.region}.amazonaws.com"] },
          { test = "ForAnyValue:StringEquals", variable = "kms:EncryptionContextKeys", values = ["aws:ebs:id"] },
        ]
        purpose = "EBS encrypts the volumes ECS creates for tasks (ReEncrypt for volumes created from snapshots)."
      },
      {
        key        = key
        sid        = "ManagedEbsGrants${i}"
        principals = { services = [], arns = [local.infrastructure_arn], roles = [] }
        actions    = ["kms:CreateGrant"]
        conditions = [
          { test = "StringEquals", variable = "kms:CallerAccount", values = [local.account_id] },
          { test = "StringEquals", variable = "kms:ViaService", values = ["ec2.${local.region}.amazonaws.com"] },
          { test = "ForAnyValue:StringEquals", variable = "kms:EncryptionContextKeys", values = ["aws:ebs:id"] },
          { test = "Bool", variable = "kms:GrantIsForAWSResource", values = ["true"] },
        ]
        purpose = "EBS attaches the encrypted volume through a grant. Without the managed EBS entries, the task stops with a volume attachment failure."
      },
    ]]),
    var.sns_topic_kms_key_arn == "" || var.sns_topic_arn == "" ? [] : (!local.alarms_publish_to_topic && length(local.event_rules) == 0) ? [] : [{
      key = var.sns_topic_kms_key_arn
      sid = "SnsTopicPublishers"
      principals = {
        services = concat(local.alarms_publish_to_topic ? ["cloudwatch.amazonaws.com"] : [], length(local.event_rules) > 0 ? ["events.amazonaws.com"] : [])
        arns     = []
        roles    = []
      }
      actions    = ["kms:GenerateDataKey*", "kms:Decrypt"]
      conditions = []
      purpose    = "The topic is encrypted with this key; alarms and event rules publishing to it need it, or the notification is dropped."
    }],
  )
}

output "notification_requirements" {
  description = "What sns_topic_arn's access policy must allow, as policy statements. The module publishes alarms and EventBridge rules to the topic but does not own it; a topic that denies them drops every notification while the rules show as healthy."
  value = !local.create || var.sns_topic_arn == "" ? null : {
    topic = var.sns_topic_arn
    topic_policy_statements = concat(
      !local.alarms_publish_to_topic ? [] : [{
        Sid       = "EcsAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = var.sns_topic_arn
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:${var.name}-*" } }
      }],
      length(local.event_rules) == 0 ? [] : [{
        Sid       = "EcsEventRules"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = var.sns_topic_arn
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${var.name}-*" } }
      }],
    )
    test = "aws sns publish --topic-arn ${var.sns_topic_arn} --subject 'ecs ${var.name}: test' --message 'notification path test' - proves the subscriptions, not the publishers above"
  }
}

output "deployer_requirements" {
  description = "IAM the principal running Terraform needs besides managing the module's resources: iam:PassRole on the roles the module hands to ECS and EventBridge Scheduler, iam:GetInstanceProfile to read supplied Managed Instances profiles at plan, and the ECS and (with autoscaling) Application Auto Scaling service-linked roles, which AWS creates on first use. Attach iam_policy to the HCP Terraform plan and apply roles."
  value = !local.create ? null : {
    iam_policy = jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid       = "PassTaskRoles"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = sort(distinct(concat(values(local.task_role_arn), values(local.execution_role_arn))))
          Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
        }],
        !local.infrastructure_used ? [] : [{
          Sid       = "PassInfrastructureRole"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = local.infrastructure_arn
          Condition = { StringEquals = { "iam:PassedToService" = "ecs.amazonaws.com" } }
        }],
        length(local.managed_instances) == 0 ? [] : [{
          Sid      = "PassManagedInstanceRoles"
          Effect   = "Allow"
          Action   = "iam:PassRole"
          Resource = concat(local.create_instance_profile ? [local.instance_role_arn] : [], [for k, d in data.aws_iam_instance_profile.managed_instances : d.role_arn])
        }],
        length(local.supplied_instance_profile) == 0 ? [] : [{
          Sid      = "ReadSuppliedInstanceProfiles"
          Effect   = "Allow"
          Action   = "iam:GetInstanceProfile"
          Resource = [for k, p in local.supplied_instance_profile : local.managed_instances[k].instance_profile_arn]
        }],
        length(local.scheduled) == 0 ? [] : [{
          Sid       = "PassSchedulerRole"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = local.scheduler_role_arn
          Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } }
        }],
        length(local.autoscaled) == 0 ? [] : [{
          Sid       = "ApplicationAutoScalingServiceLinkedRole"
          Effect    = "Allow"
          Action    = "iam:CreateServiceLinkedRole"
          Resource  = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
          Condition = { StringEquals = { "iam:AWSServiceName" = "ecs.application-autoscaling.amazonaws.com" } }
        }],
        [{
          Sid       = "EcsServiceLinkedRole"
          Effect    = "Allow"
          Action    = "iam:CreateServiceLinkedRole"
          Resource  = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS"
          Condition = { StringEquals = { "iam:AWSServiceName" = "ecs.amazonaws.com" } }
        }],
      )
    })
  }
}

output "run_task_commands" {
  description = "A ready aws ecs run-task command for each task and scheduled workload, with its capacity strategy and network filled in: what a pipeline step runs for a migration or a one-off job. It names the family, which ECS resolves to the latest ACTIVE revision, so the command does not change between deployments. Add --overrides to change the command."
  value = !local.create ? {} : { for k, s in local.services : k => join(" ", compact([
    "aws ecs run-task --cluster ${var.name}",
    "--task-definition ${var.name}-${k}",
    "--capacity-provider-strategy ${join(" ", [for p in local.strategy[k] : "capacityProvider=${p.capacity_provider},weight=${p.weight},base=${p.base}"])}",
    s.network_mode == "awsvpc" ? "--network-configuration 'awsvpcConfiguration={subnets=[${join(",", local.subnets[k])}],securityGroups=[${join(",", local.security_groups[k])}],assignPublicIp=${s.assign_public_ip ? "ENABLED" : "DISABLED"}}'" : "",
    "--enable-ecs-managed-tags --propagate-tags TASK_DEFINITION",
    s.enable_execute_command ? "--enable-execute-command" : "",
    "--query 'tasks[0].taskArn' --output text",
  ])) if contains(["task", "scheduled"], s.workload) }
}

output "run_task_requirements" {
  description = "IAM the pipeline that runs run_task_commands needs, as a policy to attach to its role: RunTask on exactly the task and scheduled families, on this cluster only; PassRole on their roles, to ECS tasks only; and tagging the tasks it starts. Null when there are no such workloads."
  value = !local.create || length(local.one_off_families) == 0 ? null : {
    iam_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "RunWorkloadTasks"
          Effect    = "Allow"
          Action    = ["ecs:RunTask"]
          Resource  = [for k, s in local.services : "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task-definition/${var.name}-${k}:*" if contains(["scheduled", "task"], s.workload)]
          Condition = { ArnEquals = { "ecs:cluster" = local.cluster_arn } }
        },
        {
          Sid       = "PassWorkloadRoles"
          Effect    = "Allow"
          Action    = ["iam:PassRole"]
          Resource  = sort(distinct(flatten([for k, s in local.services : [local.task_role_arn[k], local.execution_role_arn[k]] if contains(["scheduled", "task"], s.workload)])))
          Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
        },
        {
          Sid       = "TagStartedTasks"
          Effect    = "Allow"
          Action    = ["ecs:TagResource"]
          Resource  = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${var.name}/*"
          Condition = { StringEquals = { "ecs:CreateAction" = ["RunTask"] } }
        },
        {
          Sid      = "WatchStartedTasks"
          Effect   = "Allow"
          Action   = ["ecs:DescribeTasks"]
          Resource = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${var.name}/*"
        },
      ]
    })
  }
}

output "verify_commands" {
  description = "Copy-paste checks for CloudShell after an apply, in the order you will need them. Maps are keyed by workload."
  value = !local.create ? null : {
    services          = length(local.long_running) == 0 ? "" : "aws ecs describe-services --cluster ${var.name} --services ${join(" ", sort(keys(local.long_running)))} --query 'services[].[serviceName,status,runningCount,desiredCount,deployments[0].rolloutState,deployments[0].rolloutStateReason]' --output table"
    events            = { for k, s in local.long_running : k => "aws ecs describe-services --cluster ${var.name} --services ${k} --query 'services[0].events[:10].[createdAt,message]' --output table" }
    stopped_tasks     = { for k, s in local.services : k => "aws ecs describe-tasks --cluster ${var.name} --tasks $(aws ecs list-tasks --cluster ${var.name} --family ${var.name}-${k} --desired-status STOPPED --query 'taskArns[:20]' --output text) --query 'tasks[].[stoppedAt,stopCode,stoppedReason,containers[0].exitCode]' --output table" }
    logs              = { for k, s in local.services : k => "aws logs tail ${local.log_group_name[k]} --since 1h --follow" }
    shell             = { for k, s in local.exec_services : k => "aws ecs execute-command --cluster ${var.name} --task $(aws ecs list-tasks --cluster ${var.name} --family ${var.name}-${k} --query 'taskArns[0]' --output text) --container ${contains(keys(local.containers[k]), k) ? k : [for n, c in local.containers[k] : n if c.essential][0]} --interactive --command /bin/sh" }
    roll_back         = { for k, s in local.long_running : k => "aws ecs list-task-definitions --family-prefix ${var.name}-${k} --sort DESC --max-items 5 --output table && echo 'then: aws ecs update-service --cluster ${var.name} --service ${k} --task-definition ${var.name}-${k}:<revision>${s.deployment.ignore_task_definition_changes ? " - Terraform leaves it there; the next pipeline deploy moves it on" : " - and set the same image in Terraform, or the next apply rolls it forward again"}'" }
    deploy_latest     = { for k in local.externally_deployed : k => "aws ecs update-service --cluster ${var.name} --service ${k} --task-definition ${var.name}-${k} --query 'service.deployments[0].[taskDefinition,rolloutState]' --output text" }
    schedules         = { for k, s in local.scheduled : k => "aws scheduler get-schedule --group-name ${var.name} --name ${k} --query '[State,ScheduleExpression,ScheduleExpressionTimezone,Target.RetryPolicy]' --output table" }
    capacity          = "aws ecs describe-clusters --clusters ${var.name} --include STATISTICS --query 'clusters[0].[capacityProviders,defaultCapacityProviderStrategy,runningTasksCount,pendingTasksCount]' --output json"
    exec_ready        = { for k, s in local.exec_services : k => "aws ecs describe-tasks --cluster ${var.name} --tasks $(aws ecs list-tasks --cluster ${var.name} --family ${var.name}-${k} --query 'taskArns[0]' --output text) --query 'tasks[0].containers[].managedAgents[].[name,lastStatus]' --output table" }
    deployments       = { for k, s in local.replica : k => "aws ecs list-service-deployments --cluster ${var.name} --service ${k} --query 'serviceDeployments[:5].[serviceDeploymentArn,status,targetServiceRevisionArn]' --output table" }
    stop_deployment   = { for k, s in local.replica : k => "aws ecs stop-service-deployment --stop-type ROLLBACK --service-deployment-arn $(aws ecs list-service-deployments --cluster ${var.name} --service ${k} --status IN_PROGRESS --query 'serviceDeployments[0].serviceDeploymentArn' --output text)" if s.deployment.strategy != "ROLLING" }
    managed_instances = length(local.managed_instances) == 0 ? "" : "aws ecs describe-capacity-providers --capacity-providers ${join(" ", [for k, p in local.managed_instances : local.mi_provider_name[k]])} --query 'capacityProviders[].[name,status,updateStatus,updateStatusReason]' --output table"
  }
}
