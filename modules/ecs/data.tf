# Count-gated on create; locals coalesce the results so ARN strings still
# build under create = false. The region is parsed from aws_region.endpoint:
# the one attribute both provider majors have without a deprecation warning.

data "aws_partition" "current" {
  count = local.create ? 1 : 0
}

data "aws_region" "current" {
  count = local.create ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.create ? 1 : 0
}
