# SNS (Simple Notification Service) Module

Production-grade Terraform module for deploying Amazon SNS topics with configuration options, delivery status logging, and subscription management.

## Features

- **Standard and FIFO Topics** - Support for both standard (high throughput) and FIFO (ordered delivery) topics
- **Delivery Logging** - Built-in delivery status logging for all supported protocols (HTTP/HTTPS, Lambda, SQS, Firehose, Mobile Push)
- **Flexible Subscriptions** - Support for all SNS protocols with advanced filtering and delivery policies
- **Encryption Support** - KMS encryption for messages at rest
- **Message Filtering** - Advanced message filtering with attribute and body-based filters
- **Dead Letter Queue Integration** - Subscription-level DLQ support for failed deliveries
- **Cross-Account Access** - Topic policies for cross-account publishing and subscription
- **Monitoring Ready** - CloudWatch integration and X-Ray tracing support

## Supported Protocols

- **SQS** - Queue-based messaging with optional raw message delivery
- **Lambda** - Direct function invocation with retry policies
- **HTTP/HTTPS** - Webhook delivery with configurable retry behavior
- **Email/Email-JSON** - Email notifications in text or JSON format
- **SMS** - Text message delivery
- **Mobile Push** - iOS, Android, and other mobile platform notifications
- **Firehose** - Stream delivery to data lakes and analytics services

## Quick Start

### Basic Standard Topic

```hcl
module "notifications" {
  source = "./modules/sns"

  name         = "user-notifications"
  display_name = "User Notifications"

  subscriptions = [
    {
      protocol = "email"
      endpoint = "admin@example.com"
    },
    {
      protocol = "sqs"
      endpoint = aws_sqs_queue.notifications.arn
      raw_message_delivery = true
    }
  ]

  tags = {
    Environment = "production"
    Service     = "notifications"
  }
}
```

### FIFO Topic with Content-Based Deduplication

```hcl
module "order_events" {
  source = "./modules/sns"

  name                        = "order-events"
  fifo_topic                  = true
  content_based_deduplication = true

  subscriptions = [
    {
      protocol = "sqs"
      endpoint = aws_sqs_queue.order_processing.arn
      filter_policy = jsonencode({
        event_type = ["order_created", "order_updated"]
        priority   = ["high", "critical"]
      })
    }
  ]

  tags = {
    Environment = "production"
    Service     = "orders"
  }
}
```

### Topic with Delivery Status Logging

```hcl
module "webhook_notifications" {
  source = "./modules/sns"

  name = "webhook-notifications"

  # Enable delivery status logging
  http_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  http_success_feedback_sample_rate = 100
  http_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn

  lambda_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  lambda_success_feedback_sample_rate = 10
  lambda_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn

  subscriptions = [
    {
      protocol = "https"
      endpoint = "https://api.example.com/webhooks/sns"
      delivery_policy = jsonencode({
        healthyRetryPolicy = {
          minDelayTarget     = 20
          maxDelayTarget     = 20
          numRetries         = 3
          numMaxDelayRetries = 0
          numMinDelayRetries = 0
          numNoDelayRetries  = 0
          backoffFunction    = "linear"
        }
      })
    },
    {
      protocol = "lambda"
      endpoint = aws_lambda_function.processor.arn
      redrive_policy = jsonencode({
        deadLetterTargetArn = aws_sqs_queue.dlq.arn
      })
    }
  ]

  tags = {
    Environment = "production"
    Service     = "webhooks"
  }
}
```

### Encrypted Topic with Cross-Account Access

```hcl
module "secure_alerts" {
  source = "./modules/sns"

  name              = "security-alerts"
  kms_master_key_id = aws_kms_key.sns.id

  topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountPublish"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::123456789012:root"
        }
        Action   = "sns:Publish"
        Resource = "*"
        Condition = {
          StringEquals = {
            "sns:Protocol" = ["sqs", "lambda"]
          }
        }
      }
    ]
  })

  subscriptions = [
    {
      protocol = "sqs"
      endpoint = aws_sqs_queue.security_queue.arn
      filter_policy = jsonencode({
        severity = ["high", "critical"]
        source   = ["cloudtrail", "guardduty", "securityhub"]
      })
      filter_policy_scope = "MessageAttributes"
    }
  ]

  tags = {
    Environment = "production"
    Service     = "security"
    Compliance  = "required"
  }
}
```

