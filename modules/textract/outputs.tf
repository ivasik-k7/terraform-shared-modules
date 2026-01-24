
output "textract_role_arn" {
  description = "ARN of the IAM role for Textract"
  value       = aws_iam_role.textract.arn
}

output "textract_role_name" {
  description = "Name of the IAM role for Textract"
  value       = aws_iam_role.textract.name
}

output "sns_topic_completion_arn" {
  description = "ARN of the SNS topic for job completion notifications"
  value       = var.enable_async_processing ? aws_sns_topic.textract_completion[0].arn : null
}

output "sns_topic_failure_arn" {
  description = "ARN of the SNS topic for job failure notifications"
  value       = var.enable_async_processing ? aws_sns_topic.textract_failure[0].arn : null
}

output "cloudwatch_log_group_name" {
  description = "Name of the CloudWatch log group for Textract"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.textract[0].name : null
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for Textract"
  value       = var.enable_cloudwatch_logs ? aws_cloudwatch_log_group.textract[0].arn : null
}

output "module_config" {
  description = "Configuration summary for the Textract module"
  value = {
    project_name           = var.project_name
    environment            = var.environment
    async_processing       = var.enable_async_processing
    sns_encryption         = var.enable_sns_encryption
    cloudwatch_logs        = var.enable_cloudwatch_logs
    cloudwatch_alarms      = var.enable_cloudwatch_alarms
    input_bucket_arn       = var.input_bucket_arn
    output_bucket_arn      = var.output_bucket_arn
    input_bucket_prefix    = var.input_bucket_prefix
    output_bucket_prefix   = var.output_bucket_prefix
    allowed_document_types = var.allowed_document_types
    textract_features      = var.textract_features
    max_document_size_mb   = var.max_document_size_mb
    cross_account_enabled  = var.enable_cross_account_access
  }
}

output "deployment_metadata" {
  description = "Metadata about the deployment including region, account, and versioning info"
  value       = local.deployment_metadata
}

output "resource_names" {
  description = "All generated resource names for reference and integration"
  value       = local.resource_names
}

output "naming_context" {
  description = "Naming convention details for documentation and troubleshooting"
  value = {
    name_prefix       = local.name_prefix
    name_prefix_short = local.name_prefix_short
    region_code       = local.region_code
    account_id_short  = local.account_id_short
    full_region       = data.aws_region.current.name
    account_id        = data.aws_caller_identity.current.account_id
  }
}

output "sns_dlq_arn" {
  description = "ARN of the Dead Letter Queue for SNS (if enabled)"
  value       = var.enable_async_processing && var.enable_dead_letter_queue ? aws_sqs_queue.sns_dlq[0].arn : null
}

output "sns_dlq_url" {
  description = "URL of the Dead Letter Queue for SNS (if enabled)"
  value       = var.enable_async_processing && var.enable_dead_letter_queue ? aws_sqs_queue.sns_dlq[0].url : null
}

output "s3_resources" {
  description = "S3 resource ARNs and paths configured for Textract"
  value       = local.s3_resources
}

output "subscription_arns" {
  description = "ARNs of all SNS topic subscriptions created"
  value = {
    email_completion  = var.enable_async_processing ? [for s in aws_sns_topic_subscription.email_completion : s.arn] : []
    email_failure     = var.enable_async_processing ? [for s in aws_sns_topic_subscription.email_failure : s.arn] : []
    sqs_completion    = var.enable_async_processing ? [for s in aws_sns_topic_subscription.sqs_completion : s.arn] : []
    sqs_failure       = var.enable_async_processing ? [for s in aws_sns_topic_subscription.sqs_failure : s.arn] : []
    lambda_completion = var.enable_async_processing ? [for s in aws_sns_topic_subscription.lambda_completion : s.arn] : []
    lambda_failure    = var.enable_async_processing ? [for s in aws_sns_topic_subscription.lambda_failure : s.arn] : []
  }
}

output "alarm_arns" {
  description = "ARNs of CloudWatch alarms created for monitoring"
  value = {
    error_alarm    = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.textract_errors[0].arn : null
    throttle_alarm = var.enable_cloudwatch_alarms ? aws_cloudwatch_metric_alarm.textract_throttles[0].arn : null
  }
}
