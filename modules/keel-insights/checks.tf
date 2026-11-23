# Warnings, not refusals. Each is silent under create = false and once named
# in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  # Which table each dashboard reads.
  dashboards_without_data = sort(concat(
    (var.dashboards.cudos_v5 || var.dashboards.kpi || var.dashboards.cost_intelligence) && !var.data_exports.cur2 ? ["CUDOS v5, KPI and Cost Intelligence need CUR 2.0 (data_exports.cur2)"] : [],
    contains(var.dashboards.plugins, "focus-dashboard") && !var.data_exports.focus ? ["focus-dashboard needs FOCUS (data_exports.focus)"] : [],
    contains(var.dashboards.plugins, "cora") && !var.data_exports.coh ? ["cora needs the Cost Optimization Hub export (data_exports.coh)"] : [],
    contains(var.dashboards.plugins, "scad-containers-cost-allocation") && !var.data_exports.split_cost_allocation ? ["scad-containers-cost-allocation needs split cost allocation data (data_exports.split_cost_allocation)"] : [],
  ))
}

check "dashboards_have_their_data" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "dashboards_have_their_data") ? true : length(local.dashboards_without_data) == 0)
    error_message = "Dashboards without the table they read: ${join("; ", local.dashboards_without_data)}. They deploy and show nothing, or fail to create their datasets. Turn the export on here and in keel-billing. ${local.ack_hint}"
  }
}
