# Active attribution: EventBridge watches CloudTrail for high-risk actions taken
# by the AI role (and, if break-glass is enabled, every assumption of it) and
# pushes them to SNS in near real time. Recordable attribution -> watched.

resource "aws_cloudwatch_event_rule" "high_risk" {
  count = local.create && var.enable_alerting ? 1 : 0

  name        = "${var.name}-high-risk"
  description = "High-risk API calls made by the AI agent role."
  tags        = local.common_tags

  event_pattern = jsonencode({
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = var.high_risk_event_names
      userIdentity = {
        sessionContext = {
          sessionIssuer = {
            arn = [local.role_arn]
          }
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "high_risk" {
  count = local.create && var.enable_alerting ? 1 : 0

  rule      = aws_cloudwatch_event_rule.high_risk[0].name
  target_id = "sns"
  arn       = local.topic_arn

  input_transformer {
    input_paths = {
      actor  = "$.detail.userIdentity.sessionContext.sourceIdentity"
      event  = "$.detail.eventName"
      region = "$.detail.awsRegion"
      time   = "$.detail.eventTime"
    }
    input_template = "\"[AI HIGH-RISK] <actor> ran <event> in <region> at <time> (role ${var.name})\""
  }
}

# alert on every break-glass assumption - elevated access must never be silent.
resource "aws_cloudwatch_event_rule" "break_glass_assumed" {
  count = local.create && var.enable_alerting && var.enable_break_glass ? 1 : 0

  name        = "${var.name}-breakglass-assumed"
  description = "The break-glass role was assumed."
  tags        = local.common_tags

  event_pattern = jsonencode({
    source        = ["aws.sts"]
    "detail-type" = ["AWS API Call via CloudTrail"]
    detail = {
      eventName = ["AssumeRole"]
      requestParameters = {
        roleArn = [one(aws_iam_role.break_glass[*].arn)]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "break_glass_assumed" {
  count = local.create && var.enable_alerting && var.enable_break_glass ? 1 : 0

  rule      = aws_cloudwatch_event_rule.break_glass_assumed[0].name
  target_id = "sns"
  arn       = local.topic_arn

  input_transformer {
    input_paths = {
      actor  = "$.detail.userIdentity.principalId"
      time   = "$.detail.eventTime"
      source = "$.detail.sourceIPAddress"
    }
    input_template = "\"[BREAK-GLASS ASSUMED] ${var.name}-breakglass assumed by <actor> from <source> at <time>\""
  }
}
