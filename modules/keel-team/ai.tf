locals {
  applications = local.regional ? var.ai.applications : {}
  profiles = merge([for app, a in local.applications : {
    for alias, arn in a.models : "${app}/${alias}" => { application = app, alias = alias, source = arn, platform = a.platform }
  }]...)

  burn_alarm      = local.regional ? var.ai.burn_per_hour > 0 : false
  invocation_logs = local.regional ? var.ai.invocation_logs.enabled : false
  quotas          = local.regional ? var.ai.quotas : {}

  # CloudWatch ids: a lowercase letter first, then letters, digits and underscores.
  model_ids = { for i, m in sort(keys(var.ai.prices)) : m => "m${i}" }

  log_group_name = "/keel/${var.team}/bedrock-invocations"
}

# ---------------------------------------------------------------------------
# A tagged inference profile per application and model: calls through it
# carry Team, Application and the platform tag onto the bill
# ---------------------------------------------------------------------------

resource "aws_bedrock_inference_profile" "this" {
  for_each = local.profiles

  name = "${var.team}-${each.value.application}-${each.value.alias}"
  # Pattern ([0-9a-zA-Z:.][ _-]?)+ for the description, ([0-9a-zA-Z][ _-]?)+
  # and 64 characters for the name.
  # https://docs.aws.amazon.com/bedrock/latest/APIReference/API_CreateInferenceProfile.html
  description = "${var.team} ${each.value.application} ${each.value.alias}"
  tags = merge(
    local.tags,
    { Application = each.value.application },
    each.value.platform != "" ? { (var.platform_tag_key) = each.value.platform } : {},
  )

  model_source {
    copy_from = each.value.source
  }
}

# ---------------------------------------------------------------------------
# Burn meter: the last hour's token use, priced, ahead of the bill
# ---------------------------------------------------------------------------

# Bedrock publishes InputTokenCount and OutputTokenCount per ModelId.
# https://docs.aws.amazon.com/bedrock/latest/userguide/monitoring.html
resource "aws_cloudwatch_metric_alarm" "ai_burn" {
  count = local.burn_alarm ? 1 : 0

  alarm_name          = "${var.team}-ai-burn"
  alarm_description   = "${var.team}'s priced Bedrock token use in ${local.region} over the last hour is above ${var.ai.burn_per_hour} ${var.ai.unit}."
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.ai.burn_per_hour
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [local.topic_arns["critical"]]
  ok_actions          = [local.topic_arns["info"]]
  tags                = local.tags

  metric_query {
    id          = "cost"
    label       = "Bedrock cost, last hour (${var.ai.unit})"
    return_data = true
    expression = join(" + ", [for m, p in var.ai.prices :
      "(FILL(${local.model_ids[m]}in, 0) * ${p.input_per_million} + FILL(${local.model_ids[m]}out, 0) * ${p.output_per_million}) / 1000000"
    ])
  }

  dynamic "metric_query" {
    for_each = var.ai.prices
    content {
      id = "${local.model_ids[metric_query.key]}in"
      metric {
        namespace   = "AWS/Bedrock"
        metric_name = "InputTokenCount"
        dimensions  = { ModelId = metric_query.key }
        stat        = "Sum"
        period      = 3600
      }
    }
  }

  dynamic "metric_query" {
    for_each = var.ai.prices
    content {
      id = "${local.model_ids[metric_query.key]}out"
      metric {
        namespace   = "AWS/Bedrock"
        metric_name = "OutputTokenCount"
        dimensions  = { ModelId = metric_query.key }
        stat        = "Sum"
        period      = 3600
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Quotas: the applied tokens-per-minute ceiling is the fastest the bill can grow
# ---------------------------------------------------------------------------

data "aws_servicequotas_service_quota" "ai" {
  for_each = local.quotas

  service_code = each.value.service_code
  quota_code   = each.value.quota_code
}

# ---------------------------------------------------------------------------
# Invocation logs: who called which model, with what token counts; no
# prompt, response, image, embedding or video
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "invocations" {
  count = local.invocation_logs ? 1 : 0

  name              = local.log_group_name
  retention_in_days = var.ai.invocation_logs.retention_days
  kms_key_id        = var.signals.kms_key_arn != "" ? var.signals.kms_key_arn : null
  tags              = local.tags
}

# https://docs.aws.amazon.com/bedrock/latest/userguide/model-invocation-logging.html
resource "aws_iam_role" "invocation_logs" {
  count = local.invocation_logs ? 1 : 0

  name_prefix          = "${substr(var.team, 0, 20)}-bedrock-logs-"
  description          = "Bedrock writes ${var.team}'s model invocation metadata to CloudWatch Logs in ${local.region}"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "bedrock.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:bedrock:${local.region}:${local.account_id}:*" }
      }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "invocation_logs" {
  count = local.invocation_logs ? 1 : 0

  name = "write-invocation-logs"
  role = aws_iam_role.invocation_logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${aws_cloudwatch_log_group.invocations[0].name}:log-stream:aws/bedrock/modelinvocations"
    }]
  })
}

# One configuration per account and Region.
resource "aws_bedrock_model_invocation_logging_configuration" "this" {
  count = local.invocation_logs ? 1 : 0

  logging_config {
    text_data_delivery_enabled      = false
    image_data_delivery_enabled     = false
    embedding_data_delivery_enabled = false
    video_data_delivery_enabled     = false

    cloudwatch_config {
      log_group_name = aws_cloudwatch_log_group.invocations[0].name
      role_arn       = aws_iam_role.invocation_logs[0].arn
    }
  }

  depends_on = [aws_iam_role_policy.invocation_logs]
}
