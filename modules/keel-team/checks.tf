# Warnings, not refusals. Each is silent under create = false, outside the part
# it concerns, and once named in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  actions   = sort([for k, l in local.limits : k if try(l.action, null) != null])
  any_email = length(flatten(values(var.emails))) > 0
}

check "every_account_has_a_limit" {
  assert {
    condition     = !local.account ? true : (contains(local.acknowledged, "every_account_has_a_limit") ? true : length(local.account_limits) > 0)
    error_message = "No limit covers the whole account (a COST limit with an empty scope): spend outside the platforms and AI applications has no budget, so FC-01 is not met. ${local.ack_hint}"
  }
}

check "sandboxes_lock_at_their_limit" {
  assert {
    condition     = !local.account ? true : (contains(local.acknowledged, "sandboxes_lock_at_their_limit") ? true : (var.tier != "sandbox" ? true : length(local.actions) > 0))
    error_message = "A sandbox with no action on any limit: a runaway sandbox keeps spending past its limit until someone reads the alert. Give its account limit an action with lock_roles. ${local.ack_hint}"
  }
}

check "somebody_hears_the_team" {
  assert {
    condition     = !local.regional ? true : (contains(local.acknowledged, "somebody_hears_the_team") ? true : (local.any_email ? true : var.signals.control_plane_bus_arn != ""))
    error_message = "No emails and no control plane: this Region's alerts go to topics nobody reads. ${local.ack_hint}"
  }
}

check "signals_reach_the_control_plane" {
  assert {
    condition     = !local.regional ? true : (contains(local.acknowledged, "signals_reach_the_control_plane") ? true : var.signals.control_plane_bus_arn != "")
    error_message = "signals.control_plane_bus_arn is empty: this Region's signals are not recorded as evidence or routed by severity. ${local.ack_hint}"
  }
}

check "ai_burn_is_metered" {
  assert {
    condition     = !local.regional ? true : (contains(local.acknowledged, "ai_burn_is_metered") ? true : (length(local.applications) == 0 ? true : local.burn_alarm))
    error_message = "AI applications in this Region with no burn meter (ai.burn_per_hour = 0): the caps are budgets, which see spend hours late, so a runaway agent is stopped only by the bill. Set prices and burn_per_hour. ${local.ack_hint}"
  }
}

check "ai_invocations_are_logged" {
  assert {
    condition     = !local.regional ? true : (contains(local.acknowledged, "ai_invocations_are_logged") ? true : (length(local.applications) == 0 ? true : local.invocation_logs))
    error_message = "AI applications in this Region with no invocation logs: a spike in the burn meter cannot be traced to the caller. Set ai.invocation_logs.enabled (metadata only). ${local.ack_hint}"
  }
}
