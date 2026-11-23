# The cache bucket. Objects are disposable: unversioned, expired after
# cache.expiration_days, and deleted with the bucket.
module "cache" {
  source = "../s3"
  create = local.cache_creates_bucket

  name                = local.cache_bucket
  name_suffix         = "none"
  tags                = local.tags
  acknowledged_checks = local.cache_acknowledged

  versioning       = false
  force_destroy    = true
  kms_key_arn      = var.kms_key_arn
  vpc_endpoint_ids = var.cache.vpc_endpoint_ids

  default_lifecycle = {
    noncurrent_version_expiration_days = 1
    abort_incomplete_multipart_days    = 1
  }
  lifecycle_rules = {
    expire-cache = { expiration_days = var.cache.expiration_days }
  }
}
