# ─────────────────────────────────────────────────────────────────────────────
# logging.tf – CloudWatch log group for EKS control-plane logs
# ─────────────────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${local.name}/cluster"
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  kms_key_id        = local.kms_key_arn
  tags              = merge(local.common_tags, { Name = "${local.name}-control-plane-logs" })
}
