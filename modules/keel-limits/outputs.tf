output "budget_names" {
  description = "Budget names, by limit."
  value       = merge({ for k, b in aws_budgets_budget.spend : k => b.name }, { for k, b in aws_budgets_budget.commitment : k => b.name })
}

output "anomaly_monitor_arns" {
  description = "Anomaly monitor ARNs, by limit, for limits with an anomaly monitor."
  value       = { for k, m in aws_ce_anomaly_monitor.this : k => m.arn }
}

output "lock_policy_arns" {
  description = "The deny policies AWS Budgets attaches at the limit, by limit. Detach one, or raise the limit, to unlock."
  value       = { for k, p in aws_iam_policy.lock : k => p.arn }
}

output "thresholds" {
  description = "Each limit's thresholds with the severity they alert at, for the people subscribing and for the register."
  value = !local.create ? {} : merge(
    { for k, n in local.notifications : k => [for x in n : "${lower(x.type)} ${x.threshold}%: ${upper(x.severity)}"] },
    { for k, l in local.commitment_limits : k => ["below ${l.target_percent}%: WARNING"] },
  )
}

output "controls" {
  description = "The controls these limits implement, as register entries keyed LIMIT-<name>."
  value = !local.create ? null : merge(
    { for k, l in local.spend_limits : "LIMIT-${k}" => {
      statement      = "${upper(l.type) == "USAGE" ? "Usage" : "Spend"} of ${k} stays within ${l.auto_adjust_months > 0 ? "the average of the last ${l.auto_adjust_months} months" : "${l.amount} ${l.unit}"} a ${lower(l.period) == "monthly" ? "month" : (lower(l.period) == "quarterly" ? "quarter" : "year")}"
      type           = contains(keys(merge(local.lock_limits, local.scp_limits)), k) ? "Correct" : "Detect"
      threshold      = join(", ", [for x in local.notifications[k] : "${lower(x.type)} ${x.threshold}%"])
      evidence       = "Budget notification history; the signal on the control plane"
      implemented_by = concat([aws_budgets_budget.spend[k].name], contains(keys(aws_budgets_budget_action.this), k) ? [aws_budgets_budget_action.this[k].action_id] : [])
    } },
    { for k, l in local.commitment_limits : "LIMIT-${k}" => {
      statement      = "${replace(lower(l.type), "_", " ")} stays at or above ${l.target_percent}%"
      type           = "Detect"
      threshold      = "${l.target_percent}%"
      evidence       = "Budget notification history"
      implemented_by = [aws_budgets_budget.commitment[k].name]
    } },
  )
}

output "governance" {
  description = "Every limit as data: type, scope, amount, tier, thresholds, anomaly monitor and action."
  value = !local.create ? null : { for k, l in local.limits : k => {
    type    = l.type
    tier    = l.tier
    scope   = [for e in local.elements[k] : "${e.key} = ${join("|", e.values)}"]
    limit   = contains(["COST", "USAGE"], l.type) ? (l.auto_adjust_months > 0 ? "auto, ${l.auto_adjust_months} months" : "${l.amount} ${l.unit} ${lower(l.period)}") : "${l.target_percent}% ${lower(l.period)}"
    owners  = length(l.owners)
    anomaly = l.anomaly == null ? null : coalesce(l.anomaly.min_impact, var.tiers[l.tier].anomaly_min_impact)
    action  = l.action == null ? null : "${length(l.action.lock_roles) > 0 ? "lock ${join(", ", l.action.lock_roles)}" : "SCP ${try(l.action.scp.policy_id, "")}"} at ${l.action.at_percent}%, ${lower(l.action.approval)}"
  } }
}
