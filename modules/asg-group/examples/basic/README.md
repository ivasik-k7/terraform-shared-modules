# basic

The smallest call: a group of two to four `t3.medium` instances across two
AZs, from a pinned AMI, with an instance role that allows Session Manager and
nothing else. Instance refresh is on, so a new `ami` replaces the instances
with auto rollback.

It acknowledges two advisory checks on purpose:

| Check | Why it is acknowledged here |
|---|---|
| `somebody_hears_a_failure` | No SNS topic yet. In any shared environment, set `sns_topic_arn` |
| `volumes_use_a_customer_key` | Volumes use the account's EBS key. Set `kms_key_arn` where a key policy must be able to revoke access, and hand `kms_key_policy_requirements` to its owner |

`network_contract` is exported so the network team sees the Session Manager
endpoints the subnets need.
