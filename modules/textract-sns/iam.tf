resource "aws_iam_role" "textract" {
  name                 = local.resource_names.iam_role
  description          = "IAM role for AWS Textract to access S3 and SNS in ${var.environment} environment"
  assume_role_policy   = data.aws_iam_policy_document.textract_assume_role.json
  permissions_boundary = var.iam_permissions_boundary_arn

  tags = merge(
    local.common_tags,
    {
      Name        = local.resource_names.iam_role
      Description = "Textract service role for document processing"
    }
  )
}

resource "aws_iam_role_policy" "textract" {
  name   = local.resource_names.iam_policy
  role   = aws_iam_role.textract.id
  policy = data.aws_iam_policy_document.textract_permissions.json
}
