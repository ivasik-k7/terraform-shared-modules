data "aws_caller_identity" "current" { count = local.create ? 1 : 0 }
data "aws_partition" "current" { count = local.create ? 1 : 0 }
