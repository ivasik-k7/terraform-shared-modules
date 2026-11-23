# ---------------------------------------------------------------------------
# Organization limits and commitment targets, alerting by severity
# ---------------------------------------------------------------------------

module "limits" {
  source = "../keel-limits"

  create                   = local.create
  name                     = var.name
  tags                     = local.tags
  acknowledged_checks      = [for c in var.acknowledged_checks : c if contains(local.limit_checks, c)]
  permissions_boundary_arn = var.permissions_boundary_arn
  topic_arns               = local.topic_arns
  tiers                    = length(var.tiers) > 0 ? var.tiers : null
  limits                   = local.limits

  depends_on = [aws_ce_cost_category.this, aws_ce_cost_allocation_tag.this]
}
