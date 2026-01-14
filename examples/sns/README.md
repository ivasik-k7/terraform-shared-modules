# SNS Basic Example

This example demonstrates a basic SNS topic configuration with email subscription and custom HTML message templates.

## Features

- Standard SNS topic
- Email subscription
- Custom HTML welcome message template
- Alert message template
- Free tier optimized (no KMS encryption, no delivery logging)

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

The example creates:
- SNS topic: `archon-hub-dev-notifications`
- Email subscription (requires confirmation)
- Message templates for welcome and alert messages

## Outputs

- `topic_arn` - The ARN of the SNS topic
- `topic_name` - The name of the SNS topic
- `subscription_arns` - List of subscription ARNs

## Notes

- Email subscriptions require manual confirmation
- Message templates are stored as variables (not used by SNS directly)
- No encryption to stay within free tier
- No delivery status logging to avoid CloudWatch costs