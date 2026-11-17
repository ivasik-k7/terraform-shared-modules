# ---------------------------------------------------------------------------
# Resources: what callers wire to their other resources.
# ---------------------------------------------------------------------------

output "autoscaling_group_arn" {
  description = "Auto Scaling group ARN: the auto_scaling_group_arn of an ECS capacity provider (modules/ecs ec2_capacity_providers), or any other consumer."
  value       = local.group_arn
}

output "autoscaling_group_name" {
  description = "Auto Scaling group name (<name>-<suffix>), the AutoScalingGroupName dimension of its metrics."
  value       = local.group_name
}

output "autoscaling_group_id" {
  description = "Auto Scaling group ID, which is its name."
  value       = local.group_name
}

output "launch_template_id" {
  description = "Launch template ID."
  value       = one(aws_launch_template.this[*].id)
}

output "launch_template_arn" {
  description = "Launch template ARN."
  value       = one(aws_launch_template.this[*].arn)
}

output "launch_template_latest_version" {
  description = "Launch template version the group launches."
  value       = one(aws_launch_template.this[*].latest_version)
}

output "iam_role_arn" {
  description = "ARN of the instance role the module created; null when instance_profile.create = false."
  value       = one(aws_iam_role.this[*].arn)
}

output "iam_role_name" {
  description = "Name of the instance role the module created, for attaching further policies from the calling root; null when not created."
  value       = one(aws_iam_role.this[*].name)
}

output "instance_profile_name" {
  description = "Instance profile the instances launch with, created or supplied."
  value       = local.create ? (local.instance_profile_name != "" ? local.instance_profile_name : null) : null
}

output "instance_profile_arn" {
  description = "ARN of the instance profile the module created; null when not created."
  value       = one(aws_iam_instance_profile.this[*].arn)
}

output "target_tracking_policy_arns" {
  description = "Target tracking policy ARN by policy key."
  value       = { for k, p in aws_autoscaling_policy.target_tracking : k => p.arn }
}

output "predictive_scaling_policy_arn" {
  description = "Predictive scaling policy ARN; null when predictive scaling is off."
  value       = one(aws_autoscaling_policy.predictive[*].arn)
}

output "cloudwatch_alarm_names" {
  description = "Names of the alarms the module created."
  value       = concat(aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name, aws_cloudwatch_metric_alarm.in_service_low[*].alarm_name)
}

# ---------------------------------------------------------------------------
# Contracts: facts another team acts on, as data rather than prose.
# ---------------------------------------------------------------------------

output "governance" {
  description = "The fleet's posture as data: assert on it in tests, diff it in a change review."
  value = !local.create ? null : {
    instance_count_owner    = var.ignore_desired_capacity_changes ? "scaling, scheduled actions or a capacity provider" : "terraform"
    instance_selection      = local.attribute_based ? "attribute-based" : (local.mixed ? "mixed: ${join(", ", local.instance_types)}" : local.instance_types[0])
    spot                    = local.uses_spot ? "${var.purchase_options.on_demand_base_capacity} on-demand base, then ${var.purchase_options.on_demand_percentage_above_base_capacity}% on-demand" : "none"
    availability_zones      = local.subnet_count
    capacity_floor          = local.capacity_floor
    ami_source              = var.ami != "" ? "pinned ${var.ami}" : "resolved at plan from ${var.ami_ssm_parameter}"
    instance_refresh        = local.refresh_enabled ? "on${var.instance_refresh.auto_rollback ? ", auto rollback" : ""}${var.instance_refresh.skip_matching ? ", skip matching" : ""}" : "off"
    volumes_customer_key    = var.kms_key_arn != ""
    ssh_key                 = var.key_name != ""
    public_ip               = var.public_ip == "" ? "subnet default" : var.public_ip
    imds_hop_limit          = var.metadata_hop_limit
    session_manager         = local.create_role ? var.instance_profile.ssm : null
    cpu_credits             = local.burstable ? var.cpu_credits : "not burstable"
    initial_lifecycle_hooks = sort(keys(local.initial_hooks))
    terminate_hook_abandon  = var.terminate_hook_abandon == "" ? "terminate" : var.terminate_hook_abandon
    alarms                  = sort(concat(aws_cloudwatch_metric_alarm.cpu_high[*].alarm_name, aws_cloudwatch_metric_alarm.in_service_low[*].alarm_name))
    event_rules             = sort(keys(local.event_rules))
    notifications           = var.sns_topic_arn != ""
    required_tag_keys       = sort(var.required_tag_keys)
    acknowledged_checks     = sort(var.acknowledged_checks)
  }
}

