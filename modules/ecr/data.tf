# Only needed to build the repository policy's account-root principal, so skip
# them entirely when the module is a no-op (F6: true no-op when create = false).
data "aws_caller_identity" "current" {
  count = local.create ? 1 : 0
}

data "aws_partition" "current" {
  count = local.create ? 1 : 0
}
