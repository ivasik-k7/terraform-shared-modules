# role + instance profile. skip the whole thing if the caller brings a profile.
# ssm core policy = session manager, which is how you actually reach this box.

data "aws_iam_policy_document" "assume" {
  count = local.create_iam_role ? 1 : 0

  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  count = local.create_iam_role ? 1 : 0

  name_prefix          = substr("${var.name}-", 0, 32)
  assume_role_policy   = data.aws_iam_policy_document.assume[0].json
  permissions_boundary = var.iam_role_permissions_boundary

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion" })
}

resource "aws_iam_role_policy_attachment" "ssm" {
  count = local.create_iam_role && var.enable_ssm ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  count = local.create_iam_role && var.attach_cloudwatch_agent_policy ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = local.create_iam_role ? var.iam_role_additional_policy_arns : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = local.create_iam_role ? 1 : 0

  name_prefix = substr("${var.name}-", 0, 32)
  role        = aws_iam_role.this[0].name

  tags = merge(local.common_tags, { "Name" = "${var.name}-bastion" })

  lifecycle {
    create_before_destroy = true
  }
}