output "kms_key_policy_requirements" {
  description = "What each customer managed key's policy has to allow, in contract version 2: key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. Known at plan, so the key owner can act before the apply. The symbolic role deployer is whoever runs Terraform."
  value = !local.create ? null : concat(
    var.kms_key_arn == "" ? [] : [
      {
        key        = var.kms_key_arn
        sid        = "AutoScalingVolumes"
        principals = { services = [], arns = [local.service_linked_role_arn], roles = [] }
        actions    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        conditions = []
        purpose    = "Auto Scaling launches instances with its service-linked role, which has no access to customer managed keys. Without it every launch fails with Client.InternalError while the apply stays green."
      },
      {
        key        = var.kms_key_arn
        sid        = "AutoScalingVolumeGrants"
        principals = { services = [], arns = [local.service_linked_role_arn], roles = [] }
        actions    = ["kms:CreateGrant"]
        conditions = [{ test = "Bool", variable = "kms:GrantIsForAWSResource", values = ["true"] }]
        purpose    = "EC2 attaches the encrypted volumes through a grant the service-linked role creates."
      },
    ],
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
        Sid       = "AutoScalingGroupAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = var.sns_topic_arn
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${local.region}:${local.account_id}:alarm:${var.name}-*" } }
      }],
      length(local.event_rules) == 0 ? [] : [{
        Sid       = "AutoScalingGroupEventRules"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = var.sns_topic_arn
        Condition = { ArnLike = { "aws:SourceArn" = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/${var.name}-*" } }
      }],
    )
    test = "aws sns publish --topic-arn ${var.sns_topic_arn} --subject 'asg ${var.name}: test' --message 'notification path test' - proves the subscriptions, not the publishers above"
  }
}

output "deployer_requirements" {
  description = "IAM the principal running Terraform needs besides managing the module's resources: creating or updating a group with a launch template is authorized as ec2:RunInstances, tagging the instances and volumes as ec2:CreateTags, and handing the instance profile's role to EC2 as iam:PassRole; plus the Auto Scaling service-linked role, which AWS creates on first use. Known at plan, so the apply role can be granted it before the first apply: PassRole names the role by its <name>- prefix, because IAM adds the suffix only at creation."
  value = !local.create ? null : {
    iam_policy = jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        [{
          Sid      = "LaunchFromTheTemplate"
          Effect   = "Allow"
          Action   = ["ec2:RunInstances", "ec2:CreateTags"]
          Resource = "*"
        }],
        local.create_role ? [{
          Sid       = "PassInstanceRole"
          Effect    = "Allow"
          Action    = "iam:PassRole"
          Resource  = "arn:${local.partition}:iam::${local.account_id}:role/${var.name}-*"
          Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
        }] : [],
        [{
          Sid       = "AutoScalingServiceLinkedRole"
          Effect    = "Allow"
          Action    = "iam:CreateServiceLinkedRole"
          Resource  = "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling*"
          Condition = { StringEquals = { "iam:AWSServiceName" = "autoscaling.amazonaws.com" } }
        }],
      )
    })
    passes_a_supplied_profile = local.create_role ? null : "instance_profile.create = false: grant iam:PassRole on the role inside ${var.instance_profile.name}, with iam:PassedToService ec2.amazonaws.com"
  }
}

