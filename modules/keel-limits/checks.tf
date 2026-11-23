# Warnings, not refusals. Each is silent under create = false and once named
# in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  automatic_where_people_decide = sort([
    for k, l in merge(local.lock_limits, local.scp_limits) : k if l.action.approval == "AUTOMATIC" ? !var.tiers[l.tier].automatic_actions : false
  ])
  ownerless_limits = sort([for k, l in local.limits : k if length(l.owners) == 0 && length(var.topic_arns) == 0])
  missing_topics   = sort([for s in local.needed_severities : s if !contains(keys(var.topic_arns), s)])
}

check "production_changes_only_by_people" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "production_changes_only_by_people") ? true : length(local.automatic_where_people_decide) == 0)
    error_message = "Limits whose tier does not allow automatic actions run one automatically: ${join(", ", local.automatic_where_people_decide)}. Production is changed through people: set action.approval = MANUAL, so the action waits in AWS Budgets for approval. ${local.ack_hint}"
  }
}

check "every_limit_has_an_owner" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "every_limit_has_an_owner") ? true : length(local.ownerless_limits) == 0 && length(local.missing_topics) == 0)
    error_message = "Alerts that reach nobody: limits with no owners and no topics (${join(", ", local.ownerless_limits)}); severities used with no topic in topic_arns (${join(", ", local.missing_topics)}). ${local.ack_hint}"
  }
}
