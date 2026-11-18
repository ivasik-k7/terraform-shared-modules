# complete

Every input, shaped like a platform account's registry in eu-west-2:

| Repository | Shows |
|---|---|
| `orders/api` | Immutable tags except `latest`; pull for two workload accounts, push for the CI role |
| `orders/thumbnailer` | A Lambda container image used by functions in a workload account (both statements Lambda needs, so it does not add them itself) |
| `base/python` | Base images readable by every principal in the AWS Organization |
| `releases/orders` | Archiving instead of deleting: images not pulled for 90 days move to archive storage, archives go after seven years |

The registry, managed here and nowhere else: enhanced scanning (Amazon
Inspector) on every repository; replication of `orders` and `base` to
eu-west-1 and to a second account; pull through caches for Docker Hub (with
its secret), ECR Public, and a shared ECR registry in another account (with
the role ECR assumes); creation templates so cache, replica and
create-on-push repositories get your key, a lifecycle policy and the cost
tags; a scanner role that does not reset pull times; and the account settings.

Hand the contract outputs to their owners: `replication_destination_requirements`
to the second account, `kms_key_policy_requirements` to the key's owner,
`deployer_requirements` to whoever owns the apply role,
`notification_requirements` to the topic's owner, and
`pull_through_cache_policy_json` to the node role.

What fails in it: the ARNs are placeholders, so it plans (CI plans it against a
mocked provider) and would fail at apply.
