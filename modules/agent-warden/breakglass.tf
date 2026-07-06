# Break-glass: a separate, elevated, short-lived role for emergencies the
# read-only AI identity can't handle. Non-negotiable guardrails: MFA required,
# SourceIdentity required (who broke the glass), short session, and - when
# alerting is on - every assumption pages SNS. Deliberately NOT boundary-capped,
# because that's the whole point of break-glass; keep the policy set tight instead.

resource "aws_iam_role" "break_glass" {
  count = local.create && var.enable_break_glass ? 1 : 0

  name                 = "${var.name}-breakglass"
  description          = "Emergency elevated access - MFA + SourceIdentity required, short-lived, alerted."
  max_session_duration = var.break_glass_max_session_duration
  tags                 = local.common_tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "BreakGlassAssume"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account}:root" }
        Action    = ["sts:AssumeRole", "sts:TagSession", "sts:SetSourceIdentity"]
        Condition = {
          ArnLike = { "aws:PrincipalArn" = local.break_glass_sso_arns }
          Bool    = { "aws:MultiFactorAuthPresent" = "true" }
          Null    = { "sts:SourceIdentity" = "false" }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "break_glass" {
  for_each = local.create && var.enable_break_glass ? toset(var.break_glass_policy_arns) : toset([])

  role       = aws_iam_role.break_glass[0].name
  policy_arn = each.value
}
