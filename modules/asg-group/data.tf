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

# Resolved at plan, so the launch template pins an AMI ID. Resolving at launch
# (resolve:ssm:) rules out instance refresh rollback and skip matching, warm
# pools and attribute-based instance selection.
# https://docs.aws.amazon.com/autoscaling/ec2/userguide/using-systems-manager-parameters.html
data "aws_ssm_parameter" "ami" {
  count = local.create && var.ami == "" ? 1 : 0

  name = var.ami_ssm_parameter
}
