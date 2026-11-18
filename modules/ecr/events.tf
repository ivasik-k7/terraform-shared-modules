# Failures that leave every apply green: an image with critical findings, a
# replication or a cache sync that did not succeed.
# https://docs.aws.amazon.com/AmazonECR/latest/userguide/ecr-eventbridge.html

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name          = "${var.name}-ecr-${each.key}"
  description   = each.value.description
  event_pattern = each.value.pattern

  tags = local.common_tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "sns"
  arn       = var.sns_topic_arn
}
