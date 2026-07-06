# Scheduled daily digest of the AI role's activity -> SNS.

data "archive_file" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  type        = "zip"
  source_file = "${path.module}/lambda/digest/index.py"
  output_path = "${path.module}/lambda/digest.zip"
}

resource "aws_iam_role" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  name = "${var.name}-digest-lambda"
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

resource "aws_iam_role_policy" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  name = "read-trail-publish-sns"
  role = aws_iam_role.digest[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      # Lake SQL when an event data store is provided, LookupEvents fallback otherwise
      var.digest_event_data_store_arn != "" ? [
        {
          Sid      = "LakeQuery"
          Effect   = "Allow"
          Action   = ["cloudtrail:StartQuery", "cloudtrail:DescribeQuery", "cloudtrail:GetQueryResults"]
          Resource = var.digest_event_data_store_arn
        }
        ] : [
        {
          Sid      = "LookupTrail"
          Effect   = "Allow"
          Action   = ["cloudtrail:LookupEvents"]
          Resource = "*"
        }
      ],
      [
        {
          Sid      = "Publish"
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = local.topic_arn
        },
        {
          Sid      = "Logs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.digest[0].arn}:*"
        },
      ],
    )
  })
}

resource "aws_cloudwatch_log_group" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  name              = "/aws/lambda/${var.name}-digest"
  retention_in_days = var.lambda_log_retention_days
  tags              = local.common_tags
}

resource "aws_lambda_function" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  function_name    = "${var.name}-digest"
  role             = aws_iam_role.digest[0].arn
  runtime          = "python3.12"
  handler          = "index.handler"
  filename         = data.archive_file.digest[0].output_path
  source_code_hash = data.archive_file.digest[0].output_base64sha256
  timeout          = 120
  tags             = local.common_tags

  depends_on = [aws_cloudwatch_log_group.digest]

  environment {
    variables = {
      ROLE_NAME            = var.name
      TOPIC_ARN            = local.topic_arn
      EVENT_DATA_STORE_ARN = var.digest_event_data_store_arn
    }
  }
}

resource "aws_cloudwatch_event_rule" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  name                = "${var.name}-digest-schedule"
  description         = "Daily AI-activity digest trigger."
  schedule_expression = var.digest_schedule
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "digest" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  rule      = aws_cloudwatch_event_rule.digest[0].name
  target_id = "lambda"
  arn       = aws_lambda_function.digest[0].arn
}

resource "aws_lambda_permission" "digest_from_events" {
  count = local.create && var.enable_daily_digest ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.digest[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.digest[0].arn
}
