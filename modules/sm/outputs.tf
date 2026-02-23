output "secrets" {
  description = "Full metadata for all managed secrets: { key => { arn, id, name, version_id } }. Use module.secrets.secrets[\"<key>\"].arn for downstream references."
  value = {
    for k, v in local.all_secret_resources : k => {
      arn        = v.arn
      id         = v.id
      name       = v.name
      version_id = try(local.all_version_resources[k].version_id, null)
    }
  }
}

output "secret_arns" {
  description = "Map of secret key to ARN. Convenience alias for module.secrets.secrets[*].arn."
  value       = { for k, v in local.all_secret_resources : k => v.arn }
}

output "secret_ids" {
  description = "Map of secret key to Secret ID (path name)."
  value       = { for k, v in local.all_secret_resources : k => v.id }
}

output "secret_names" {
  description = "Map of secret key to fully-resolved path."
  value       = { for k, v in local.all_secret_resources : k => v.name }
}

output "secret_version_ids" {
  description = "Map of secret key to current AWSCURRENT version ID. Use to force downstream re-reads on rotation."
  value       = { for k, v in local.all_version_resources : k => v.version_id }
}

output "iam_read_arns" {
  description = "List of all secret ARNs for use in IAM policy Resource blocks granting read access."
  value       = [for k, v in local.all_secret_resources : v.arn]
}

output "resolved_paths" {
  description = "Map of secret key to computed full path. Use to verify naming convention before apply."
  value       = { for k, cfg in local.resolved : k => cfg.full_path }
}

output "rotation_enabled" {
  description = "Map of secret key to bool indicating whether automatic rotation is configured."
  value = {
    for k in keys(local.all_secret_resources) : k =>
    contains(keys(aws_secretsmanager_secret_rotation.this), k)
  }
}
