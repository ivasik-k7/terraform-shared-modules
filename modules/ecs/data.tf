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

data "aws_ebs_encryption_by_default" "current" {
  count = length(local.managed_instances) > 0 ? 1 : 0
}

# Keyed by capacity provider, so a profile ARN unknown at plan still plans.
data "aws_iam_instance_profile" "managed_instances" {
  for_each = local.supplied_instance_profile

  name = each.value
}
