# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and HCP Terraform health assessment.
# Each is silent under create = false and once named in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  tag_keys_in_categories = distinct(flatten([for k, c in var.cost_categories : concat(
    [for r in c.rules : r.tag_key if r.tag_key != ""],
    c.inherit_from_tag != "" ? [c.inherit_from_tag] : [],
  )]))
  inactive_category_tags = sort([for t in local.tag_keys_in_categories : t if !contains(var.cost_allocation_tags, t)])
}

check "somebody_hears_an_anomaly" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "somebody_hears_an_anomaly") ? true : (length(local.active_monitors) == 0 ? true : (local.alert ? (length(var.anomaly_detection.alert.emails) > 0 ? true : var.signals.control_plane_bus_arn != "") : length(local.active_digests) > 0)))
    error_message = "Anomalies reach nobody: the immediate alert is off and there are no digests, or the alert has neither emails nor a control plane to route it. Anomalies are detected and shown in the console, and nobody is told. ${local.ack_hint}"
  }
}

check "every_cost_category_is_watched" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "every_cost_category_is_watched") ? true : length(local.unwatched_categories) == 0)
    error_message = "Cost categories with no anomaly monitor: ${join(", ", local.unwatched_categories)}. A spike in one of their values is seen only as part of the account or service it lands in. List them in anomaly_detection.cost_categories. ${local.ack_hint}"
  }
}

check "spend_is_allocated_by_tags" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "spend_is_allocated_by_tags") ? true : length(local.inactive_category_tags) == 0)
    error_message = "Cost categories use tag keys that are not in cost_allocation_tags: ${join(", ", local.inactive_category_tags)}. A tag that is not an active cost allocation tag matches nothing in billing, so those rules allocate no spend. Activate them here, or acknowledge if another workspace activates them. ${local.ack_hint}"
  }
}

check "anomaly_events_reach_the_control_plane" {
  assert {
    condition     = !local.forward_anomalies ? true : (contains(local.acknowledged, "anomaly_events_reach_the_control_plane") ? true : local.region == "us-east-1")
    error_message = "The anomaly forwarding rule is in ${local.region}. Cost Anomaly Detection publishes its events in its home Region, which this module expects to be us-east-1 (docs/RESEARCH.md); a rule elsewhere may never match. Run this module with a us-east-1 provider. ${local.ack_hint}"
  }
}

check "commitments_are_watched" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "commitments_are_watched") ? true : length(local.commitment_limits) > 0)
    error_message = "No commitment target: Savings Plans or Reserved Instances bought and left idle, or coverage falling as usage grows, show only in the bill. Set commitments.savings_plans_utilization (and coverage) once the organization holds commitments. ${local.ack_hint}"
  }
}

# The agent stores its data in us-east-1 and infers within the US geography.
# https://docs.aws.amazon.com/finops-agent/latest/userguide/what-is.html
check "finops_agent_data_stays_in_the_us" {
  assert {
    condition     = !local.finops_agent ? true : contains(local.acknowledged, "finops_agent_data_stays_in_the_us")
    error_message = "FinOps Agent is on: it reads the organization's cost and resource data, keeps what it stores in us-east-1 and runs inference in the US, whichever Regions the workloads are in. Acknowledge it once the data-residency approval exists. ${local.ack_hint}"
  }
}
