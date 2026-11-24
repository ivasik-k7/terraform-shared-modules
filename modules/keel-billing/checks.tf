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

# https://docs.aws.amazon.com/finops-agent/latest/userguide/setting-up-organization-access.html
check "finops_agent_is_approved" {
  assert {
    condition     = !local.finops_agent ? true : contains(local.acknowledged, "finops_agent_is_approved")
    error_message = "FinOps Agent is chosen: organization-wide it reads every member account's cost, resource and operational data (CloudTrail events, CloudWatch metrics) through a role SCPs do not restrict, everyone who can use it reads all of it, no account can be excluded, and it runs in us-east-1. Acknowledge it once that is approved, then follow output.finops_agent_setup. ${local.ack_hint}"
  }
}
