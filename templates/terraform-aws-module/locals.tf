locals {
  create = var.create

  # Module keys last, so a caller's tags cannot override them.
  module_tags = {
    "ManagedBy" = "Terraform"
    "Module"    = "log-group"
  }
  common_tags = merge(var.tags, local.module_tags)

  # Placeholders so ARN expressions still evaluate when create = false.
  partition  = coalesce(one(data.aws_partition.current[*].partition), "aws")
  region     = try(split(".", one(data.aws_region.current[*].endpoint))[1], "us-east-1")
  account_id = coalesce(one(data.aws_caller_identity.current[*].account_id), "000000000000")

  acknowledged = toset(var.acknowledged_checks)

  # Built, not read from the resource, so contracts are known in the first plan.
  log_group_arn = "arn:${local.partition}:logs:${local.region}:${local.account_id}:log-group:${var.name}"

  # A key must be in the log group's region; another region fails at apply.
  key_in_another_region = var.kms_key_arn == "" ? false : !strcontains(var.kms_key_arn, ":${local.region}:")
}
