output "role_arn" {
  description = "ARN of the AI agent role - what the agent assumes."
  value       = one(aws_iam_role.this[*].arn)
}

output "role_name" {
  description = "Name of the AI agent role."
  value       = one(aws_iam_role.this[*].name)
}

output "permission_boundary_arn" {
  description = "ARN of the permission boundary policy (the hard ceiling)."
  value       = one(aws_iam_policy.boundary[*].arn)
}

output "kill_switch_engaged" {
  description = "True when the kill switch is denying all actions."
  value       = local.create && var.kill_switch
}

output "access_expires_at" {
  description = "When the AI identity self-expires (empty = never)."
  value       = var.access_expires_at
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass role (null unless enabled)."
  value       = one(aws_iam_role.break_glass[*].arn)
}

output "alert_topic_arn" {
  description = "SNS topic carrying alerts / budget / digest notifications (null when no notification feature is on)."
  value       = local.notifications_wanted ? local.topic_arn : null
}

# the one way in: JIT creds, no long-lived keys, SourceIdentity stamped. Works
# in both attribution modes, so this replaces the old plain-profile "setup" output
# (a bare role_arn profile can't set SourceIdentity and breaks the default mode).
output "credential_process" {
  description = "Drop-in ~/.aws/config profile that mints short-lived, attributed creds on demand via credential_process."
  value = !local.create ? null : trimspace(<<-EOT
    [profile ai-agent]
    region = ${var.allowed_regions[0]}
    credential_process = bash -c 'aws sts assume-role \
      --role-arn ${one(aws_iam_role.this[*].arn)} \
      --role-session-name "$${USER:-ai-agent}" \
      --source-identity "$${USER:-ai-agent}" \
      --duration-seconds ${var.max_session_duration} \
      --query "Credentials | {Version: \`1\`, AccessKeyId: AccessKeyId, SecretAccessKey: SecretAccessKey, SessionToken: SessionToken, Expiration: Expiration}" \
      --output json'
  EOT
  )
}

# ---- rendered policy documents ----
# Available even with create = false, so CI can render + lint them offline and
# reviewers can read exactly what would be enforced.

output "boundary_policy_json" {
  description = "The permission-boundary document (renderable offline for lint/review)."
  value       = local.boundary_policy
}

output "trust_policy_json" {
  description = "The AI role's trust (assume-role) document."
  value       = local.assume_role_policy
}

output "team_grants_policy_json" {
  description = "The rendered team-grants document (null when no grants)."
  value       = local.team_grants_policy
}

output "scp_policy_json" {
  description = "Org-level SCP that stops everyone except provisioner_principal_arns from lifting the AI guardrails (role trust/policies/boundary). Attach via your org-management stack. Null until provisioner_principal_arns is set."
  value       = local.scp_policy
}