### Mobile Push Notifications

```hcl
module "mobile_push" {
  source = "./modules/sns"

  name = "mobile-notifications"

  # Enable mobile push delivery logging
  application_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  application_success_feedback_sample_rate = 100
  application_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn

  subscriptions = [
    {
      protocol = "application"
      endpoint = aws_sns_platform_application.ios.arn
      filter_policy = jsonencode({
        platform = ["ios"]
        user_type = ["premium", "enterprise"]
      })
    },
    {
      protocol = "application"
      endpoint = aws_sns_platform_application.android.arn
      filter_policy = jsonencode({
        platform = ["android"]
        user_type = ["premium", "enterprise"]
      })
    }
  ]

  tags = {
    Environment = "production"
    Service     = "mobile"
  }
}
```

## Advanced Configuration

### Message Filtering

SNS supports two types of message filtering:

#### Attribute-Based Filtering (Default)

```hcl
subscriptions = [
  {
    protocol = "sqs"
    endpoint = aws_sqs_queue.high_priority.arn
    filter_policy = jsonencode({
      priority = ["high", "critical"]
      region   = ["us-east-1", "us-west-2"]
      event_type = {
        "anything-but" = ["test", "debug"]
      }
    })
    filter_policy_scope = "MessageAttributes"
  }
]
```

#### Message Body Filtering

```hcl
subscriptions = [
  {
    protocol = "lambda"
    endpoint = aws_lambda_function.processor.arn
    filter_policy = jsonencode({
      "user.type" = ["premium"]
      "order.total" = {
        "numeric" = [">", 100]
      }
    })
    filter_policy_scope = "MessageBody"
  }
]
```

### Custom Delivery Policies

```hcl
subscriptions = [
  {
    protocol = "https"
    endpoint = "https://api.example.com/webhook"
    delivery_policy = jsonencode({
      healthyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numMinDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = "linear"
      }
      sicklyRetryPolicy = {
        minDelayTarget     = 20
        maxDelayTarget     = 20
        numRetries         = 3
        numMaxDelayRetries = 0
        numMinDelayRetries = 0
        numNoDelayRetries  = 0
        backoffFunction    = "linear"
      }
      throttlePolicy = {
        maxReceivesPerSecond = 10
      }
    })
  }
]
```

## Requirements

| Name      | Version  |
| --------- | -------- |
| terraform | >= 1.5.0 |
| aws       | ~> 5.0   |

## Providers

| Name | Version |
| ---- | ------- |
| aws  | ~> 5.0  |

## Resources

| Name                                                                                                                                  | Type     |
| ------------------------------------------------------------------------------------------------------------------------------------- | -------- |
| [aws_sns_topic.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic)                           | resource |
| [aws_sns_topic_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy)             | resource |
| [aws_sns_topic_subscription.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_subscription) | resource |

## Inputs

| Name                        | Description                                                                                      | Type           | Default | Required |
| --------------------------- | ------------------------------------------------------------------------------------------------ | -------------- | ------- | :------: |
| name                        | The name of the SNS topic. For FIFO topics, '.fifo' suffix is automatically added if not present | `string`       | n/a     |   yes    |
| display_name                | The display name for the SNS topic (used in SMS messages)                                        | `string`       | `null`  |    no    |
| fifo_topic                  | Whether to create a FIFO (First-In-First-Out) topic instead of standard topic                    | `bool`         | `false` |    no    |
| content_based_deduplication | Enables content-based deduplication for FIFO topics. Requires fifo_topic = true                  | `bool`         | `false` |    no    |
| delivery_policy             | The JSON delivery policy for the topic. Controls retry behavior and delivery throttling          | `string`       | `null`  |    no    |
| kms_master_key_id           | The ID of an AWS-managed CMK, customer-managed CMK, or KMS key alias for encryption              | `string`       | `null`  |    no    |
| topic_policy                | The JSON IAM policy document for the topic. Controls who can perform what actions on the topic   | `string`       | `null`  |    no    |
| subscriptions               | List of subscription configurations for the topic                                                | `list(object)` | `[]`    |    no    |
| signature_version           | The signature version corresponds to the hashing algorithm used while creating the signature     | `number`       | `null`  |    no    |
| tracing_config              | Tracing mode of an Amazon SNS topic. Valid values: PassThrough, Active                           | `string`       | `null`  |    no    |
| tags                        | A map of tags to apply to all resources                                                          | `map(string)`  | `{}`    |    no    |