output "network_contract" {
  description = "What the instances need from YOUR network to be managed without SSH or a bastion, as data. The module creates no network resources."
  value = !local.create ? null : {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
    session_manager_interface_endpoints = local.create_role && var.instance_profile.ssm ? [
      "com.amazonaws.${local.region}.ssm",
      "com.amazonaws.${local.region}.ssmmessages",
      "com.amazonaws.${local.region}.ec2messages",
    ] : []
    gateway_endpoints = ["com.amazonaws.${local.region}.s3"]
    required_egress   = ["443 to the interface endpoints and the S3 gateway prefix list"]
    notes = [
      "Session Manager needs ssm and ssmmessages; ec2messages only for SSM Agent older than 3.3.40.0. Add kms and logs endpoints if sessions are encrypted or logged (https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html).",
      "SSM Agent updates itself from S3: without the gateway endpoint, or another S3 path, it stays on the version baked into the AMI.",
      "Interface endpoints need private DNS, and their security groups must allow 443 from the instances' security groups.",
      "The ECS agent, CloudWatch agent and the workload need their own endpoints (for ECS: ecs, ecs-agent, ecs-telemetry, ecr.api, ecr.dkr, logs).",
    ]
  }
}

output "verify_commands" {
  description = "Copy-paste checks for CloudShell after an apply, in the order you will need them."
  value = !local.create ? null : {
    group              = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${coalesce(local.group_name, "<group>")} --query 'AutoScalingGroups[0].[MinSize,DesiredCapacity,MaxSize,length(Instances),Status]' --output table"
    instances          = "aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${coalesce(local.group_name, "<group>")} --query 'AutoScalingGroups[0].Instances[].[InstanceId,AvailabilityZone,InstanceType,LifecycleState,HealthStatus,LaunchTemplate.Version]' --output table"
    failed_launches    = "aws autoscaling describe-scaling-activities --auto-scaling-group-name ${coalesce(local.group_name, "<group>")} --max-items 10 --query 'Activities[?StatusCode!=`Successful`].[StartTime,StatusCode,StatusMessage]' --output table"
    instance_refresh   = "aws autoscaling describe-instance-refreshes --auto-scaling-group-name ${coalesce(local.group_name, "<group>")} --max-records 3 --query 'InstanceRefreshes[].[StartTime,Status,PercentageComplete,StatusReason]' --output table"
    start_refresh      = "aws autoscaling start-instance-refresh --auto-scaling-group-name ${coalesce(local.group_name, "<group>")} --preferences '{\"SkipMatching\":${var.instance_refresh.skip_matching},\"AutoRollback\":${var.instance_refresh.auto_rollback},\"MinHealthyPercentage\":${var.instance_refresh.min_healthy_percentage}}'"
    shell              = "aws ssm start-session --target $(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names ${coalesce(local.group_name, "<group>")} --query 'AutoScalingGroups[0].Instances[?LifecycleState==`InService`]|[0].InstanceId' --output text)"
    warm_pool          = var.warm_pool.enabled ? "aws autoscaling describe-warm-pool --auto-scaling-group-name ${coalesce(local.group_name, "<group>")} --query 'Instances[].[InstanceId,LifecycleState]' --output table" : ""
    terminate_retained = var.terminate_hook_abandon == "retain" ? "aws autoscaling terminate-instance-in-auto-scaling-group --instance-id <retained-instance-id> --no-should-decrement-desired-capacity, then complete its TERMINATING lifecycle action with CONTINUE" : ""
    forecast           = var.predictive_scaling.enabled ? "aws autoscaling get-predictive-scaling-forecast --auto-scaling-group-name ${coalesce(local.group_name, "<group>")} --policy-name ${var.name}-predictive --start-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --end-time $(date -u -d '+2 days' +%Y-%m-%dT%H:%M:%SZ)" : ""
  }
}
