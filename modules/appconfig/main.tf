# app -> environments -> profiles -> deployments. every change rides a
# deployment strategy, nothing is edited in place. flag json is rendered in
# locals from typed HCL.
# cost: appconfig bills per config request (~$0.20/1M after free tier); the
# resources themselves are free.

resource "aws_appconfig_application" "this" {
  count = local.create ? 1 : 0

  name        = var.name
  description = var.description
  tags        = local.common_tags
}
