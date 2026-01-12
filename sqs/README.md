# SQS Terraform Module

A Terraform module for provisioning AWS Simple Queue Service (SQS) with flexible configuration for standard and FIFO queues, dead letter queue handling, encryption, and access control.

## What This Module Does

- Creates standard or FIFO SQS queues with configurable message handling
- Optionally creates a Dead Letter Queue (DLQ) for handling failed messages
- Manages encryption with SQS-managed keys or custom KMS encryption
- Configures message visibility, retention, and delivery delays
- Supports long polling for efficient message retrieval
- Handles FIFO queue deduplication (content-based or explicit)
- Applies queue access policies for fine-grained access control
- Enables tagging across all resources

## Basic Usage

### Standard Queue (Minimal)

```hcl
module "sqs" {
  source = "./sqs"

  name = "my-queue"
}
```

### Standard Queue with DLQ

```hcl
module "sqs" {
  source = "./sqs"

  name         = "my-queue"
  create_dlq   = true
  max_receive_count = 3

  tags = {
    Environment = "production"
  }
}
```

### FIFO Queue with Deduplication

```hcl
module "sqs" {
  source = "./sqs"

  name                           = "my-queue"
  fifo_queue                     = true
  content_based_deduplication    = true
  deduplication_scope            = "messageGroup"
  fifo_throughput_limit          = "perMessageGroupId"

  create_dlq   = true
  max_receive_count = 5

  tags = {
    Environment = "production"
  }
}
```

### Queue with Custom KMS Encryption

```hcl
module "sqs" {
  source = "./sqs"

  name              = "my-queue"
  kms_master_key_id = aws_kms_key.sqs.id
  kms_data_key_reuse_period_seconds = 600

  tags = {
    Environment = "production"
  }
}
```

### Queue with Access Policy

```hcl
module "sqs" {
  source = "./sqs"

  name = "my-queue"

  queue_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = "arn:aws:sqs:*:*:my-queue"
        Condition = {
          ArnLike = {
            "aws:SourceArn" = aws_lambda_function.producer.arn
          }
        }
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}
```

## Input Variables

### Queue Identity

| Name   | Type        | Required | Default | Description                                                                          |
| ------ | ----------- | -------- | ------- | ------------------------------------------------------------------------------------ |
| `name` | string      | Yes      | N/A     | Queue name (1-80 characters). For FIFO queues, `.fifo` suffix is automatically added |
| `tags` | map(string) | No       | `{}`    | Tags applied to all resources                                                        |

### Queue Type

| Name                          | Type   | Default      | Description                                                                              |
| ----------------------------- | ------ | ------------ | ---------------------------------------------------------------------------------------- |
| `fifo_queue`                  | bool   | `false`      | Create a FIFO queue instead of standard                                                  |
| `content_based_deduplication` | bool   | `false`      | Enable content-based deduplication (FIFO only)                                           |
| `deduplication_scope`         | string | `"queue"`    | Deduplication scope: `messageGroup` or `queue` (FIFO only)                               |
| `fifo_throughput_limit`       | string | `"perQueue"` | Throughput limit: `perQueue` (300 msg/s) or `perMessageGroupId` (3000 msg/s) (FIFO only) |

### Message Handling

| Name                         | Type   | Default  | Description                                                         |
| ---------------------------- | ------ | -------- | ------------------------------------------------------------------- |
| `visibility_timeout_seconds` | number | `30`     | How long messages are hidden after retrieval (0-43200 seconds)      |
| `message_retention_seconds`  | number | `345600` | How long messages are retained (60-1209600 seconds, default 4 days) |
| `max_message_size`           | number | `262144` | Maximum message size in bytes (1024-262144, default 256 KB)         |
| `delay_seconds`              | number | `0`      | Delivery delay for all messages (0-900 seconds)                     |
| `receive_wait_time_seconds`  | number | `0`      | Long polling wait time (0-20 seconds)                               |

### Encryption

