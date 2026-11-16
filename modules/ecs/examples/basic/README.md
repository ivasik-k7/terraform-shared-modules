# basic

The smallest call: a cluster with one Fargate service of two tasks, from a
pinned ECR image, in private subnets.

It acknowledges two advisory checks on purpose:

| Check | Why it is acknowledged here |
|---|---|
| `somebody_hears_a_failure` | No SNS topic yet. In any shared environment, set `sns_topic_arn` instead |
| `logs_use_a_customer_key` | CloudWatch Logs' own encryption. Set `log_kms_key_arn` where a key policy must be able to revoke access |

`network_contract` is exported so the network team sees which endpoints the
subnets need (ECR, the S3 gateway and CloudWatch Logs for this call).
