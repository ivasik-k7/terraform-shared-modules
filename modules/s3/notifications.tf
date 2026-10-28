resource "terraform_data" "notification_dependencies" {
  count = local.create && local.notifications_on ? 1 : 0

  input = var.notification_dependencies
}

# PutBucketNotificationConfiguration replaces the whole configuration and sends a test message to each destination.
# https://docs.aws.amazon.com/AmazonS3/latest/API/API_PutBucketNotificationConfiguration.html
resource "aws_s3_bucket_notification" "this" {
  count = local.create && local.notifications_on ? 1 : 0

  bucket      = aws_s3_bucket.this[0].id
  eventbridge = var.notifications.eventbridge

  dynamic "topic" {
    for_each = var.notifications.topics
    content {
      id            = topic.key
      topic_arn     = topic.value.arn
      events        = topic.value.events
      filter_prefix = topic.value.prefix != "" ? topic.value.prefix : null
      filter_suffix = topic.value.suffix != "" ? topic.value.suffix : null
    }
  }

  dynamic "queue" {
    for_each = var.notifications.queues
    content {
      id            = queue.key
      queue_arn     = queue.value.arn
      events        = queue.value.events
      filter_prefix = queue.value.prefix != "" ? queue.value.prefix : null
      filter_suffix = queue.value.suffix != "" ? queue.value.suffix : null
    }
  }

  dynamic "lambda_function" {
    for_each = var.notifications.lambda_functions
    content {
      id                  = lambda_function.key
      lambda_function_arn = lambda_function.value.arn
      events              = lambda_function.value.events
      filter_prefix       = lambda_function.value.prefix != "" ? lambda_function.value.prefix : null
      filter_suffix       = lambda_function.value.suffix != "" ? lambda_function.value.suffix : null
    }
  }

  depends_on = [terraform_data.notification_dependencies]
}
