# REGIONAL scope only: attach the ACL to ALB / API Gateway stage / AppSync /
# Cognito by ARN. CloudFront does NOT use this - set web_acl_id on the
# distribution to the web_acl_arn output instead (a variable already validated
# to forbid this list under CLOUDFRONT scope).

resource "aws_wafv2_web_acl_association" "this" {
  for_each = local.create && var.scope == "REGIONAL" ? toset(var.associate_resource_arns) : toset([])

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
