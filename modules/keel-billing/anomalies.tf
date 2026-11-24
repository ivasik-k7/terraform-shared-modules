# AWS managed monitors by service and by account; the provider takes no key
# with a dimension, so TAG and COST_CATEGORY managed monitors cannot be
# declared. A cost category value is a customer managed monitor, one value
# each, 500 per management account.
# https://docs.aws.amazon.com/cost-management/latest/userguide/management-limits.html
resource "aws_ce_anomaly_monitor" "this" {
  for_each = local.active_monitors

  name                  = "${var.name}-${each.key}"
  monitor_type          = each.value.type
  monitor_dimension     = each.value.dimension
  monitor_specification = each.value.specification
  tags                  = local.tags

  depends_on = [aws_ce_cost_category.this, aws_ce_cost_allocation_tag.this]
}

locals {
  subscriptions = merge(
    !local.alert ? {} : { alert = merge(var.anomaly_detection.alert, { frequency = "IMMEDIATE" }) },
    { for k, d in local.active_digests : "digest-${k}" => merge(d, { enabled = true }) },
  )
}

# One immediate alert, so each anomaly emits one Anomaly Detected event;
# immediate alerts require an SNS subscriber.
# https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html
resource "aws_ce_anomaly_subscription" "this" {
  for_each = local.subscriptions

  name             = "${var.name}-${each.key}"
  frequency        = each.value.frequency
  monitor_arn_list = [for m in aws_ce_anomaly_monitor.this : m.arn]
  tags             = local.tags

  dynamic "subscriber" {
    for_each = each.value.frequency == "IMMEDIATE" ? [aws_sns_topic.anomaly_alerts[0].arn] : []
    content {
      type    = "SNS"
      address = subscriber.value
    }
  }

  dynamic "subscriber" {
    for_each = each.value.frequency == "IMMEDIATE" ? [] : each.value.emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dynamic "and" {
      for_each = each.value.min_impact_percentage > 0 ? [1] : []
      content {
        dimension {
          key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
          match_options = ["GREATER_THAN_OR_EQUAL"]
          values        = [tostring(each.value.min_impact_absolute)]
        }
      }
    }
    dynamic "and" {
      for_each = each.value.min_impact_percentage > 0 ? [1] : []
      content {
        dimension {
          key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
          match_options = ["GREATER_THAN_OR_EQUAL"]
          values        = [tostring(each.value.min_impact_percentage)]
        }
      }
    }
    dynamic "dimension" {
      for_each = each.value.min_impact_percentage > 0 ? [] : [1]
      content {
        key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
        match_options = ["GREATER_THAN_OR_EQUAL"]
        values        = [tostring(each.value.min_impact_absolute)]
      }
    }
  }

  depends_on = [aws_sns_topic_policy.anomaly_alerts]
}
