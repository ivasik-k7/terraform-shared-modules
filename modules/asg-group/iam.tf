resource "aws_iam_role" "this" {
  count = local.create_role ? 1 : 0

  # IAM caps name_prefix at 38 characters; var.name is validated to fit.
  name_prefix          = "${var.name}-"
  description          = "Instances of Auto Scaling group ${var.name}."
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_instance_profile" "this" {
  count = local.create_role ? 1 : 0

  name_prefix = "${var.name}-"
  role        = aws_iam_role.this[0].name
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.create_role ? local.managed_policies : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.create_role ? var.instance_profile.policies : {}

  name   = each.key
  role   = aws_iam_role.this[0].id
  policy = each.value
}
