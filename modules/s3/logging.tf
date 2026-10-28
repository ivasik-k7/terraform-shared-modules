resource "aws_s3_bucket_logging" "this" {
  count = local.create && var.access_logging.enabled ? 1 : 0

  bucket        = aws_s3_bucket.this[0].id
  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix != "" ? var.access_logging.target_prefix : "${local.bucket_name}/"

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = var.access_logging.partition_date_source
    }
  }
}
