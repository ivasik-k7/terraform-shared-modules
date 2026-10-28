# ---------------------------------------------------------------------------
# Resources: what callers wire to their other resources.
# ---------------------------------------------------------------------------

output "name" {
  description = "Log group name."
  value       = one(aws_cloudwatch_log_group.this[*].name)
}

output "arn" {
  description = "Log group ARN, without the :* suffix (add it for IAM resource statements on log streams)."
  value       = one(aws_cloudwatch_log_group.this[*].arn)
}

# ---------------------------------------------------------------------------
# Contracts: facts another team acts on, as data rather than prose.
# ---------------------------------------------------------------------------

output "kms_key_policy_requirements" {
  description = "What the customer managed key's policy has to allow, in contract version 2: key, sid, principals = { services, arns, roles }, actions, conditions = [{ test, variable, values }], purpose. Known at plan, so the key owner can act before the apply."
  value = !local.create || var.kms_key_arn == "" ? null : [{
    key        = var.kms_key_arn
    sid        = "LogGroup"
    principals = { services = ["logs.${local.region}.amazonaws.com"], arns = [], roles = [] }
    actions    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    conditions = [{ test = "ArnEquals", variable = "kms:EncryptionContext:aws:logs:arn", values = [local.log_group_arn] }]
    purpose    = "CloudWatch Logs encrypts this log group. Without it, creating the group fails."
  }]
}

output "governance" {
  description = "The posture as data: assert on it in tests, diff it in a change review."
  value = !local.create ? null : {
    retention_days      = var.retention_days
    log_group_class     = var.log_group_class
    customer_key        = var.kms_key_arn != ""
    survives_destroy    = var.skip_destroy
    acknowledged_checks = sort(var.acknowledged_checks)
  }
}

output "verify_commands" {
  description = "AWS CLI commands to run from CloudShell after an apply."
  value = !local.create ? null : {
    describe = "aws logs describe-log-groups --log-group-name-prefix ${var.name} --query 'logGroups[?logGroupName==`${var.name}`].[logGroupName,retentionInDays,kmsKeyId,logGroupClass]' --output table"
    # Infrequent Access has no FilterLogEvents, which tail uses.
    read = var.log_group_class == "STANDARD" ? "aws logs tail ${var.name} --since 1h" : "aws logs start-query --log-group-name ${var.name} --start-time $(date -d '-1 hour' +%s) --end-time $(date +%s) --query-string 'fields @timestamp, @message | sort @timestamp desc | limit 50'"
  }
}
