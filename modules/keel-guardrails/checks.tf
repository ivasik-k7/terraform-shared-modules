# Warnings, not refusals. Each is silent under create = false and once named
# in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  scps_without_exemption = sort(concat(
    var.deny_untagged.enabled && length(var.deny_untagged.exempt_principals) == 0 ? ["untagged"] : [],
    var.bedrock_models.enabled && length(var.bedrock_models.exempt_principals) == 0 ? ["models"] : [],
  ))
}

check "guardrails_are_attached" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "guardrails_are_attached") ? true : (length(local.active_policies) == 0 ? true : length(var.targets) > 0))
    error_message = "Policies are created but targets is empty: they exist and govern nothing. ${local.ack_hint}"
  }
}

check "someone_can_break_glass" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "someone_can_break_glass") ? true : length(local.scps_without_exemption) == 0)
    error_message = "Service control policies with no exempt principals: ${join(", ", local.scps_without_exemption)}. They bind every role in the target accounts, the platform's own included, so a wrong tag key blocks the people who would fix it. Exempt a break-glass role. ${local.ack_hint}"
  }
}
