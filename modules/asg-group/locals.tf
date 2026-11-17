locals {
  create = var.create

  # Module keys last, so a caller's tags cannot override them.
  module_tags   = { ManagedBy = "Terraform", Module = "asg-group" }
  common_tags   = merge(var.tags, local.module_tags)
  instance_tags = merge(var.tags, var.instance_tags, local.module_tags, { Name = var.name })
  group_tags    = merge(var.tags, var.autoscaling_group_tags, local.module_tags, { Name = var.name })

  # Placeholders so ARN strings still build when create = false.
  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = coalesce(one(data.aws_region.current[*].region), "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  acknowledged = toset(var.acknowledged_checks)

  ami       = var.ami != "" ? var.ami : (length(data.aws_ssm_parameter.ami) > 0 ? data.aws_ssm_parameter.ami[0].insecure_value : "")
  user_data = var.user_data != "" ? base64encode(var.user_data) : (var.user_data_base64 != "" ? var.user_data_base64 : null)

  # ---------------------------------------------------------------------------
  # Instance mix
  # ---------------------------------------------------------------------------

  attribute_based = var.instance_requirements.vcpu_min > 0
  instance_types  = local.attribute_based ? [] : (length(var.instance_types) > 0 ? var.instance_types : [var.instance_type])
  uses_spot       = var.purchase_options.on_demand_percentage_above_base_capacity < 100
  mixed = anytrue([
    local.attribute_based, local.uses_spot, length(local.instance_types) > 1,
    length(var.instance_weights) > 0, var.purchase_options.on_demand_allocation_strategy != "",
  ])

  # Credit specification is valid only for burstable types.
  burstable          = local.attribute_based ? false : alltrue([for t in local.instance_types : can(regex("^t[0-9]+[a-z]*\\.", t))])
  capacity_rebalance = local.uses_spot ? true : var.capacity_rebalance
  desired_capacity   = var.desired_capacity == -1 ? var.min_size : var.desired_capacity

  # ---------------------------------------------------------------------------
  # Roles
  # ---------------------------------------------------------------------------

  create_role    = local.create ? var.instance_profile.create : false
  ssm_policy_arn = "arn:${local.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
  # Keyed, never decided by an ARN value that may be unknown at plan. A
  # caller's own "ssm" key replaces the module's.
  managed_policies = merge(var.instance_profile.ssm ? { ssm = local.ssm_policy_arn } : {}, var.instance_profile.managed_policies)

  instance_profile_name = local.create_role ? one(aws_iam_instance_profile.this[*].name) : var.instance_profile.name

  service_linked_role_arn = var.service_linked_role_arn != "" ? var.service_linked_role_arn : "arn:${local.partition}:iam::${local.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"

  # ---------------------------------------------------------------------------
  # Hooks
  # ---------------------------------------------------------------------------

  hook_transition = { LAUNCHING = "autoscaling:EC2_INSTANCE_LAUNCHING", TERMINATING = "autoscaling:EC2_INSTANCE_TERMINATING" }
  initial_hooks   = { for n, h in var.lifecycle_hooks : n => h if h.initial }
  predictive_metric_pair = {
    cpu          = "ASGCPUUtilization"
    network_in   = "ASGNetworkIn"
    network_out  = "ASGNetworkOut"
    alb_requests = "ALBRequestCount"
  }
  separate_hooks = local.create ? { for n, h in var.lifecycle_hooks : n => h if !h.initial } : {}

  # ---------------------------------------------------------------------------
  # The group, whichever of the two resources holds it
  # ---------------------------------------------------------------------------

  group_name = one(concat(aws_autoscaling_group.this[*].name, aws_autoscaling_group.static[*].name))
  group_arn  = one(concat(aws_autoscaling_group.this[*].arn, aws_autoscaling_group.static[*].arn))

  # ---------------------------------------------------------------------------
  # Signals
  # ---------------------------------------------------------------------------

  # The lowest count the group may run: min_size, or a scheduled action's lower one.
  capacity_floor       = min(concat([var.min_size], [for a in values(var.scheduled_actions) : a.min_size if a.min_size >= 0])...)
  in_service_threshold = var.alarm_min_in_service == -1 ? local.capacity_floor : var.alarm_min_in_service
  in_service_alarm = alltrue([
    local.create, var.create_alarms, contains(var.enabled_metrics, "GroupInServiceInstances"), local.in_service_threshold > 0,
  ])
  cpu_alarm = local.create ? var.create_alarms : false

  alarm_actions           = length(var.alarm_actions) > 0 ? var.alarm_actions : (var.sns_topic_arn == "" ? [] : [var.sns_topic_arn])
  ok_actions              = length(var.ok_actions) > 0 ? var.ok_actions : local.alarm_actions
  alarms_publish_to_topic = var.sns_topic_arn == "" ? false : (local.cpu_alarm || local.in_service_alarm ? contains(concat(local.alarm_actions, local.ok_actions), var.sns_topic_arn) : false)

  event_rules_enabled = local.create ? (var.create_event_rules ? var.sns_topic_arn != "" : false) : false
  event_rules = !local.event_rules_enabled ? {} : {
    launch-failed = {
      description = "Instances of ${var.name} that Auto Scaling could not launch: capacity, quota, KMS or subnet problems."
      detail_type = ["EC2 Instance Launch Unsuccessful"]
    }
    terminate-failed = {
      description = "Instances of ${var.name} that Auto Scaling could not terminate."
      detail_type = ["EC2 Instance Terminate Unsuccessful"]
    }
    refresh-failed = {
      description = "Instance refreshes of ${var.name} that failed, were cancelled or rolled back."
      detail_type = [
        "EC2 Auto Scaling Instance Refresh Failed", "EC2 Auto Scaling Instance Refresh Cancelled",
        "EC2 Auto Scaling Instance Refresh Rollback Started", "EC2 Auto Scaling Instance Refresh Rollback Failed",
      ]
    }
  }

  # ---------------------------------------------------------------------------
  # Posture
  # ---------------------------------------------------------------------------

  subnet_count            = length(distinct(var.subnet_ids))
  spot_without_floor      = local.uses_spot ? (var.purchase_options.on_demand_base_capacity == 0 ? var.purchase_options.on_demand_percentage_above_base_capacity == 0 : false) : false
  unbounded_credits       = local.burstable ? var.cpu_credits == "unlimited" : false
  refresh_enabled         = var.instance_refresh.enabled
  missing_required_tags   = [for t in var.required_tag_keys : t if trimspace(lookup(var.tags, t, "")) == ""]
  ami_moves_on_its_own    = var.ami_ssm_parameter != ""
  imds_reachable_by_tasks = var.metadata_hop_limit > 1
}
