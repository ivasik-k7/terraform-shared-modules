resource "aws_costoptimizationhub_enrollment_status" "this" {
  count = local.create && var.optimization.cost_optimization_hub ? 1 : 0

  include_member_accounts = var.optimization.include_member_accounts
}

resource "aws_costoptimizationhub_preferences" "this" {
  count = local.create && var.optimization.cost_optimization_hub ? 1 : 0

  savings_estimation_mode            = var.optimization.savings_estimation_mode
  member_account_discount_visibility = var.optimization.member_discount_visibility

  depends_on = [aws_costoptimizationhub_enrollment_status.this]
}

resource "aws_computeoptimizer_enrollment_status" "this" {
  count = local.create && var.optimization.compute_optimizer ? 1 : 0

  status                  = "Active"
  include_member_accounts = var.optimization.include_member_accounts
}
