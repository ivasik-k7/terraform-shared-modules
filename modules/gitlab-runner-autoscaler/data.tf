# Count-gated on create; locals coalesce the results so ARN strings still
# build under create = false.

data "aws_partition" "current" {
  count = local.create ? 1 : 0
}

data "aws_region" "current" {
  count = local.create ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.create ? 1 : 0
}

# Looked up whenever the module creates anything, so no pool can end up
# without its S3 rule: ECR serves image layers from S3.
data "aws_ec2_managed_prefix_list" "s3" {
  count = local.create && var.s3_prefix_list_id == "" ? 1 : 0

  name = "com.amazonaws.${local.region}.s3"
}
