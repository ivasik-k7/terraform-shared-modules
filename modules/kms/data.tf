data "aws_partition" "current" {
  count = local.create ? 1 : 0
}

data "aws_region" "current" {
  count = local.create ? 1 : 0
}

data "aws_caller_identity" "current" {
  count = local.create ? 1 : 0
}

data "aws_iam_session_context" "deployer" {
  count = local.create && var.detect_deployer && length(var.deployers) == 0 ? 1 : 0
  arn   = data.aws_caller_identity.current[0].arn
}

data "aws_kms_public_key" "this" {
  for_each = local.create ? { for k, v in local.keys : k => v if v.enabled ? contains(["sign", "agreement", "asymmetric_encrypt"], local.key_kind[k]) : false } : {}
  key_id   = local.key_id[each.key]
}
