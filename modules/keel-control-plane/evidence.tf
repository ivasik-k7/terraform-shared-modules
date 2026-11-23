# Every event on the bus goes to an Object Lock bucket through Data Firehose.

module "evidence" {
  source = "../s3"
  create = local.create

  name                = local.evidence_bucket
  name_suffix         = "none"
  tags                = local.tags
  acknowledged_checks = [for c in var.acknowledged_checks : c if contains(["access_is_logged", "data_uses_a_customer_key"], c)]

  versioning  = true
  kms_key_arn = var.kms_key_arn
  object_lock = {
    enabled = true
    mode    = var.evidence.mode
    days    = var.evidence.retention_days
  }

  # Locked versions cannot be removed before their retention; these rules
  # remove them after it.
  default_lifecycle = {
    noncurrent_version_expiration_days = 1
    abort_incomplete_multipart_days    = 1
  }
  lifecycle_rules = {
    expire-evidence = { expiration_days = var.evidence.retention_days + 1 }
  }
}

resource "aws_cloudwatch_log_group" "evidence" {
  count = local.create ? 1 : 0

  name              = "/aws/kinesisfirehose/${var.name}-evidence"
  retention_in_days = 90
  kms_key_id        = var.kms_key_arn != "" ? var.kms_key_arn : null
  tags              = local.tags
}

resource "aws_cloudwatch_log_stream" "evidence" {
  count = local.create ? 1 : 0

  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.evidence[0].name
}

resource "aws_iam_role" "firehose" {
  count = local.create ? 1 : 0

  name_prefix          = "${var.name}-evidence-firehose-"
  description          = "Data Firehose writing Keel evidence to S3"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "sts:ExternalId" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "firehose" {
  count = local.create ? 1 : 0

  name = "deliver"
  role = aws_iam_role.firehose[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "Deliver"
          Effect   = "Allow"
          Action   = ["s3:AbortMultipartUpload", "s3:GetBucketLocation", "s3:GetObject", "s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:PutObject"]
          Resource = [local.evidence_bucket_arn, "${local.evidence_bucket_arn}/*"]
        },
        {
          Sid      = "Log"
          Effect   = "Allow"
          Action   = ["logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.evidence[0].arn}:*"
        },
      ],
      var.kms_key_arn == "" ? [] : [{
        Sid       = "Encrypt"
        Effect    = "Allow"
        Action    = ["kms:GenerateDataKey", "kms:Decrypt"]
        Resource  = var.kms_key_arn
        Condition = { StringEquals = { "kms:ViaService" = "s3.${local.region}.amazonaws.com" } }
      }],
    )
  })
}

resource "aws_kinesis_firehose_delivery_stream" "evidence" {
  count = local.create ? 1 : 0

  name        = "${var.name}-evidence"
  destination = "extended_s3"
  tags        = local.tags

  server_side_encryption {
    enabled  = true
    key_type = var.kms_key_arn != "" ? "CUSTOMER_MANAGED_CMK" : "AWS_OWNED_CMK"
    key_arn  = var.kms_key_arn != "" ? var.kms_key_arn : null
  }

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose[0].arn
    bucket_arn          = local.evidence_bucket_arn
    prefix              = "events/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy}/!{timestamp:MM}/!{timestamp:dd}/"
    buffering_interval  = 300
    buffering_size      = 5
    compression_format  = "GZIP"
    kms_key_arn         = var.kms_key_arn != "" ? var.kms_key_arn : null

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.evidence[0].name
      log_stream_name = aws_cloudwatch_log_stream.evidence[0].name
    }
  }

  depends_on = [aws_iam_role_policy.firehose, module.evidence]
}

resource "aws_iam_role" "events_to_firehose" {
  count = local.create ? 1 : 0

  name_prefix          = "${var.name}-evidence-events-"
  description          = "EventBridge putting Keel events into the evidence stream"
  permissions_boundary = var.permissions_boundary_arn != "" ? var.permissions_boundary_arn : null
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = { StringEquals = { "aws:SourceAccount" = local.account_id } }
    }]
  })
  tags = local.tags
}

resource "aws_iam_role_policy" "events_to_firehose" {
  count = local.create ? 1 : 0

  name = "put-records"
  role = aws_iam_role.events_to_firehose[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["firehose:PutRecord", "firehose:PutRecordBatch"], Resource = aws_kinesis_firehose_delivery_stream.evidence[0].arn }]
  })
}

# Every event carries "version": "0".
resource "aws_cloudwatch_event_rule" "evidence" {
  count = local.create ? 1 : 0

  name           = "${var.name}-evidence"
  description    = "Every Keel signal, kept as evidence"
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  event_pattern  = jsonencode({ version = ["0"] })
  tags           = local.tags
}

resource "aws_cloudwatch_event_target" "evidence" {
  count = local.create ? 1 : 0

  rule           = aws_cloudwatch_event_rule.evidence[0].name
  event_bus_name = aws_cloudwatch_event_bus.this[0].name
  arn            = aws_kinesis_firehose_delivery_stream.evidence[0].arn
  role_arn       = aws_iam_role.events_to_firehose[0].arn

  dead_letter_config {
    arn = aws_sqs_queue.dead_letters[0].arn
  }
}

# ---------------------------------------------------------------------------
# The control plane watches itself
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "undelivered" {
  count = local.create ? 1 : 0

  alarm_name          = "${var.name}-signals-undelivered"
  alarm_description   = "Keel signals EventBridge could not deliver to a topic or the evidence stream are waiting in ${var.name}-undelivered."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dead_letters[0].name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.severity["high"].arn]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "evidence_delivery" {
  count = local.create ? 1 : 0

  alarm_name          = "${var.name}-evidence-not-delivered"
  alarm_description   = "Data Firehose failed to write Keel evidence to S3. Look in its log group and under errors/ in the bucket."
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToS3.Success"
  dimensions          = { DeliveryStreamName = aws_kinesis_firehose_delivery_stream.evidence[0].name }
  statistic           = "Minimum"
  period              = 900
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.severity["high"].arn]
  tags                = local.tags
}
