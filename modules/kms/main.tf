
locals {
  default_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })

  key_policy = var.key_policy != null ? var.key_policy : (
    var.additional_policy_statements != null ? jsonencode({
      Version = "2012-10-17"
      Statement = concat(
        jsondecode(local.default_key_policy).Statement,
        var.additional_policy_statements
      )
    }) : local.default_key_policy
  )

  description = var.description != null ? var.description : (
    var.environment != null && var.purpose != null ?
    "KMS key for ${var.purpose} in ${var.environment} environment" :
    var.purpose != null ? "KMS key for ${var.purpose}" : "Managed by Terraform"
  )

  tags = merge(
    {
      Name        = var.name
      ManagedBy   = "Terraform"
      Purpose     = var.purpose
      Environment = var.environment
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}

resource "aws_kms_key" "this" {
  description = local.description

  key_usage                = var.key_usage
  customer_master_key_spec = var.customer_master_key_spec
  multi_region             = var.multi_region

  policy = local.key_policy

  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = var.enable_key_rotation
  rotation_period_in_days = var.rotation_period_in_days

  is_enabled = var.is_enabled

  bypass_policy_lockout_safety_check = var.bypass_policy_lockout_safety_check

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_alias ? 1 : 0

  name          = var.alias_name != null ? var.alias_name : "alias/${var.name}"
  target_key_id = aws_kms_key.this.key_id
}

resource "aws_kms_grant" "this" {
  for_each = var.grants

  name              = each.key
  key_id            = aws_kms_key.this.key_id
  grantee_principal = each.value.grantee_principal

  operations = each.value.operations

  dynamic "constraints" {
    for_each = each.value.constraints != null ? [each.value.constraints] : []
    content {
      encryption_context_equals = try(constraints.value.encryption_context_equals, null)
      encryption_context_subset = try(constraints.value.encryption_context_subset, null)
    }
  }

  retiring_principal    = try(each.value.retiring_principal, null)
  grant_creation_tokens = try(each.value.grant_creation_tokens, null)
  retire_on_delete      = try(each.value.retire_on_delete, true)
}
