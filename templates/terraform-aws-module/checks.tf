# Warnings, not refusals: postures a real configuration may want, but a
# reviewer should see in every plan and every HCP Terraform health
# assessment. Each is silent under create = false and once acknowledged.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."
}

check "log_retention_is_bounded" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "log_retention_is_bounded") ? true : var.retention_days != 0)
    error_message = "retention_days = 0 keeps every log event forever; storage is billed every month for everything ever written. ${local.ack_hint}"
  }
}

check "logs_use_a_customer_key" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "logs_use_a_customer_key") ? true : var.kms_key_arn != "")
    error_message = "the log group uses CloudWatch Logs' own encryption, not a key you control: access cannot be revoked by key policy. ${local.ack_hint}"
  }
}
