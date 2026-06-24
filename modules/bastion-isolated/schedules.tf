# the actual auto-shutdown. cron -> scale to 0 after hours, back up in the
# morning. this is where the bastion line item on the bill basically disappears.

resource "aws_autoscaling_schedule" "this" {
  for_each = local.create ? local.scheduled_actions : {}

  scheduled_action_name  = each.key
  autoscaling_group_name = aws_autoscaling_group.this[0].name

  recurrence       = each.value.recurrence
  start_time       = each.value.start_time
  end_time         = each.value.end_time
  time_zone        = each.value.time_zone
  min_size         = each.value.min_size
  max_size         = each.value.max_size
  desired_capacity = each.value.desired_capacity
}