### Delivery Status Logging Variables

| Name                                     | Description                                                                 | Type     | Default | Required |
| ---------------------------------------- | --------------------------------------------------------------------------- | -------- | ------- | :------: |
| http_success_feedback_role_arn           | IAM role ARN for successful HTTP/HTTPS delivery feedback                    | `string` | `null`  |    no    |
| http_success_feedback_sample_rate        | Sample rate percentage (0-100) for successful HTTP/HTTPS delivery feedback  | `number` | `null`  |    no    |
| http_failure_feedback_role_arn           | IAM role ARN for failed HTTP/HTTPS delivery feedback                        | `string` | `null`  |    no    |
| lambda_success_feedback_role_arn         | IAM role ARN for successful Lambda delivery feedback                        | `string` | `null`  |    no    |
| lambda_success_feedback_sample_rate      | Sample rate percentage (0-100) for successful Lambda delivery feedback      | `number` | `null`  |    no    |
| lambda_failure_feedback_role_arn         | IAM role ARN for failed Lambda delivery feedback                            | `string` | `null`  |    no    |
| sqs_success_feedback_role_arn            | IAM role ARN for successful SQS delivery feedback                           | `string` | `null`  |    no    |
| sqs_success_feedback_sample_rate         | Sample rate percentage (0-100) for successful SQS delivery feedback         | `number` | `null`  |    no    |
| sqs_failure_feedback_role_arn            | IAM role ARN for failed SQS delivery feedback                               | `string` | `null`  |    no    |
| firehose_success_feedback_role_arn       | IAM role ARN for successful Firehose delivery feedback                      | `string` | `null`  |    no    |
| firehose_success_feedback_sample_rate    | Sample rate percentage (0-100) for successful Firehose delivery feedback    | `number` | `null`  |    no    |
| firehose_failure_feedback_role_arn       | IAM role ARN for failed Firehose delivery feedback                          | `string` | `null`  |    no    |
| application_success_feedback_role_arn    | IAM role ARN for successful mobile push delivery feedback                   | `string` | `null`  |    no    |
| application_success_feedback_sample_rate | Sample rate percentage (0-100) for successful mobile push delivery feedback | `number` | `null`  |    no    |
| application_failure_feedback_role_arn    | IAM role ARN for failed mobile push delivery feedback                       | `string` | `null`  |    no    |

### Subscription Object Structure

```hcl
subscriptions = [
  {
    protocol               = string           # Required: sqs, sms, email, email-json, http, https, application, lambda, firehose
    endpoint               = string           # Required: The endpoint to deliver messages to
    confirmation_timeout   = number           # Optional: Timeout for subscription confirmation (1-1440 minutes)
    endpoint_auto_confirms = bool             # Optional: Whether the endpoint auto-confirms subscriptions
    raw_message_delivery   = bool             # Optional: Whether to deliver raw messages (SQS/HTTP only)
    filter_policy          = string           # Optional: JSON filter policy for message filtering
    filter_policy_scope    = string           # Optional: "MessageAttributes" or "MessageBody"
    delivery_policy        = string           # Optional: JSON delivery policy for retry behavior
    redrive_policy         = string           # Optional: JSON redrive policy for DLQ
    subscription_role_arn  = string           # Optional: IAM role for cross-account subscriptions
  }
]
```

## Outputs

| Name                        | Description                                     |
| --------------------------- | ----------------------------------------------- |
| topic_id                    | The ARN of the SNS topic                        |
| topic_arn                   | The ARN of the SNS topic                        |
| topic_name                  | The name of the SNS topic                       |
| topic_display_name          | The display name of the SNS topic               |
| topic_owner                 | The AWS Account ID of the SNS topic owner       |
| fifo_topic                  | Whether the topic is a FIFO topic               |
| content_based_deduplication | Whether content-based deduplication is enabled  |
| kms_master_key_id           | The KMS master key ID used for encryption       |
| subscription_arns           | List of ARNs of the topic subscriptions         |
| subscription_count          | Number of subscriptions created for the topic   |
| subscriptions               | List of subscription details                    |
| topic_info                  | Topic information for integration               |
| topic_arn_for_policy        | The topic ARN formatted for use in IAM policies |

