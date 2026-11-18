# The role ECR assumes to create repositories from templates: a template that
# sets tags or a key needs one, or the creation fails.
# https://docs.aws.amazon.com/AmazonECR/latest/userguide/repository-creation-templates-custom.html
resource "aws_iam_role" "templates" {
  count = local.create_template_role ? 1 : 0

  name        = local.template_role_name
  description = "ECR repository creation templates in ${local.region}: creates, tags and encrypts the repositories ECR makes for pull through cache, replication and create on push."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecr.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "templates" {
  count = local.create_template_role ? 1 : 0

  name = "ecr-module"
  role = aws_iam_role.templates[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Sid      = "CreateTemplatedRepositories"
        Effect   = "Allow"
        Action   = ["ecr:CreateRepository", "ecr:ReplicateImage", "ecr:TagResource"]
        Resource = local.template_repository_arns
      }],
      length(local.template_keys) == 0 ? [] : [{
        Sid      = "EncryptTemplatedRepositories"
        Effect   = "Allow"
        Action   = ["kms:CreateGrant", "kms:DescribeKey", "kms:RetireGrant"]
        Resource = local.template_keys
      }],
    )
  })
}
