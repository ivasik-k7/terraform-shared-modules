locals {
  path_segments = compact([var.name_prefix, var.environment])

  resolved = {
    for key, cfg in var.secrets : key => {
      full_path = join("/", concat(local.path_segments, [key]))

      resolved_string = (
        cfg.secret_string != null ? cfg.secret_string :
        cfg.secret_key_value != null ? jsonencode(cfg.secret_key_value) :
        null
      )

      kms_key_id = try(coalesce(cfg.kms_key_id, var.default_kms_key_id), null)

      recovery_window_in_days = coalesce(cfg.recovery_window_in_days, var.default_recovery_window_in_days)

      tags = merge(
        {
          "managed-by"  = "terraform"
          "environment" = var.environment
        },
        var.default_tags,
        cfg.tags,
      )
    }
  }

  managed   = { for k, v in var.secrets : k => v if !v.ignore_secret_changes }
  unmanaged = { for k, v in var.secrets : k => v if v.ignore_secret_changes }

  has_value_managed = {
    for k, v in local.managed : k => v
    if local.resolved[k].resolved_string != null || v.secret_binary != null
  }

  has_value_unmanaged = {
    for k, v in local.unmanaged : k => v
    if local.resolved[k].resolved_string != null || v.secret_binary != null
  }

  rotation_keys = { for k, v in var.secrets : k => v if v.rotation != null }

  all_secret_resources = merge(
    { for k, v in aws_secretsmanager_secret.managed : k => v },
    { for k, v in aws_secretsmanager_secret.unmanaged : k => v },
  )

  all_version_resources = merge(
    { for k, v in aws_secretsmanager_secret_version.managed : k => v },
    { for k, v in aws_secretsmanager_secret_version.unmanaged : k => v },
  )

  policy_keys = {
    for k, cfg in var.secrets : k => cfg
    if(
      cfg.policy != null ||
      length(var.reader_arns) > 0 ||
      length(var.manager_arns) > 0
    )
  }

  manager_actions = [
    "secretsmanager:CancelRotateSecret",
    "secretsmanager:DeleteSecret",
    "secretsmanager:DescribeSecret",
    "secretsmanager:GetResourcePolicy",
    "secretsmanager:GetSecretValue",
    "secretsmanager:ListSecretVersionIds",
    "secretsmanager:PutResourcePolicy",
    "secretsmanager:PutSecretValue",
    "secretsmanager:RestoreSecret",
    "secretsmanager:RotateSecret",
    "secretsmanager:TagResource",
    "secretsmanager:UntagResource",
    "secretsmanager:UpdateSecret",
    "secretsmanager:UpdateSecretVersionStage",
  ]

  reader_actions = [
    "secretsmanager:DescribeSecret",
    "secretsmanager:GetResourcePolicy",
    "secretsmanager:GetSecretValue",
    "secretsmanager:ListSecretVersionIds",
  ]
}
