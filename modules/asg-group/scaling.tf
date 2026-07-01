# target-tracking scaling + scheduled capacity changes. dynamic scaling adjusts
# to load; scheduled changes the floor/ceiling on a clock (e.g. business hours).

resource "aws_autoscaling_policy" "target_tracking" {
  for_each = local.create ? var.target_tracking_policies : {}

  name                      = "${var.name}-${each.key}"
  autoscaling_group_name    = aws_autoscaling_group.this[0].name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = each.value.estimated_instance_warmup

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = each.value.predefined_metric_type
      resource_label         = each.value.resource_label
    }
    target_value     = each.value.target_value
    disable_scale_in = each.value.disable_scale_in
  }
}

resource "aws_autoscaling_schedule" "this" {
  for_each = local.create ? var.scheduled_actions : {}

  scheduled_action_name  = each.key
  autoscaling_group_name = aws_autoscaling_group.this[0].name

  # -1 tells AWS to leave that bound unchanged
  min_size         = coalesce(each.value.min_size, -1)
  max_size         = coalesce(each.value.max_size, -1)
  desired_capacity = coalesce(each.value.desired_capacity, -1)

  recurrence = each.value.recurrence
  start_time = each.value.start_time
  end_time   = each.value.end_time
  time_zone  = each.value.time_zone
}