## IAM Permissions

### Required Permissions for Terraform

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "sns:CreateTopic",
        "sns:DeleteTopic",
        "sns:GetTopicAttributes",
        "sns:SetTopicAttributes",
        "sns:ListTopics",
        "sns:TagResource",
        "sns:UntagResource",
        "sns:ListTagsForResource",
        "sns:Subscribe",
        "sns:Unsubscribe",
        "sns:GetSubscriptionAttributes",
        "sns:SetSubscriptionAttributes",
        "sns:ListSubscriptions",
        "sns:ListSubscriptionsByTopic"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": ["kms:Describe*", "kms:List*"],
      "Resource": "*"
    }
  ]
}
```

### SNS Delivery Status Logging Role

```hcl
resource "aws_iam_role" "sns_feedback" {
  name = "sns-delivery-status-logging"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "sns.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sns_feedback" {
  role       = aws_iam_role.sns_feedback.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/SNSLogsDeliveryRolePolicy"
}
```

## Best Practices

### Security

- **Enable Encryption**: Use KMS encryption for sensitive data
- **Least Privilege**: Apply restrictive topic policies
- **Cross-Account Access**: Use condition keys in policies
- **Monitor Access**: Enable CloudTrail logging for SNS API calls

### Performance

- **Message Filtering**: Use filter policies to reduce unnecessary deliveries
- **Batch Operations**: Use batch publishing for high-volume scenarios
- **FIFO Considerations**: Use FIFO topics only when ordering is critical
- **Delivery Policies**: Configure appropriate retry policies

### Cost Optimization

- **Filter Early**: Apply filters to reduce delivery costs
- **Sample Logging**: Use appropriate sample rates for delivery status logging
- **Monitor Usage**: Track message volumes and delivery patterns
- **Cleanup**: Remove unused subscriptions and topics

### Monitoring

- **CloudWatch Metrics**: Monitor delivery success rates and latencies
- **Delivery Status Logging**: Enable for critical subscriptions
- **X-Ray Tracing**: Use for distributed tracing
- **Alarms**: Set up alerts for delivery failures

## Troubleshooting

### Common Issues

**Subscription Not Confirming**

- Check endpoint accessibility and auto-confirmation settings
- Verify confirmation timeout is sufficient
- Review endpoint logs for confirmation requests

**Messages Not Filtering**

- Validate filter policy JSON syntax
- Ensure message attributes match filter criteria
- Check filter policy scope (MessageAttributes vs MessageBody)

**Delivery Failures**

- Review delivery status logs
- Check endpoint health and accessibility
- Verify IAM permissions for cross-service delivery
- Configure appropriate retry policies

**FIFO Topic Issues**

- Ensure MessageGroupId is provided for FIFO topics
- Check deduplication settings and MessageDeduplicationId
- Verify .fifo suffix in topic name

### Debugging

Enable delivery status logging to troubleshoot delivery issues:

```hcl
module "debug_topic" {
  source = "./modules/sns"

  name = "debug-topic"

  http_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  http_success_feedback_sample_rate = 100
  http_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn

  lambda_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  lambda_success_feedback_sample_rate = 100
  lambda_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn

  sqs_success_feedback_role_arn    = aws_iam_role.sns_feedback.arn
  sqs_success_feedback_sample_rate = 100
  sqs_failure_feedback_role_arn    = aws_iam_role.sns_feedback.arn
}
```

## Examples

See the [examples](./examples/) directory for complete working examples:

- [Basic Topic](./examples/basic/)
- [FIFO Topic](./examples/fifo/)
- [Multi-Protocol Subscriptions](./examples/multi-protocol/)
- [Message Filtering](./examples/filtering/)
- [Cross-Account Access](./examples/cross-account/)
- [Mobile Push Notifications](./examples/mobile-push/)

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## License

This module is provided as-is for infrastructure management. Review licensing terms before use in commercial environments.
