# ─────────────────────────────────────────────────────────────────────────────
# Outputs
# All outputs work whether create_role = true or false.
# ─────────────────────────────────────────────────────────────────────────────

locals {
  # When create_role = false the caller must supply role_arn directly.
  _role_arn  = var.create_role ? aws_iam_role.this[0].arn  : var.role_arn
  _role_name = var.create_role ? aws_iam_role.this[0].name : null
  _role_id   = var.create_role ? aws_iam_role.this[0].id   : null
  _role_uid  = var.create_role ? aws_iam_role.this[0].unique_id : null
}

# ── Core ──────────────────────────────────────────────────────────────────────

output "role_arn" {
  description = "ARN of the IRSA IAM role."
  value       = local._role_arn
}

output "role_name" {
  description = "Name of the IRSA IAM role."
  value       = local._role_name
}

output "role_id" {
  description = "ID of the IRSA IAM role (same as name for IAM roles)."
  value       = local._role_id
}

output "role_unique_id" {
  description = <<-EOT
    Stable unique ID of the IAM role.
    Safe to use in S3 bucket policies and other resource-based policies
    because it does not change when the role is renamed.
  EOT
  value = local._role_uid
}

# ── Trust introspection ───────────────────────────────────────────────────────

output "oidc_subjects" {
  description = "List of OIDC subject strings trusted by this role."
  value       = local.oidc_subjects
}

output "trusted_service_accounts" {
  description = "Resolved list of {namespace, service_account} objects trusted by this role."
  value       = local.all_service_accounts
}

# ── Convenience annotation value ─────────────────────────────────────────────

output "service_account_annotation" {
  description = <<-EOT
    Ready-to-use Kubernetes annotation map.
    Apply directly to a ServiceAccount:
      annotations = module.<name>.service_account_annotation
  EOT
  value = {
    "eks.amazonaws.com/role-arn" = local._role_arn
  }
}
