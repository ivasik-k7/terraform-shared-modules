# Hooks with initial = true are on the group itself (main.tf), so they also
# hold the instances launched when the group is created; the provider replaces
# the group when they change (internal/service/autoscaling/group.go,
# initial_lifecycle_hook is ForceNew). These are updated in place.
resource "aws_autoscaling_lifecycle_hook" "this" {
  for_each = local.separate_hooks

  name                    = each.key
  autoscaling_group_name  = local.group_name
  lifecycle_transition    = local.hook_transition[each.value.transition]
  default_result          = each.value.default_result
  heartbeat_timeout       = each.value.heartbeat_timeout
  notification_target_arn = each.value.notification_target_arn != "" ? each.value.notification_target_arn : null
  role_arn                = each.value.role_arn != "" ? each.value.role_arn : null
  notification_metadata   = each.value.notification_metadata != "" ? each.value.notification_metadata : null
}
