# One group per pool, shaped as fleeting-plugin-aws requires: zero minimum and
# desired, no scaling policy, AZRebalance suspended, scale-in protection on.
# https://gitlab.com/gitlab-org/fleet-plugins/aws/-/blob/v1.3.2/README.md
module "fleet" {
  source   = "../asg-group"
  for_each = local.active_pools

  name              = each.value.fleet_name
  required_tag_keys = var.required_tag_keys
  # The manager's scaling rights and job roles' trust select by this tag; it
  # reaches the group, the instances and the instance role.
  tags = merge(local.tags, each.value.tags, { (local.pool_tag_key) = each.value.fleet_name })
  acknowledged_checks = distinct(concat(
    local.fleet_acknowledged,
    each.value.jobs_use_aws ? ["containers_cannot_reach_instance_credentials"] : [],
  ))

  subnet_ids         = var.subnet_ids
  security_group_ids = concat([local.security_group_ids.instance], var.instance_security_group_ids)
  public_ip          = "none"

  ami            = var.ami_id
  instance_type  = each.value.instance_types[0]
  instance_types = each.value.instance_types
  key_name       = one(aws_key_pair.managers[*].key_name)
  user_data      = local.user_data
  # 2 lets job containers on the bridge network reach the instance role.
  metadata_hop_limit = each.value.jobs_use_aws ? 2 : 1
  root_volume        = { size_gib = each.value.root_volume_gib }
  kms_key_arn        = var.kms_key_arn

  instance_profile = {
    ssm              = true
    policies         = local.instance_role_policies[each.key]
    managed_policies = each.value.jobs_use_aws ? each.value.aws_access.managed_policies : {}
  }
  permissions_boundary_arn = var.permissions_boundary_arn

  min_size                        = 0
  max_size                        = each.value.max_instances
  desired_capacity                = 0
  ignore_desired_capacity_changes = true
  protect_from_scale_in           = true
  suspended_processes             = ["AZRebalance"]
  instance_refresh                = { enabled = false }
  purchase_options = {
    on_demand_base_capacity                  = each.value.on_demand_base
    on_demand_percentage_above_base_capacity = each.value.spot ? 0 : 100
  }
  enabled_metrics = ["GroupDesiredCapacity", "GroupInServiceInstances", "GroupPendingInstances", "GroupTerminatingInstances", "GroupTotalInstances"]

  sns_topic_arn      = var.sns_topic_arn
  create_event_rules = var.sns_topic_arn != ""
  # Build load keeps CPU high by design, and a zero floor leaves nothing for an in-service alarm to watch.
  create_alarms = false
}
