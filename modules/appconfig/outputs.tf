output "application_id" {
  description = "ID of the AppConfig application."
  value       = one(aws_appconfig_application.this[*].id)
}

output "application_arn" {
  description = "ARN of the AppConfig application."
  value       = one(aws_appconfig_application.this[*].arn)
}

output "environment_ids" {
  description = "Map of environment key => environment id."
  value       = { for k, e in aws_appconfig_environment.this : k => e.environment_id }
}

output "profile_ids" {
  description = "Map of profile instance key => configuration profile id (env-specialized profiles use \"profile:env\" keys)."
  value       = { for k, p in aws_appconfig_configuration_profile.this : k => p.configuration_profile_id }
}

output "hosted_version_numbers" {
  description = "Map of profile instance key => current hosted configuration version number."
  value       = { for k, v in aws_appconfig_hosted_configuration_version.this : k => v.version_number }
}

output "deployment_strategy_ids" {
  description = "Map of custom strategy key => strategy id."
  value       = { for k, s in aws_appconfig_deployment_strategy.this : k => s.id }
}

output "deployment_numbers" {
  description = "Map of environment:profile => latest deployment number managed here."
  value       = { for k, d in aws_appconfig_deployment.this : k => d.deployment_number }
}

output "monitor_role_arn" {
  description = "Role AppConfig uses to read rollback alarms (null when no alarms and none provided)."
  value       = local.any_alarms ? local.monitor_role_arn : null
}

output "events_topic_arn" {
  description = "SNS topic carrying deployment lifecycle events (null when notifications are off)."
  value       = var.enable_notifications ? local.topic_arn : null
}

# ---- rendered artifacts ----
# feature_flags_json renders even with create = false - review exactly what
# would ship, diff it in MRs, lint it in CI without credentials.

output "feature_flags_json" {
  description = "Map of feature-flags instance key => the rendered AWS.AppConfig.FeatureFlags document (env-specialized profiles render one per environment)."
  value       = local.feature_flags_json
}

output "retrieval_policy_json" {
  description = "Least-privilege IAM policy for consumers: session-based retrieval scoped to exactly this application's environments/profiles. Attach to the app runtime role."
  value = !local.create || length(var.environments) == 0 || length(var.profiles) == 0 ? null : jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "GetConfiguration"
      Effect = "Allow"
      Action = ["appconfig:StartConfigurationSession", "appconfig:GetLatestConfiguration"]
      Resource = flatten([
        for ek, e in aws_appconfig_environment.this : [
          for pk, p in aws_appconfig_configuration_profile.this :
          "arn:${one(data.aws_partition.current[*].partition)}:appconfig:${one(data.aws_region.current[*].name)}:${one(data.aws_caller_identity.current[*].account_id)}:application/${one(aws_appconfig_application.this[*].id)}/environment/${e.environment_id}/configuration/${p.configuration_profile_id}"
        ]
      ])
    }]
  })
}

output "fetch_example" {
  description = "How a consumer fetches configuration (session-based API; use the AppConfig Agent or Lambda extension in production)."
  value = !local.create || length(var.environments) == 0 || length(var.profiles) == 0 ? null : trimspace(<<-EOT
    aws appconfigdata start-configuration-session \
      --application-identifier ${one(aws_appconfig_application.this[*].id)} \
      --environment-identifier <env-id> \
      --configuration-profile-identifier <profile-id> \
      --query InitialConfigurationToken --output text \
    | xargs -I{} aws appconfigdata get-latest-configuration \
        --configuration-token {} /dev/stdout
  EOT
  )
}
