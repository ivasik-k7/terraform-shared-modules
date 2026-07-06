# FinOps guardrail: track spend attributable to the AI (by cost-allocation tag)
# against a monthly budget. Every threshold notifies the shared alerts topic; the
# FINAL threshold additionally notifies a DEDICATED killswitch topic so the
# containment Lambda only fires on a real budget breach - never on a digest or
# an ordinary alert (which all share the alerts topic).

resource "aws_budgets_budget" "ai" {
  count = local.create && var.enable_budget_guardrail ? 1 : 0

  name         = "${var.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  cost_filter {
    name = "TagKeyValue"
    # AWS wants the literal form user:<key>$<value>
    values = [format("user:%s$%s", var.budget_cost_tag.key, var.budget_cost_tag.value)]
  }

  dynamic "notification" {
    for_each = var.budget_alert_thresholds_percent
    content {
      comparison_operator = "GREATER_THAN"
      threshold           = notification.value
      threshold_type      = "PERCENTAGE"
      notification_type   = "ACTUAL"
      subscriber_sns_topic_arns = concat(
        local.topic_arn != null ? [local.topic_arn] : [],
        # only the final threshold pulls the containment trigger
        var.enable_budget_killswitch && notification.value >= local.budget_final_threshold ? [local.killswitch_topic_arn] : [],
      )
      subscriber_email_addresses = []
    }
  }

  # forecast fires before the money is gone (cost data lags ~8-24h). Alert only -
  # a forecast is a prediction, never grounds for auto-containment.
  dynamic "notification" {
    for_each = var.budget_forecasted_threshold_percent > 0 ? [var.budget_forecasted_threshold_percent] : []
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value
      threshold_type             = "PERCENTAGE"
      notification_type          = "FORECASTED"
      subscriber_sns_topic_arns  = local.topic_arn != null ? [local.topic_arn] : []
      subscriber_email_addresses = []
    }
  }
}

# ---- auto kill-switch: budget final threshold -> dedicated topic -> Lambda ----

resource "aws_sns_topic" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  name              = "${var.name}-killswitch"
  kms_master_key_id = var.alerts_kms_key_id != "" ? var.alerts_kms_key_id : null
  tags              = local.common_tags
}

resource "aws_sns_topic_policy" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  arn = aws_sns_topic.killswitch[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowBudgetsPublish"
      Effect    = "Allow"
      Principal = { Service = "budgets.amazonaws.com" }
      Action    = "sns:Publish"
      Resource  = aws_sns_topic.killswitch[0].arn
    }]
  })
}

data "archive_file" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/killswitch/index.py"
  output_path = "${path.module}/lambda/killswitch.zip"
}

resource "aws_iam_role" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  name = "${var.name}-killswitch-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

# least privilege: the Lambda may only put a policy on THIS role, plus logs + DLQ.
resource "aws_iam_role_policy" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  name = "contain-ai-role"
  role = aws_iam_role.killswitch[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ContainTargetRoleOnly"
        Effect   = "Allow"
        Action   = ["iam:PutRolePolicy"]
        Resource = local.role_arn
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.killswitch[0].arn}:*"
      },
      {
        Sid      = "DeadLetter"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.killswitch_dlq[0].arn
      },
    ]
  })
}

# containment must never fail silently: failed invocations land here for forensics...
resource "aws_sqs_queue" "killswitch_dlq" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  name                      = "${var.name}-killswitch-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true
  tags                      = local.common_tags
}

# ...and any Lambda error pages the alerts topic immediately.
resource "aws_cloudwatch_metric_alarm" "killswitch_errors" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  alarm_name          = "${var.name}-killswitch-errors"
  alarm_description   = "The AI containment Lambda failed - the role may NOT be contained. Investigate now."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { FunctionName = aws_lambda_function.killswitch[0].function_name }
  alarm_actions       = local.topic_arn != null ? [local.topic_arn] : []
  tags                = local.common_tags
}

resource "aws_cloudwatch_log_group" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  name              = "/aws/lambda/${var.name}-killswitch"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_function" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  function_name    = "${var.name}-killswitch"
  role             = aws_iam_role.killswitch[0].arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.killswitch[0].output_path
  source_code_hash = data.archive_file.killswitch[0].output_base64sha256
  timeout          = 30
  tags             = local.common_tags

  depends_on = [aws_cloudwatch_log_group.killswitch]

  dead_letter_config {
    target_arn = aws_sqs_queue.killswitch_dlq[0].arn
  }

  environment {
    variables = {
      TARGET_ROLE           = var.name
      EMERGENCY_POLICY_NAME = local.emergency_policy_name
    }
  }
}

resource "aws_sns_topic_subscription" "killswitch" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  topic_arn = aws_sns_topic.killswitch[0].arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.killswitch[0].arn
}

resource "aws_lambda_permission" "killswitch_from_sns" {
  count = local.create && var.enable_budget_killswitch ? 1 : 0

  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.killswitch[0].function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.killswitch[0].arn
}
