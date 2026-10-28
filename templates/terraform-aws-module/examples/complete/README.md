# complete

Every input: a customer managed key, a year of retention, a group that
survives `terraform destroy`, and tags.

Before the first apply, the key owner needs
`output.kms_key_policy_requirements`: without that statement in the key
policy, creating the log group fails. The key must be in the same region;
the plan refuses one that is not.
