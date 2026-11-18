# basic

Two repositories for one application, with the module's defaults: immutable
tags, scan on push, your KMS key, and a lifecycle policy that expires untagged
images after 14 days and keeps the newest 100.

Hand `push_policy_json` to the CI role that builds the images, and
`kms_key_policy_requirements` to the key's owner before the first apply.

What fails in it: the key ARN is a placeholder, so it plans (CI plans it
against a mocked provider) and would fail at apply.