| Name                                | Type   | Default | Description                                                           |
| ----------------------------------- | ------ | ------- | --------------------------------------------------------------------- |
| `sqs_managed_sse_enabled`           | bool   | `true`  | Enable SQS-managed encryption (ignored if `kms_master_key_id` is set) |
| `kms_master_key_id`                 | string | `null`  | KMS key ID or ARN for custom encryption                               |
| `kms_data_key_reuse_period_seconds` | number | `300`   | KMS data key reuse period (60-86400 seconds)                          |

### Dead Letter Queue

| Name                            | Type   | Default   | Description                                                    |
| ------------------------------- | ------ | --------- | -------------------------------------------------------------- |
| `create_dlq`                    | bool   | `false`   | Create a Dead Letter Queue                                     |
| `max_receive_count`             | number | `5`       | Messages sent to DLQ after this many receive attempts (1-1440) |
| `dlq_message_retention_seconds` | number | `1209600` | DLQ message retention (60-1209600 seconds, default 14 days)    |
| `redrive_policy`                | string | `null`    | Custom redrive policy (auto-generated if `create_dlq` is true) |
| `redrive_allow_policy`          | string | `null`    | Allow other queues to use this queue as their DLQ              |

### Access Control

| Name           | Type   | Default | Description                               |
| -------------- | ------ | ------- | ----------------------------------------- |
| `queue_policy` | string | `null`  | JSON IAM policy document for queue access |

## Outputs

### Queue Identity

| Name         | Description               |
| ------------ | ------------------------- |
| `queue_id`   | The URL of the SQS queue  |
| `queue_url`  | The URL of the SQS queue  |
| `queue_arn`  | The ARN of the SQS queue  |
| `queue_name` | The name of the SQS queue |

### Queue Configuration

| Name                          | Description                                    |
| ----------------------------- | ---------------------------------------------- |
| `visibility_timeout_seconds`  | Configured visibility timeout                  |
| `message_retention_seconds`   | Configured retention period                    |
| `max_message_size`            | Configured maximum message size                |
| `delay_seconds`               | Configured message delay                       |
| `receive_wait_time_seconds`   | Configured long polling wait time              |
| `fifo_queue`                  | Whether queue is FIFO                          |
| `content_based_deduplication` | Whether content-based deduplication is enabled |
| `deduplication_scope`         | Deduplication scope (FIFO only)                |
| `fifo_throughput_limit`       | Throughput limit (FIFO only)                   |

### Encryption

| Name                                | Description                               |
| ----------------------------------- | ----------------------------------------- |
| `kms_master_key_id`                 | KMS key ID used for encryption, if any    |
| `sqs_managed_sse_enabled`           | Whether SQS-managed encryption is enabled |
| `kms_data_key_reuse_period_seconds` | KMS data key reuse period                 |

### Dead Letter Queue

| Name                | Description                          |
| ------------------- | ------------------------------------ |
| `dlq_id`            | URL of the DLQ, if created           |
| `dlq_url`           | URL of the DLQ, if created           |
| `dlq_arn`           | ARN of the DLQ, if created           |
| `dlq_name`          | Name of the DLQ, if created          |
| `max_receive_count` | Max receive count before DLQ routing |
| `dlq_created`       | Whether a DLQ was created            |

### Integration Outputs

| Name                   | Description                                                      |
| ---------------------- | ---------------------------------------------------------------- |
| `queue_info`           | Combined queue information (id, url, arn, name, fifo, encrypted) |
| `dlq_info`             | Combined DLQ information if created                              |
| `queue_endpoint`       | Queue URL for message producers                                  |
| `queue_arn_for_policy` | Queue ARN formatted for IAM policies                             |
| `dlq_arn_for_policy`   | DLQ ARN formatted for IAM policies                               |

## Common Patterns

### Lambda Event Source Mapping

```hcl
module "sqs" {
  source = "./sqs"

  name = "lambda-events"
  receive_wait_time_seconds = 20  # Long polling
  visibility_timeout_seconds = 300

  tags = {
    Environment = "production"
  }
}

resource "aws_lambda_event_source_mapping" "sqs" {
  event_source_arn = module.sqs.queue_arn
  function_name    = aws_lambda_function.processor.arn
  batch_size       = 10
}
```

