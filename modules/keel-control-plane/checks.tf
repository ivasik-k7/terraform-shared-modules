# Warnings, not refusals. Each is silent under create = false and once named
# in acknowledged_checks.

locals {
  ack_hint = "Acknowledge it with acknowledged_checks if this is intended."

  silent_severities = sort([for s in ["warning", "high", "critical"] : s if length(lookup(var.severity.emails, s, [])) == 0])
}

check "evidence_is_immutable" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "evidence_is_immutable") ? true : var.evidence.mode == "COMPLIANCE")
    error_message = "Evidence is locked in GOVERNANCE mode: anyone with s3:BypassGovernanceRetention can delete it, so it is not evidence an auditor can rely on. Switch to COMPLIANCE once the pipeline is accepted; that cannot be undone. ${local.ack_hint}"
  }
}

check "every_severity_reaches_someone" {
  assert {
    condition     = !local.create ? true : (contains(local.acknowledged, "every_severity_reaches_someone") ? true : length(local.silent_severities) == 0)
    error_message = "Severities with no e-mail subscriber: ${join(", ", local.silent_severities)}. Their signals are recorded and reach nobody, unless a chat or paging tool subscribes to output.topic_arns outside this module. ${local.ack_hint}"
  }
}
