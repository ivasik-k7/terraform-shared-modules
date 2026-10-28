resource "aws_s3_bucket" "this" {
  count = local.create ? 1 : 0

  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = local.common_tags

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "the bucket name ${local.bucket_name} is ${length(local.bucket_name)} characters; S3 allows 63. ${local.suffixed ? "The account and region suffix takes ${length(local.bucket_name) - length(var.name)}: shorten name to ${63 - (length(local.bucket_name) - length(var.name))} characters." : "Shorten name."}"
    }

    precondition {
      condition     = !local.key_in_another_region
      error_message = "kms_key_arn is in another region than the bucket (${local.region}); S3 encrypts only with keys in its own region. Use a key, or a multi-Region replica, in ${local.region}."
    }

    precondition {
      condition     = var.encryption.dsse ? local.uses_kms : true
      error_message = "encryption.dsse needs kms_key_arn: DSSE-KMS encrypts with a KMS key."
    }

    precondition {
      condition     = local.public_access_relaxed ? var.allow_public_access : true
      error_message = "public_access_block turns protections off without allow_public_access = true. Serve public content through CloudFront (cloudfront_distribution_arns) instead."
    }

    precondition {
      condition     = local.replication_on ? var.versioning : true
      error_message = "replication needs versioning on this bucket (and on each destination)."
    }

    precondition {
      condition     = var.object_lock.enabled ? var.versioning : true
      error_message = "Object Lock needs versioning, and once on, versioning cannot be suspended."
    }

    precondition {
      condition     = length(var.access_log_sources) == 0 ? true : !local.uses_kms
      error_message = "a server access log bucket must use SSE-S3: S3 would deliver logs encrypted with a key nobody can read. Leave kms_key_arn empty for this bucket."
    }

    precondition {
      condition     = length(var.access_log_sources) == 0 ? true : !(var.object_lock.enabled || var.requester_pays)
      error_message = "S3 cannot deliver server access logs to a bucket with Object Lock or Requester Pays."
    }

    precondition {
      condition     = var.access_logging.target_bucket != local.bucket_name
      error_message = "access_logging.target_bucket is this bucket: every log delivery would log itself, without end."
    }

    precondition {
      # OAC needs Bucket owner enforced, or Bucket owner preferred where ACLs are required.
      # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html
      condition     = length(var.cloudfront_distribution_arns) == 0 ? true : var.object_ownership != "ObjectWriter"
      error_message = "CloudFront Origin Access Control needs object_ownership BucketOwnerEnforced (or BucketOwnerPreferred where ACLs are still required)."
    }

    precondition {
      # Bucket policies are limited to 20 KB.
      # https://docs.aws.amazon.com/AmazonS3/latest/userguide/add-bucket-policy.html
      condition     = length(local.bucket_policy) <= 20480
      error_message = "the bucket policy is ${length(local.bucket_policy)} characters, over S3's 20 KB. Fewer grants or prefixes, or grant through IAM (output.read_policy_json)."
    }

    precondition {
      condition     = length([for r in values(var.replication.rules) : r if r.replica_kms_key_arn == ""]) == 0 ? true : !local.uses_kms
      error_message = "this bucket encrypts with kms_key_arn, and S3 does not replicate SSE-KMS objects unless the rule names a replica_kms_key_arn: these rules would replicate nothing: ${join(", ", [for k, r in var.replication.rules : k if r.replica_kms_key_arn == ""])}."
    }
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.this[0].id
  block_public_acls       = var.public_access_block.block_public_acls
  block_public_policy     = var.public_access_block.block_public_policy
  ignore_public_acls      = var.public_access_block.ignore_public_acls
  restrict_public_buckets = var.public_access_block.restrict_public_buckets
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.uses_kms ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.bucket_key
  }
}

resource "aws_s3_bucket_versioning" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  versioning_configuration {
    status = var.versioning ? "Enabled" : "Suspended"
  }
}

# PutObjectLockConfiguration enables Object Lock on an existing bucket.
# https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock-configure.html#object-lock-configure-existing-bucket
resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = local.create && var.object_lock.enabled ? 1 : 0

  bucket              = aws_s3_bucket.this[0].id
  object_lock_enabled = "Enabled"

  dynamic "rule" {
    for_each = var.object_lock.days + var.object_lock.years > 0 ? [1] : []
    content {
      default_retention {
        mode  = var.object_lock.mode
        days  = var.object_lock.days > 0 ? var.object_lock.days : null
        years = var.object_lock.years > 0 ? var.object_lock.years : null
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id
  policy = local.bucket_policy

  # With BlockPublicPolicy on, S3 rejects PutBucketPolicy for a public policy.
  # https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html
  depends_on = [aws_s3_bucket_public_access_block.this, aws_s3_bucket_ownership_controls.this]
}
