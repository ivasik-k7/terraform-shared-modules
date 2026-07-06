# The AI agent's AWS identity on a shared account: an SSO-assumable, read-only
# role capped by a hard permission boundary (dangerous/exfil/cross-region denied),
# attributable per human via SourceIdentity, extendable per team, and killable in
# one flip. Provisioned centrally (e.g. Terraform Cloud), not per developer.

resource "aws_iam_policy" "boundary" {
  count = local.create ? 1 : 0

  name        = "${var.name}-boundary"
  description = "Hard permission ceiling for the AI agent role (dangerous/exfil/cross-region denied)."
  policy      = local.boundary_policy
  tags        = local.common_tags
}

resource "aws_iam_role" "this" {
  count = local.create ? 1 : 0

  name                 = var.name
  description          = "AI agent role - read-only baseline, SSO-assumed, attributable, boundary-capped."
  assume_role_policy   = local.assume_role_policy
  permissions_boundary = aws_iam_policy.boundary[0].arn
  max_session_duration = var.max_session_duration
  tags                 = local.common_tags
}

# read-only baseline (still capped by the boundary + exfil deny)
resource "aws_iam_role_policy_attachment" "read_only" {
  count = local.create && var.attach_read_only ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/ReadOnlyAccess"
}

# per-team extensions, layered on top; the boundary still caps them.
resource "aws_iam_role_policy" "team_grants" {
  count = local.create && local.team_grants_policy != null ? 1 : 0

  name   = "${var.name}-team-grants"
  role   = aws_iam_role.this[0].id
  policy = local.team_grants_policy
}

# drift control: inline policies not in this list (manual attachments, or the
# killswitch's emergency deny-all) are removed on apply. See the variable's
# trade-off note before enabling.
resource "aws_iam_role_policies_exclusive" "this" {
  count = local.create && var.exclusive_inline_policies ? 1 : 0

  role_name    = aws_iam_role.this[0].name
  policy_names = local.team_grants_policy != null ? [aws_iam_role_policy.team_grants[0].name] : []
}
