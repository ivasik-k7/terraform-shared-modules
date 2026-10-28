resource "aws_kms_key" "data" {
  description = "orders data"
}

resource "aws_kms_key" "replica" {
  description = "orders replica"
}

resource "aws_s3_bucket" "dr" {
  bucket = "orders-dr-example"
}

resource "aws_sns_topic" "events" {
  name = "orders-events"
}

resource "aws_iam_role" "reader" {
  name               = "orders-reader"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "ec2.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

module "bucket" {
  source = "../../.."

  name           = "orders-data"
  kms_key_arn    = aws_kms_key.data.arn
  access_logging = { target_bucket = "central-logs-111122223333-eu-west-2" }

  grants = {
    reader = { principals = [aws_iam_role.reader.arn], access = "read" }
  }

  replication = {
    rules = {
      dr = { destination_bucket_arn = aws_s3_bucket.dr.arn, replica_kms_key_arn = aws_kms_key.replica.arn, replication_time_control = true }
    }
  }

  notifications = {
    topics = { events = { arn = aws_sns_topic.events.arn, events = ["s3:ObjectCreated:*"] } }
  }

  inventory = {
    weekly = { destination_bucket_arn = aws_s3_bucket.dr.arn }
  }

  acknowledged_checks = ["data_uses_a_customer_key"]
}

resource "aws_s3_bucket" "logs" {
  bucket = "orders-logs-example"
}

resource "aws_iam_role" "replication" {
  name               = "orders-raw-replication"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "s3.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}

resource "aws_sqs_queue" "ingest" {
  name = "orders-raw-ingest"
}

resource "aws_sqs_queue_policy" "ingest" {
  queue_url = aws_sqs_queue.ingest.id
  policy    = jsonencode({ Version = "2012-10-17", Statement = [jsondecode(module.raw.notification_destination_requirements.queues["ingest"])] })
}

module "raw" {
  source = "../../.."

  name           = "orders-raw"
  access_logging = { target_bucket = aws_s3_bucket.logs.id }

  replication = {
    create_role = false
    role_arn    = aws_iam_role.replication.arn
    rules = {
      dr = { destination_bucket_arn = aws_s3_bucket.dr.arn, replication_time_control = true }
    }
  }

  notifications = {
    queues = { ingest = { arn = aws_sqs_queue.ingest.arn, events = ["s3:ObjectCreated:*"] } }
  }
  notification_dependencies = [aws_sqs_queue_policy.ingest.id]

  acknowledged_checks = ["data_uses_a_customer_key"]
}