### SNS to SQS Subscription

```hcl
module "sqs" {
  source = "./sqs"

  name = "sns-events"
  fifo_queue = true

  queue_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
        Action   = "sqs:SendMessage"
        Resource = aws_sqs_queue.this.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.events.arn
          }
        }
      }
    ]
  })

  tags = {
    Environment = "production"
  }
}

resource "aws_sns_topic_subscription" "sqs" {
  topic_arn = aws_sns_topic.events.arn
  protocol  = "sqs"
  endpoint  = module.sqs.queue_arn
}
```

### Cost Optimization with Visibility and Retention

```hcl
module "sqs" {
  source = "./sqs"

  name                      = "temp-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 3600  # 1 hour instead of 4 days

  tags = {
    Environment = "development"
    CostCenter  = "engineering"
  }
}
```

### High-Throughput FIFO Queue

```hcl
module "sqs" {
  source = "./sqs"

  name                     = "orders"
  fifo_queue               = true
  fifo_throughput_limit    = "perMessageGroupId"  # 3000 msg/s per group
  content_based_deduplication = true

  create_dlq = true
  max_receive_count = 3

  tags = {
    Environment = "production"
    Service     = "orders"
  }
}
```

### Audit and Compliance Queue with Custom Encryption

```hcl
module "sqs" {
  source = "./sqs"

  name              = "audit-logs"
  kms_master_key_id = aws_kms_key.audit.arn

  message_retention_seconds = 7776000  # 90 days for audit trail

  tags = {
    Environment = "production"
    Compliance  = "PCI-DSS"
    Encrypted   = "yes"
  }
}
```

## Important Notes

### Standard vs FIFO Queues

- **Standard**: Best throughput, at-least-once delivery, no ordering guarantee
- **FIFO**: Exactly-once delivery, strict ordering, lower throughput (300 or 3000 msg/s)

### Deduplication Modes (FIFO Only)

- **content-based**: AWS calculates SHA-256 hash of message body
- **explicit**: Messages must include a `MessageDeduplicationId` attribute

### Visibility Timeout

- Duration a message is hidden after consumer receives it
- Must be longer than consumer processing time
- Applies only to received messages, not queued messages

### Long Polling

- `receive_wait_time_seconds > 0` enables long polling
- Reduces empty responses and API costs
- Recommended for most use cases

### Message Retention

- Minimum 60 seconds (1 minute)
- Maximum 1,209,600 seconds (14 days)
- Messages deleted after this period regardless of processing status

### DLQ Configuration

- Max receive count should be proportional to queue visibility timeout
- DLQ retention typically longer than primary queue (audit trail)
- Monitor DLQ for application issues

### Encryption Options

1. **SQS-managed (default)** - AWS manages keys, no additional cost
2. **Custom KMS** - Full control, audit trail, additional KMS API costs

## Troubleshooting

### "InvalidParameterValue" on FIFO Attributes

- Ensure FIFO attributes are only set when `fifo_queue = true`
- The module automatically handles this, but verify variables

### Messages Not Being Processed

- Check visibility timeout isn't too high
- Verify queue policy allows consumer actions
- Enable long polling to reduce empty responses

### High Costs

- Reduce message retention if not needed
- Use long polling to batch API calls
- Consider consolidating multiple queues

### Messages Stuck in DLQ

- Check consumer logs for processing errors
- Increase `max_receive_count` if transient failures occur
- Verify DLQ is being monitored

## Integration with Other Services

- **Lambda**: Use `aws_lambda_event_source_mapping` resource
- **SNS**: Use `aws_sns_topic_subscription` with `sqs` protocol
- **Step Functions**: Reference queue ARN in state machine
- **CloudWatch**: Monitor `ApproximateNumberOfMessagesVisible` and `SentMessageCount`
- **EventBridge**: Use as event target for rule conditions
